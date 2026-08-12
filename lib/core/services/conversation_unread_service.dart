import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../constants/api_constants.dart';
import '../models/conversation_models.dart';
import '../models/demande_service_models.dart';
import 'app_refresh_service.dart';
import 'auth_service.dart';
import 'conversation_service.dart';
import 'demande_service_service.dart';

class ConversationUnreadService {
  ConversationUnreadService._();

  static final ConversationUnreadService instance =
      ConversationUnreadService._();

  final ValueNotifier<Map<int, int>> counts = ValueNotifier<Map<int, int>>(
    const {},
  );

  final Map<int, WebSocketChannel> _channels = <int, WebSocketChannel>{};
  final Map<int, StreamSubscription<dynamic>> _subscriptions =
      <int, StreamSubscription<dynamic>>{};
  final Map<int, Conversation> _conversations = <int, Conversation>{};
  final Map<int, int> _messageSequence = <int, int>{};
  final Set<String> _seenMessageKeys = <String>{};
  int? _openConversationId;

  int get totalUnread =>
      counts.value.values.fold<int>(0, (total, count) => total + count);

  int countForConversation(int? conversationId) {
    if (conversationId == null) return 0;
    return counts.value[conversationId] ?? 0;
  }

  int? get latestUnreadConversationId {
    for (final entry
        in _messageSequence.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value))) {
      if ((counts.value[entry.key] ?? 0) > 0) return entry.key;
    }
    return counts.value.keys.isEmpty ? null : counts.value.keys.first;
  }

  Conversation? conversationFor(int conversationId) {
    return _conversations[conversationId];
  }

  Future<void> syncAndWatchConversations() async {
    if (!AuthService.instance.isLoggedIn) {
      clear();
      return;
    }

    try {
      final conversations = await ConversationService.instance
          .getConversations();
      final nextCounts = <int, int>{...counts.value};
      final ids = <int>[];

      for (final conversation in conversations.results) {
        if (conversation.id <= 0) continue;
        ids.add(conversation.id);
        _conversations[conversation.id] = conversation;
        final unread = conversation.unreadCount;
        if (unread != null) {
          if (unread > 0) {
            nextCounts[conversation.id] = unread;
          } else {
            nextCounts.remove(conversation.id);
          }
        }
      }

      _setCounts(nextCounts);
      watchConversations(ids);
    } catch (_) {
      // Keep the realtime state already known if the HTTP sync fails.
    }
  }

  void watchConversations(Iterable<int?> conversationIds) {
    final token = AuthService.instance.currentUser?.token ?? '';
    if (token.isEmpty) return;

    for (final conversationId in conversationIds.whereType<int>()) {
      if (conversationId <= 0 || _channels.containsKey(conversationId)) {
        continue;
      }

      try {
        final channel = WebSocketChannel.connect(
          ApiConstants.conversationWs(conversationId, token),
        );
        _channels[conversationId] = channel;
        unawaited(
          channel.ready.catchError((_) {
            _closeConversationSocket(conversationId);
          }),
        );
        _subscriptions[conversationId] = channel.stream.listen(
          (event) => _handleWsEvent(conversationId, event),
          onError: (_) => _closeConversationSocket(conversationId),
          onDone: () => _closeConversationSocket(conversationId),
        );
      } catch (_) {
        _closeConversationSocket(conversationId);
      }
    }
  }

  void markConversationOpen(int conversationId) {
    _openConversationId = conversationId;
    markConversationRead(conversationId);
  }

  void markConversationClosed(int conversationId) {
    if (_openConversationId == conversationId) _openConversationId = null;
  }

  void markConversationRead(int conversationId) {
    if (!counts.value.containsKey(conversationId)) return;
    final next = <int, int>{...counts.value}..remove(conversationId);
    _setCounts(next);
    AppRefreshService.instance.notify(const {
      AppRefreshTopic.conversations,
      AppRefreshTopic.notifications,
    });
  }

  void clear() {
    for (final sub in _subscriptions.values) {
      unawaited(sub.cancel());
    }
    for (final channel in _channels.values) {
      unawaited(channel.sink.close());
    }
    _subscriptions.clear();
    _channels.clear();
    _conversations.clear();
    _messageSequence.clear();
    _seenMessageKeys.clear();
    _openConversationId = null;
    _setCounts(const {});
  }

  void _handleWsEvent(int conversationId, dynamic event) {
    try {
      final payload = jsonDecode(event as String) as Map<String, dynamic>;
      final type = payload['type'] as String? ?? payload['event'] as String?;
      final data = payload['data'];

      if (type == 'message') {
        final rawMessage = data is Map<String, dynamic> ? data : payload;
        final message = ChatMessage.fromJson(rawMessage);
        _recordIncomingMessage(conversationId, message);
        return;
      }

      if (type == 'read' || type == 'messages_read') {
        final raw = data is Map<String, dynamic> ? data : payload;
        final userId = _parseInt(
          raw['user_id'] ?? raw['reader_id'] ?? raw['destinataire_id'],
        );
        if (userId == AuthService.instance.currentUser?.userId) {
          markConversationRead(conversationId);
        }
      }
    } catch (_) {
      // Ignore malformed realtime payloads without interrupting the app.
    }
  }

  void _recordIncomingMessage(int conversationId, ChatMessage message) {
    if (message.contenu.trim().isEmpty) return;
    final currentUserId = AuthService.instance.currentUser?.userId;
    if (currentUserId != null && message.sender?.id == currentUserId) return;

    final key = _messageKey(conversationId, message);
    if (!_seenMessageKeys.add(key)) return;

    if (_openConversationId == conversationId) {
      markConversationRead(conversationId);
      return;
    }

    final next = <int, int>{...counts.value};
    next[conversationId] = (next[conversationId] ?? 0) + 1;
    _messageSequence[conversationId] = DateTime.now().microsecondsSinceEpoch;
    _setCounts(next);
    AppRefreshService.instance.notify(const {
      AppRefreshTopic.conversations,
      AppRefreshTopic.notifications,
    });
  }

  void _closeConversationSocket(int conversationId) {
    final subscription = _subscriptions.remove(conversationId);
    if (subscription != null) unawaited(subscription.cancel());
    final channel = _channels.remove(conversationId);
    if (channel != null) unawaited(channel.sink.close());
  }

  void _setCounts(Map<int, int> next) {
    counts.value = Map<int, int>.unmodifiable(
      Map<int, int>.fromEntries(next.entries.where((entry) => entry.value > 0)),
    );
  }

  String _messageKey(int conversationId, ChatMessage message) {
    if (message.id > 0) return '$conversationId:${message.id}';
    return [
      conversationId,
      message.sender?.id ?? 0,
      message.dateCreation?.toIso8601String() ?? '',
      message.contenu,
    ].join(':');
  }

  int? _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  Future<DemandeService?> demandeForConversation(int conversationId) async {
    var conversation = _conversations[conversationId];
    if (conversation == null) {
      await syncAndWatchConversations();
      conversation = _conversations[conversationId];
    }
    if (conversation == null) return null;

    try {
      return await DemandeServiceService.instance.getDemande(
        conversation.demande.id,
      );
    } catch (_) {
      return _fallbackDemande(conversation);
    }
  }

  DemandeService _fallbackDemande(Conversation conversation) {
    return DemandeService(
      id: conversation.demande.id,
      client: DemandeServiceClient(
        id: conversation.client.id,
        username: conversation.client.displayName,
        email: '',
      ),
      prestataire: DemandeServicePrestataire(
        id: conversation.prestataire.id,
        typeService: conversation.prestataire.typeService,
      ),
      description: 'Conversation',
      dateSouhaitee: DateTime.now(),
      lieuIntervention: '',
      statut: conversation.demande.statut,
      conversationId: conversation.id,
    );
  }

  String titleFor(Conversation conversation) {
    final user = AuthService.instance.currentUser;
    if (user?.estPrestataire == true) return conversation.client.displayName;
    return conversation.prestataire.typeService;
  }
}
