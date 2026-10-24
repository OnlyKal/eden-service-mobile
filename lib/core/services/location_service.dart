import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/api_constants.dart';
import 'auth_service.dart';

/// Position GPS de l'appareil, pour afficher la distance aux prestataires.
///
/// Ne lève jamais d'erreur : sans permission, sans GPS ou en cas de délai
/// dépassé, la position vaut simplement null et l'app fonctionne comme avant.
class LocationService {
  LocationService._();
  static final LocationService instance = LocationService._();

  static const _cacheDuration = Duration(minutes: 5);
  static const _kProviderSyncKey = 'provider_position_sync';

  /// Le prestataire renvoie sa position s'il a bougé de plus de 100 m ou
  /// si la dernière date de plus de 6 h.
  static const _providerSyncDistanceMeters = 100.0;
  static const _providerSyncMaxAge = Duration(hours: 6);

  Position? _position;
  DateTime? _positionAt;
  Future<Position?>? _pending;

  /// Dernière position connue en mémoire, sans attendre le GPS.
  Position? get lastPosition => _position;

  /// Position actuelle (mise en cache 5 min). Demande la permission au
  /// premier appel si nécessaire.
  Future<Position?> currentPosition() {
    final at = _positionAt;
    if (_position != null &&
        at != null &&
        DateTime.now().difference(at) < _cacheDuration) {
      return Future.value(_position);
    }
    return _pending ??= _readPosition().whenComplete(() => _pending = null);
  }

  Future<Position?> _readPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return _position;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 12),
          ),
        );
      } catch (_) {
        // GPS trop lent : la dernière position du système suffit pour une
        // distance indicative (indisponible sur le web).
        if (!kIsWeb) position = await Geolocator.getLastKnownPosition();
      }
      if (position != null) {
        _position = position;
        _positionAt = DateTime.now();
      }
      return _position;
    } catch (error) {
      if (kDebugMode) debugPrint('[Location] position indisponible: $error');
      return _position;
    }
  }

  /// Envoie la position du prestataire connecté, pour que les clients
  /// voient à quelle distance il se trouve. Sa position n'est jamais
  /// montrée aux clients, seulement la distance.
  Future<void> syncProviderPosition() async {
    final user = AuthService.instance.currentUser;
    if (user == null || !user.hasProviderProfile) return;
    final position = await currentPosition();
    if (position == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = _decodeSync(prefs.getString(_kProviderSyncKey));
      if (last != null && last.userId == user.userId) {
        final moved = Geolocator.distanceBetween(
          last.latitude,
          last.longitude,
          position.latitude,
          position.longitude,
        );
        if (moved < _providerSyncDistanceMeters &&
            DateTime.now().difference(last.at) < _providerSyncMaxAge) {
          return;
        }
      }
      final response = await http
          .post(
            Uri.parse(ApiConstants.maPositionPrestataire),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': user.token,
            },
            body: jsonEncode({
              'latitude': position.latitude,
              'longitude': position.longitude,
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        await prefs.setString(
          _kProviderSyncKey,
          jsonEncode({
            'user_id': user.userId,
            'latitude': position.latitude,
            'longitude': position.longitude,
            'at': DateTime.now().toIso8601String(),
          }),
        );
      }
    } catch (error) {
      if (kDebugMode)
        debugPrint('[Location] envoi position impossible: $error');
    }
  }

  _ProviderSync? _decodeSync(String? raw) {
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return _ProviderSync(
        userId: json['user_id'] as int,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        at: DateTime.parse(json['at'] as String),
      );
    } catch (_) {
      return null;
    }
  }
}

class _ProviderSync {
  const _ProviderSync({
    required this.userId,
    required this.latitude,
    required this.longitude,
    required this.at,
  });

  final int userId;
  final double latitude;
  final double longitude;
  final DateTime at;
}

/// « à 350 m », « à 2,4 km », « à 15 km ».
String formatDistance(double km) {
  if (km < 0.05) return 'à moins de 50 m';
  if (km < 1) {
    final meters = (km * 1000 / 10).round() * 10;
    return meters >= 1000 ? 'à 1 km' : 'à $meters m';
  }
  if (km < 10) {
    final rounded = (km * 10).round() / 10;
    final text = rounded == rounded.roundToDouble()
        ? rounded.toStringAsFixed(0)
        : rounded.toStringAsFixed(1).replaceAll('.', ',');
    return 'à $text km';
  }
  return 'à ${km.round()} km';
}
