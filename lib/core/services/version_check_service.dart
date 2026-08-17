import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/api_constants.dart';
import '../models/version_app_models.dart';
import '../utils/version_comparator.dart';

/// Résultat de la vérification de version.
enum VersionCheckResult {
  /// Version installée = version serveur → continuer normalement.
  upToDate,

  /// Version installée < version serveur et `est_actif = true`.
  updateAvailable,

  /// Version installée > version serveur (version plus récente que le serveur).
  newerThanServer,

  /// L'API est inaccessible ou a retourné une erreur → ne pas bloquer.
  error,
}

/// Service centralisé de vérification de version.
///
/// Récupère la version installée depuis les informations natives de
/// l'application, appelle l'API Django, compare les versions et expose
/// le résultat pour afficher les modales de mise à jour.
class VersionCheckService {
  VersionCheckService._();
  static final VersionCheckService instance = VersionCheckService._();

  static const _kLastCheckKey = 'version_check_last_timestamp';
  static const _kLastResultKey = 'version_check_last_result';

  /// Intervalle minimum entre deux vérifications automatiques (5 minutes).
  static const _minCheckInterval = Duration(minutes: 5);

  /// Version installée sur le téléphone (chargée une seule fois).
  String? _installedVersion;

  /// Dernière version serveur connue.
  VersionApp? _lastServerVersion;

  /// Indique si une vérification est en cours.
  bool _isChecking = false;

  /// Timestamp de la dernière vérification réussie.
  DateTime? _lastCheckTime;

  /// Version installée sur le téléphone.
  String? get installedVersion => _installedVersion;

  /// Dernière version serveur connue.
  VersionApp? get lastServerVersion => _lastServerVersion;

  /// Indique si une vérification est en cours.
  bool get isChecking => _isChecking;

