import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../constants/api_constants.dart';
import '../models/prestataire_models.dart';

class PrestataireRealtimeService {
  PrestataireRealtimeService._();

  static final PrestataireRealtimeService instance =
      PrestataireRealtimeService._();

  final ValueNotifier<int> changes = ValueNotifier<int>(0);
  final Map<int, _PrestataireAvailability> _updates =
      <int, _PrestataireAvailability>{};

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  int _watchers = 0;
  int _attempt = 0;

  void watch() {
    _watchers++;
    if (_channel != null) return;
    _connect();
  }

  void unwatch() {
    if (_watchers > 0) _watchers--;
    if (_watchers == 0) _close();
  }

  Prestataire applyTo(Prestataire prestataire) {
    final update = _updates[prestataire.id];
    if (update == null) return prestataire;
    return prestataire.copyWith(
      isAvailable: update.isAvailable,
      estValide: update.estValide,
    );
  }

  void registerPrestataires(Iterable<Prestataire> prestataires) {
    for (final prestataire in prestataires) {
      if (prestataire.id <= 0) continue;
      _updates[prestataire.id] = _PrestataireAvailability(
        prestataireId: prestataire.id,
        isAvailable: prestataire.isAvailable,
        estValide: prestataire.estValide,
      );
    }
  }

  List<Prestataire> applyToList(List<Prestataire> prestataires) {
    return prestataires.map(applyTo).toList();
  }

  void _connect() {
    if (_watchers <= 0) return;
    _close(keepReconnect: true);
    final uri = ApiConstants.prestatairesWs();
    try {
      if (kDebugMode) {
        debugPrint('[PrestataireRealtime] connecting $uri');
      }
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      unawaited(
        channel.ready
            .then((_) {
              _attempt = 0;
              if (kDebugMode) {
                debugPrint('[PrestataireRealtime] connected $uri');
              }
            })
            .catchError((Object error) {
              if (kDebugMode) {
                debugPrint('[PrestataireRealtime] ready failed: $error');
              }
              _scheduleReconnect();
            }),
      );
      _subscription = channel.stream.listen(
        _handleEvent,
        onError: (Object error) {
          if (kDebugMode) {
            debugPrint('[PrestataireRealtime] stream error: $error');
          }
          _scheduleReconnect();
        },
        onDone: _scheduleReconnect,
      );
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[PrestataireRealtime] connect failed: $error');
      }
      _scheduleReconnect();
    }
  }

  void _handleEvent(dynamic event) {
    try {
      final payload = _decode(event);
      if (payload == null) return;
      final type = (payload['type'] ?? payload['event'])?.toString();
      final action = payload['action']?.toString();
      if (type != null &&
          type != 'prestataire_availability' &&
          type != 'availability_update' &&
          type != 'status_update' &&
          action != 'prestataire_availability') {
        return;
      }
      final data = _mapValue(payload, const ['data', 'payload']) ?? payload;
      final update = _PrestataireAvailability.fromJson(data);
      if (update == null) return;
      _updates[update.prestataireId] = update;
      if (kDebugMode) {
        debugPrint(
          '[PrestataireRealtime] availability '
          'prestataire=${update.prestataireId} available=${update.isAvailable}',
        );
      }
      changes.value++;
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('[PrestataireRealtime] ignored event=$event');
        debugPrint('$error');
        debugPrint('$stackTrace');
      }
    }
  }

  void _scheduleReconnect() {
    if (_watchers <= 0 || _reconnectTimer != null) return;
    _close(keepReconnect: true);
    final seconds = _attempt < 4 ? 1 << _attempt : 16;
    _attempt++;
    _reconnectTimer = Timer(Duration(seconds: seconds), () {
      _reconnectTimer = null;
      _connect();
    });
  }

  void _close({bool keepReconnect = false}) {
    if (!keepReconnect) {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
    }
    unawaited(_subscription?.cancel());
    unawaited(_channel?.sink.close());
    _subscription = null;
    _channel = null;
  }

  Map<String, dynamic>? _decode(dynamic event) {
    if (event is Map<String, dynamic>) return event;
    if (event is String && event.trim().isNotEmpty) {
      final decoded = jsonDecode(event);
      if (decoded is Map<String, dynamic>) return decoded;
    }
    return null;
  }

  Map<String, dynamic>? _mapValue(
    Map<String, dynamic> source,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = source[key];
      if (value is Map<String, dynamic>) return value;
    }
    return null;
  }
}

class _PrestataireAvailability {
  const _PrestataireAvailability({
    required this.prestataireId,
    required this.isAvailable,
    this.estValide,
  });

  final int prestataireId;
  final bool isAvailable;
  final bool? estValide;

  static _PrestataireAvailability? fromJson(Map<String, dynamic> json) {
    final prestataire = json['prestataire'];
    final prestataireId = _parseInt(
      json['id'] ??
          json['prestataire_id'] ??
          json['prestataireId'] ??
          (prestataire is Map<String, dynamic> ? prestataire['id'] : null) ??
          prestataire,
    );
    if (prestataireId <= 0) return null;
    return _PrestataireAvailability(
      prestataireId: prestataireId,
      isAvailable: _parseBool(
        json['is_available'] ??
            json['isAvailable'] ??
            json['available'] ??
            json['disponible'] ??
            json['est_disponible'] ??
            json['estDisponible'] ??
            (prestataire is Map<String, dynamic>
                ? prestataire['is_available'] ??
                      prestataire['isAvailable'] ??
                      prestataire['available'] ??
                      prestataire['disponible']
                : null),
      ),
      estValide: json.containsKey('est_valide')
          ? _parseBool(json['est_valide'])
          : null,
    );
  }
}

int _parseInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

bool _parseBool(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final lower = value.toLowerCase().trim();
    return lower == 'true' ||
        lower == '1' ||
        lower == 'yes' ||
        lower == 'available' ||
        lower == 'disponible';
  }
  return false;
}
