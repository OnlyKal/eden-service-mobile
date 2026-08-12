import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../constants/api_constants.dart';
import 'app_refresh_service.dart';
import 'auth_service.dart';

class UserRealtimeService {
  UserRealtimeService._();

  static final UserRealtimeService instance = UserRealtimeService._();

  final StreamController<UserRealtimeEvent> _events =
      StreamController<UserRealtimeEvent>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  int _watchers = 0;
  int _attempt = 0;
  bool _connecting = false;

  Stream<UserRealtimeEvent> get events => _events.stream;

  void watch() {
    final token = AuthService.instance.currentUser?.token;
    if (token == null || token.trim().isEmpty) return;

    _watchers++;
    if (_channel != null || _connecting) return;
    _connect(token);
  }

  void unwatch() {
    if (_watchers > 0) _watchers--;
    if (_watchers == 0) _closeSocket();
  }

  void clear() {
    _watchers = 0;
    _closeSocket();
  }

  void _connect(String token) {
    if (_watchers <= 0 || _connecting) return;
    _connecting = true;
    _reconnectTimer?.cancel();

    try {
      final channel = WebSocketChannel.connect(
        ApiConstants.userRealtimeWs(token),
      );
      _channel = channel;
      unawaited(
        channel.ready
            .then((_) {
              _attempt = 0;
              _connecting = false;
            })
            .catchError((_) {
              _connecting = false;
              _scheduleReconnect();
            }),
      );
      _subscription = channel.stream.listen(
        _handleWsEvent,
        onError: (_) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
      );
    } catch (_) {
      _connecting = false;
      _scheduleReconnect();
    }
  }

  void _handleWsEvent(dynamic event) {
    try {
      final payload = jsonDecode(event as String) as Map<String, dynamic>;
      final type = payload['type'] as String? ?? payload['event'] as String?;
      if (type == null || type.trim().isEmpty) return;
      _events.add(UserRealtimeEvent(type: type, payload: payload));
      if (type == 'demande_status') {
        AppRefreshService.instance.notify(const {
          AppRefreshTopic.demandes,
          AppRefreshTopic.conversations,
        });
      } else if (type == 'paiement_status') {
        AppRefreshService.instance.notify(const {
          AppRefreshTopic.abonnement,
          AppRefreshTopic.profile,
          AppRefreshTopic.home,
        });
      }
    } catch (error) {
      if (kDebugMode) debugPrint('[UserRealtime] ignored event: $error');
    }
  }

  void _scheduleReconnect() {
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
    _connecting = false;
    if (_watchers <= 0 || !AuthService.instance.isLoggedIn) return;

    final token = AuthService.instance.currentUser?.token;
    if (token == null || token.trim().isEmpty) return;
    final seconds = _attempt < 2 ? 2 : 5;
    _attempt++;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: seconds), () => _connect(token));
  }

  void _closeSocket() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
    _connecting = false;
    _attempt = 0;
  }
}

class UserRealtimeEvent {
  const UserRealtimeEvent({required this.type, required this.payload});

  final String type;
  final Map<String, dynamic> payload;

  Map<String, dynamic> get data {
    final value = payload['data'];
    return value is Map<String, dynamic> ? value : payload;
  }
}

class DemandeStatusRealtimeEvent {
  const DemandeStatusRealtimeEvent({
    required this.id,
    required this.statut,
    this.statutLabel,
    this.previousStatut,
    this.clientId,
    this.prestataireId,
    this.prestataireUtilisateurId,
    this.conversationId,
    this.dateModification,
  });

  final int id;
  final String statut;
  final String? statutLabel;
  final String? previousStatut;
  final int? clientId;
  final int? prestataireId;
  final int? prestataireUtilisateurId;
  final int? conversationId;
  final DateTime? dateModification;

  static DemandeStatusRealtimeEvent? fromUserEvent(UserRealtimeEvent event) {
    if (event.type != 'demande_status') return null;
    return fromJson(event.data);
  }

  static DemandeStatusRealtimeEvent? fromJson(Map<String, dynamic> json) {
    final id = _parseInt(json['id']);
    final statut = json['statut']?.toString();
    if (id <= 0 || statut == null || statut.isEmpty) return null;
    return DemandeStatusRealtimeEvent(
      id: id,
      statut: statut,
      statutLabel: json['statut_label']?.toString(),
      previousStatut: json['previous_statut']?.toString(),
      clientId: _parseNullableInt(json['client']),
      prestataireId: _parseNullableInt(json['prestataire']),
      prestataireUtilisateurId: _parseNullableInt(
        json['prestataire_utilisateur'],
      ),
      conversationId: _parseNullableInt(json['conversation_id']),
      dateModification: DateTime.tryParse(
        json['date_modification']?.toString() ?? '',
      ),
    );
  }
}

class PaiementStatusRealtimeEvent {
  const PaiementStatusRealtimeEvent({
    required this.id,
    required this.statut,
    this.statutLabel,
    this.previousStatut,
    this.utilisateurId,
    this.abonnementId,
    this.prestataireId,
    this.montant,
    this.devise,
    this.orderNumber,
    this.referenceTransaction,
  });

  final int id;
  final String statut;
  final String? statutLabel;
  final String? previousStatut;
  final int? utilisateurId;
  final int? abonnementId;
  final int? prestataireId;
  final String? montant;
  final String? devise;
  final String? orderNumber;
  final String? referenceTransaction;

  static PaiementStatusRealtimeEvent? fromUserEvent(UserRealtimeEvent event) {
    if (event.type != 'paiement_status') return null;
    return fromJson(event.data);
  }

  static PaiementStatusRealtimeEvent? fromJson(Map<String, dynamic> json) {
    final id = _parseInt(json['id']);
    final statut = json['statut']?.toString();
    if (id <= 0 || statut == null || statut.isEmpty) return null;
    return PaiementStatusRealtimeEvent(
      id: id,
      statut: statut,
      statutLabel: json['statut_label']?.toString(),
      previousStatut: json['previous_statut']?.toString(),
      utilisateurId: _parseNullableInt(json['utilisateur']),
      abonnementId: _parseNullableInt(json['abonnement']),
      prestataireId: _parseNullableInt(json['prestataire']),
      montant: json['montant']?.toString(),
      devise: json['devise']?.toString(),
      orderNumber: json['order_number']?.toString(),
      referenceTransaction: json['reference_transaction']?.toString(),
    );
  }

  bool get isSuccess {
    final normalized = statut.toLowerCase();
    return normalized == 'success' || normalized == 'complete';
  }

  bool get isFailed {
    final normalized = statut.toLowerCase();
    return normalized == 'failed' || normalized == 'echoue';
  }

  bool get isRefunded {
    final normalized = statut.toLowerCase();
    return normalized == 'refunded' || normalized == 'rembourse';
  }

  bool get isCancelled => statut.toLowerCase() == 'cancelled';
}

int _parseInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

int? _parseNullableInt(dynamic value) {
  final parsed = _parseInt(value);
  return parsed > 0 ? parsed : null;
}
