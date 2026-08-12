import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/constants/api_constants.dart';
import '../core/models/conversation_models.dart';
import '../core/models/demande_service_models.dart';
import '../core/services/auth_service.dart';
import '../core/services/conversation_service.dart';
import '../core/services/conversation_unread_service.dart';
import '../core/services/demande_service_service.dart';
import '../core/services/user_realtime_service.dart';
import '../theme/app_colors.dart';
import '../widgets/gradient_background.dart';

class ConversationScreen extends StatefulWidget {
  ConversationScreen({
    super.key,
    required this.demande,
    this.title,
    this.allowAcceptPrestation = false,
  });

  final DemandeService demande;
  final String? title;
  final bool allowAcceptPrestation;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final TextEditingController _messageCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final List<ChatMessage> _messages = [];
  Conversation? _conversation;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _wsSub;
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  bool _loading = true;
  bool _sending = false;
  bool _accepting = false;
  bool _conversationUnavailable = false;
  late String _currentStatut;
  String _connectionLabel = 'Connexion en cours';

  @override
  void initState() {
    super.initState();
    _currentStatut = widget.demande.statut;
    _initChat();
  }

  @override
  void dispose() {
    final conversationId = _conversation?.id;
    if (conversationId != null) {
      ConversationUnreadService.instance.markConversationClosed(conversationId);
    }
    _wsSub?.cancel();
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _messageCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _initChat() async {
    try {
      final conversation = await _resolveConversation();
      final messages = await ConversationService.instance.getMessages(
        conversation.id,
      );
      if (!mounted) return;
      setState(() {
        _conversation = conversation;
        _conversationUnavailable = false;
        _messages
          ..clear()
          ..addAll(messages);
        _loading = false;
      });
      ConversationUnreadService.instance.markConversationOpen(conversation.id);
      _connectWs(conversation.id);
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _conversationUnavailable = true;
        _connectionLabel = 'Aucun message';
      });
    }
  }

  Future<Conversation> _resolveConversation() async {
    if (_conversation != null) return _conversation!;
    if (widget.demande.conversationId != null) {
      return Conversation(
        id: widget.demande.conversationId!,
        demande: ConversationDemande(
          id: widget.demande.id,
          statut: widget.demande.statut,
          conversationId: widget.demande.conversationId,
        ),
        client: ConversationClient(
          id: widget.demande.client.id,
          username: widget.demande.client.username,
          firstName: widget.demande.client.firstName,
          lastName: widget.demande.client.lastName,
        ),
        prestataire: ConversationPrestataire(
          id: widget.demande.prestataire.id,
          typeService: widget.demande.prestataire.typeService ?? 'Service',
        ),
      );
    }
    return ConversationService.instance.getConversationForDemande(
      widget.demande.id,
    );
  }

  void _connectWs(int conversationId) {
    _reconnectTimer?.cancel();
    _wsSub?.cancel();
    _channel?.sink.close();
    final token = AuthService.instance.currentUser?.token ?? '';
    final uri = ApiConstants.conversationWs(conversationId, token);

    try {
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      setState(() => _connectionLabel = 'Connexion en cours');
      unawaited(
        channel.ready
            .then((_) {
              if (mounted) setState(() => _connectionLabel = 'Connecté');
              _reconnectAttempt = 0;
            })
            .catchError((_) {
              if (mounted) setState(() => _connectionLabel = 'Hors ligne');
              _scheduleConversationReconnect(conversationId);
            }),
      );
      _wsSub = channel.stream.listen(
        _handleWsEvent,
        onError: (_) {
          if (mounted) setState(() => _connectionLabel = 'Connexion instable');
          _scheduleConversationReconnect(conversationId);
        },
        onDone: () {
          if (mounted) setState(() => _connectionLabel = 'Hors ligne');
          _scheduleConversationReconnect(conversationId);
        },
      );
    } catch (_) {
      if (mounted) setState(() => _connectionLabel = 'Hors ligne');
      _scheduleConversationReconnect(conversationId);
    }
  }

  void _scheduleConversationReconnect(int conversationId) {
    if (!mounted || _reconnectTimer != null) return;
    _wsSub?.cancel();
    _wsSub = null;
    _channel?.sink.close();
    _channel = null;
    final seconds = _reconnectAttempt < 2 ? 2 : 5;
    _reconnectAttempt++;
    _reconnectTimer = Timer(Duration(seconds: seconds), () {
      _reconnectTimer = null;
      if (mounted) _connectWs(conversationId);
    });
  }

  void _handleWsEvent(dynamic event) {
    try {
      final payload = jsonDecode(event as String) as Map<String, dynamic>;
      final type = payload['type'] as String? ?? payload['event'] as String?;
      final data = payload['data'];

      if (type == 'message') {
        final rawMessage = data is Map<String, dynamic> ? data : payload;
        final message = ChatMessage.fromJson(rawMessage);
        if (message.contenu.trim().isEmpty) return;
        final conversationId = _conversation?.id;
        if (conversationId != null) {
          ConversationUnreadService.instance.markConversationRead(
            conversationId,
          );
        }
        setState(() => _upsertServerMessage(message));
        _scrollToBottom();
        return;
      }

      if (type == 'notification') {
        final text = data is Map<String, dynamic>
            ? data['message'] as String?
            : payload['message'] as String?;
        if (text != null && text.isNotEmpty) _showSnack(text);
        return;
      }

      if (type == 'demande_status') {
        final raw = data is Map<String, dynamic> ? data : payload;
        final demandeEvent = DemandeStatusRealtimeEvent.fromJson(raw);
        if (demandeEvent == null) return;
        if (demandeEvent.id != widget.demande.id) return;
        setState(() => _currentStatut = demandeEvent.statut);
        return;
      }

      if (type == 'demande') {
        final statut = data is Map<String, dynamic>
            ? data['statut'] as String?
            : payload['statut'] as String?;
        if (statut != null && statut.isNotEmpty) {
          setState(() => _currentStatut = statut);
        }
      }
    } catch (_) {
      // Ignore malformed realtime payloads without breaking the chat.
    }
  }

  Future<void> _sendMessage() async {
    final contenu = _messageCtrl.text.trim();
    if (contenu.isEmpty || _sending || _loading) return;

    Conversation conversation;
    try {
      setState(() => _sending = true);
      conversation = await _resolveConversation();
      if (!mounted) return;
      if (_conversation == null) {
        setState(() {
          _conversation = conversation;
          _conversationUnavailable = false;
          _connectionLabel = 'Connecté';
        });
        _connectWs(conversation.id);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _conversationUnavailable = true;
          _connectionLabel = 'Aucun message';
        });
      }
      return;
    }

    _messageCtrl.clear();
    final local = ChatMessage(
      id: DateTime.now().microsecondsSinceEpoch * -1,
      contenu: contenu,
      sender: ChatSender(
        id: AuthService.instance.currentUser?.userId ?? 0,
        username: AuthService.instance.currentUser?.username ?? '',
        firstName: AuthService.instance.currentUser?.firstName ?? '',
        lastName: AuthService.instance.currentUser?.lastName ?? '',
      ),
      dateCreation: DateTime.now(),
      isLocalPending: true,
    );
    setState(() => _messages.add(local));
    _scrollToBottom();

    try {
      if (_channel != null) {
        _channel!.sink.add(jsonEncode({'contenu': contenu}));
      } else {
        final sent = await ConversationService.instance.sendMessage(
          conversation.id,
          contenu,
        );
        if (mounted) setState(() => _upsertServerMessage(sent));
      }
    } catch (_) {
      try {
        final sent = await ConversationService.instance.sendMessage(
          conversation.id,
          contenu,
        );
        if (mounted) setState(() => _upsertServerMessage(sent));
      } catch (_) {
        if (mounted) _showSnack('Message non envoyé. Réessayez.');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _upsertServerMessage(ChatMessage message) {
    if (message.id != 0) {
      final sameIdIndex = _messages.indexWhere((item) => item.id == message.id);
      if (sameIdIndex != -1) {
        _messages[sameIdIndex] = message;
        return;
      }
    }

    final currentUserId = AuthService.instance.currentUser?.userId;
    final pendingIndex = _messages.indexWhere((item) {
      final sameText = item.contenu.trim() == message.contenu.trim();
      final sameSender =
          message.sender?.id == null ||
          message.sender?.id == 0 ||
          message.sender?.id == currentUserId;
      final recent =
          item.dateCreation == null ||
          message.dateCreation == null ||
          message.dateCreation!.difference(item.dateCreation!).inSeconds.abs() <
              30;
      return item.isLocalPending && sameText && sameSender && recent;
    });
    if (pendingIndex != -1) {
      _messages[pendingIndex] = message;
      return;
    }

    final sameRecentMessage = _messages.any((item) {
      final sameText = item.contenu.trim() == message.contenu.trim();
      final sameSender = item.sender?.id == message.sender?.id;
      final recent =
          item.dateCreation != null &&
          message.dateCreation != null &&
          message.dateCreation!.difference(item.dateCreation!).inSeconds.abs() <
              5;
      return sameText && sameSender && recent;
    });
    if (!sameRecentMessage) _messages.add(message);
  }

  Future<void> _acceptPrestation() async {
    if (_accepting || _currentStatut != 'en_attente') return;
    setState(() => _accepting = true);
    try {
      await DemandeServiceService.instance.accepterDemande(widget.demande.id);
      if (!mounted) return;
      setState(() => _currentStatut = 'acceptee');
      _showSnack('Prestation acceptée. Le client est notifié.');
    } catch (_) {
      if (mounted) {
        _showSnack('Impossible de confirmer la prestation pour le moment.');
      }
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent + 80,
        duration: Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _showSnack(String message) {
    debugPrint('[Conversation] $message');
  }

  @override
  Widget build(BuildContext context) {
    final title =
        widget.title ??
        '${widget.demande.prestataire.typeService ?? 'Service'} #${widget.demande.id}';
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              _ChatHeader(
                title: title,
                subtitle: _connectionLabel,
                onBack: () => Navigator.maybePop(context),
              ),
              if (widget.allowAcceptPrestation &&
                  _currentStatut == 'en_attente')
                _AcceptAgreementBar(
                  accepting: _accepting,
                  onAccept: _acceptPrestation,
                )
              else if (widget.allowAcceptPrestation &&
                  _currentStatut == 'acceptee')
                _AcceptedBar(),
              Expanded(
                child: _loading
                    ? Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                          strokeWidth: 2.4,
                        ),
                      )
                    : _conversationUnavailable || _messages.isEmpty
                    ? _EmptyMessages()
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: EdgeInsets.fromLTRB(18, 12, 18, 18),
                        itemCount: _messages.length,
                        itemBuilder: (_, index) {
                          final message = _messages[index];
                          final mine =
                              message.sender?.id ==
                              AuthService.instance.currentUser?.userId;
                          return _MessageBubble(message: message, mine: mine);
                        },
                      ),
              ),
              _Composer(
                controller: _messageCtrl,
                sending: _sending,
                enabled: !_loading,
                onSend: _sendMessage,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatHeader extends StatelessWidget {
  _ChatHeader({
    required this.title,
    required this.subtitle,
    required this.onBack,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 14, 18, 8),
      child: Row(
        children: [
          _IconBubble(icon: Icons.arrow_back_rounded, onTap: onBack),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: AppColors.textHint,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  _MessageBubble({required this.message, required this.mine});
  final ChatMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: 290),
        margin: EdgeInsets.only(bottom: 10),
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          gradient: mine ? AppColors.primaryGradient : null,
          color: mine ? null : Colors.white.withValues(alpha: 0.82),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 5),
            bottomRight: Radius.circular(mine ? 5 : 16),
          ),
          border: mine
              ? null
              : Border.all(color: AppColors.glassBorder, width: 1.1),
        ),
        child: Column(
          crossAxisAlignment: mine
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Text(
              message.contenu,
              style: TextStyle(
                color: mine ? Colors.white : AppColors.textPrimary,
                fontSize: 14,
                height: 1.35,
              ),
            ),
            SizedBox(height: 4),
            Text(
              message.isLocalPending
                  ? 'envoi...'
                  : _formatTime(message.dateCreation),
              style: TextStyle(
                color: mine
                    ? Colors.white.withValues(alpha: 0.72)
                    : AppColors.textHint,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyMessages extends StatelessWidget {
  _EmptyMessages();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                color: AppColors.primarySurface,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.chat_bubble_outline_rounded,
                color: AppColors.primary,
                size: 34,
              ),
            ),
            SizedBox(height: 14),
            Text(
              'Aucun message',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AcceptAgreementBar extends StatelessWidget {
  _AcceptAgreementBar({required this.accepting, required this.onAccept});

  final bool accepting;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 6, 18, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.84),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.glassBorder, width: 1.1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Accord trouvé ?',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Vous pouvez continuer à discuter ou confirmer maintenant la prestation.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
                SizedBox(height: 12),
                GestureDetector(
                  onTap: accepting ? null : onAccept,
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (accepting)
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        else
                          Icon(
                            Icons.check_circle_outline_rounded,
                            color: Colors.white,
                            size: 19,
                          ),
                        SizedBox(width: 8),
                        Text(
                          'Accepter la prestation',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AcceptedBar extends StatelessWidget {
  _AcceptedBar();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 6, 18, 8),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.success.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(Icons.verified_rounded, color: AppColors.success, size: 18),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Prestation acceptée. La discussion reste ouverte.',
                style: TextStyle(
                  color: AppColors.success,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  _Composer({
    required this.controller,
    required this.sending,
    required this.enabled,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final bool enabled;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.86),
            border: Border.all(color: AppColors.glassBorder, width: 1.1),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => enabled ? onSend() : null,
                  decoration: InputDecoration(
                    hintText: 'Écrire un message...',
                    filled: true,
                    fillColor: AppColors.primarySurface.withValues(alpha: 0.55),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
              SizedBox(width: 10),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) {
                  final canSend =
                      enabled && !sending && value.text.trim().isNotEmpty;
                  return GestureDetector(
                    onTap: canSend ? onSend : null,
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        gradient: canSend ? AppColors.primaryGradient : null,
                        color: canSend ? null : AppColors.textHint,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: sending
                          ? Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Icon(Icons.send_rounded, color: Colors.white),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconBubble extends StatelessWidget {
  _IconBubble({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.glassBorder, width: 1.1),
        ),
        child: Icon(icon, color: AppColors.primary, size: 20),
      ),
    );
  }
}

String _formatTime(DateTime? value) {
  if (value == null) return '';
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}