  /// Charge la version installée depuis les informations natives.
  Future<String?> loadInstalledVersion() async {
    if (_installedVersion != null) return _installedVersion;
    try {
      final info = await PackageInfo.fromPlatform();
      _installedVersion = info.version;
      if (kDebugMode) {
        debugPrint('[VersionCheck] Version installée: ${info.version} '
            '(build ${info.buildNumber})');
      }
      return _installedVersion;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[VersionCheck] Impossible de lire la version installée: $e');
      }
      return null;
    }
  }

  /// Récupère la version actuelle depuis l'API Django.
  Future<VersionApp?> fetchServerVersion() async {
    try {
      final response = await http
          .get(Uri.parse(ApiConstants.versionAppActuelle))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        if (kDebugMode) {
          debugPrint(
            '[VersionCheck] API retourné status ${response.statusCode}',
          );
        }
        return null;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;

      // La réponse est enveloppée dans `data`.
      final data = decoded['data'];
      if (data is! Map<String, dynamic>) return null;

      final version = VersionApp.fromJson(data);
      _lastServerVersion = version;
      return version;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[VersionCheck] Erreur réseau: $e');
      }
      return null;
    }
  }

  /// Effectue une vérification complète de version.
  ///
  /// Retourne le résultat de la comparaison. En cas d'erreur réseau,
  /// retourne [VersionCheckResult.error] pour ne pas bloquer l'utilisateur.
  Future<VersionCheckResult> checkForUpdate({
    bool force = false,
  }) async {
    // Restaure l'état persisté au premier appel.
    if (_lastCheckTime == null && _lastResult == null) {
      await _loadPersistedResult();
    }

    // Évite les vérifications concurrentes.
    if (_isChecking) {
      return _lastResult ?? VersionCheckResult.error;
    }

    // Évite les vérifications trop fréquentes (sauf si force = true).
    if (!force && !_shouldCheckAgain()) {
      return _lastResult ?? VersionCheckResult.error;
    }

    _isChecking = true;
    try {
      // 1. Récupère la version installée.
      final installed = await loadInstalledVersion();
      if (installed == null || installed.trim().isEmpty) {
        if (kDebugMode) {
          debugPrint('[VersionCheck] Version installée introuvable.');
        }
        return VersionCheckResult.error;
      }

      // 2. Récupère la version serveur.
      final serverVersion = await fetchServerVersion();
      if (serverVersion == null) {
        if (kDebugMode) {
          debugPrint('[VersionCheck] Version serveur introuvable.');
        }
        return VersionCheckResult.error;
      }

      final serverVersionStr = serverVersion.version.trim();
      if (serverVersionStr.isEmpty) {
        if (kDebugMode) {
          debugPrint('[VersionCheck] Version serveur vide.');
        }
        return VersionCheckResult.error;
      }

      // 3. Compare les versions.
      final comparison = VersionComparator.compare(installed, serverVersionStr);

      VersionCheckResult result;
      if (comparison == 0) {
        result = VersionCheckResult.upToDate;
      } else if (comparison < 0) {
        result = VersionCheckResult.updateAvailable;
      } else {
        result = VersionCheckResult.newerThanServer;
      }

      // 4. Si le contrôle n'est pas actif, ne pas bloquer.
      if (result == VersionCheckResult.updateAvailable &&
          !serverVersion.estActif) {
        result = VersionCheckResult.upToDate;
      }

      _lastResult = result;
      _lastCheckTime = DateTime.now();
      await _persistResult(result);

      if (kDebugMode) {
        debugPrint(
          '[VersionCheck] Installée=$installed, Serveur=$serverVersionStr, '
          'Résultat=$result, estActif=${serverVersion.estActif}, '
          'estObligatoire=${serverVersion.estObligatoire}',
        );
      }

      return result;
    } finally {
      _isChecking = false;
    }
  }

  /// Retourne `true` si une mise à jour est disponible et obligatoire.
  bool get isUpdateMandatory {
    final server = _lastServerVersion;
    if (server == null) return false;
    return server.estActif && server.estObligatoire;
  }

  /// Retourne `true` si une mise à jour est disponible (obligatoire ou non).
  bool get isUpdateAvailable {
    final server = _lastServerVersion;
    if (server == null) return false;
    return server.estActif;
  }

  /// URL officielle de l'application sur Google Play (Android).
  static const String _androidStoreUrl =
      'https://play.google.com/store/apps/details?id=com.app.mt'
      '&pcampaignid=web_share';

  /// URL officielle de l'application sur l'App Store (iOS).
  static const String _iosStoreUrl =
      'https://apps.apple.com/cd/app/zwacop/id6449708415?l=fr-FR';

  /// Ouvre la page officielle de l'application sur le store.
  ///
  /// - Android → Google Play
  /// - iOS → App Store
  Future<bool> openStore() async {
    try {
      String url;
      if (kIsWeb) {
        url = _androidStoreUrl;
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        url = _iosStoreUrl;
      } else {
        url = _androidStoreUrl;
      }

      return await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[VersionCheck] Impossible d\'ouvrir le store: $e');
      }
      return false;
    }
  }

  // ── Gestion de la fréquence des vérifications ────────────────────────────

  VersionCheckResult? _lastResult;

  bool _shouldCheckAgain() {
    final last = _lastCheckTime;
    if (last == null) return true;
    return DateTime.now().difference(last) >= _minCheckInterval;
  }

  Future<void> _persistResult(VersionCheckResult result) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kLastCheckKey, DateTime.now().millisecondsSinceEpoch);
      await prefs.setInt(_kLastResultKey, result.index);
    } catch (_) {
      // Non bloquant.
    }
  }

  Future<void> _loadPersistedResult() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt(_kLastCheckKey);
      final resultIndex = prefs.getInt(_kLastResultKey);
      if (timestamp != null && resultIndex != null) {
        _lastCheckTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
        _lastResult = VersionCheckResult.values[resultIndex];
      }
    } catch (_) {
      // Non bloquant.
    }
  }

  /// Réinitialise l'état pour forcer une nouvelle vérification.
  Future<void> reset() async {
    _lastCheckTime = null;
    _lastResult = null;
    _lastServerVersion = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kLastCheckKey);
      await prefs.remove(_kLastResultKey);
    } catch (_) {
      // Non bloquant.
    }
  }
}