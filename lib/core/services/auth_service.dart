import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/api_constants.dart';
import '../models/abonnement_models.dart';
import '../models/auth_models.dart';
import 'app_refresh_service.dart';

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  static const _kUserKey = 'auth_user';

  // ── Session ──────────────────────────────────────────────────────────────
  AuthData? _currentUser;
  AuthData? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;

  void _notifyAbonnementChanged() {
    AppRefreshService.instance.notify(const {
      AppRefreshTopic.abonnement,
      AppRefreshTopic.profile,
      AppRefreshTopic.home,
      AppRefreshTopic.prestataires,
    });
  }

  /// Charge la session sauvegardée au démarrage de l'app.
  Future<void> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kUserKey);
    if (raw != null) {
      try {
        _currentUser = AuthData.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      } catch (_) {
        await prefs.remove(_kUserKey);
      }
    }
    await syncFcmToken();
  }

  Future<void> _persist(AuthData data) async {
    _currentUser = data;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kUserKey,
      jsonEncode({
        'token': data.token,
        'user_id': data.userId,
        'username': data.username,
        'email': data.email,
        'est_prestataire': data.estPrestataire,
        'photo': data.photo,
        'first_name': data.firstName,
        'last_name': data.lastName,
        'telephone': data.telephone,
      }),
    );
    AppRefreshService.instance.notifyAuthChanged();
    await syncFcmToken();
  }

  Future<void> logout() async {
    _currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kUserKey);
    AppRefreshService.instance.notifyAuthChanged();
  }

  Future<void> syncFcmToken([
    String? refreshedFirebaseRegistrationToken,
  ]) async {
    final user = _currentUser;
    if (user == null) return;
    try {
      final authToken = user.token;
      final fcmToken =
          refreshedFirebaseRegistrationToken?.trim() ??
          await FirebaseMessaging.instance.getToken();

          print('================================');
          print('FCM TOKEN ACTUEL');
          print(fcmToken);
          print('================================');
      if (fcmToken == null || fcmToken.trim().isEmpty) {
        return;
      }

      if (kDebugMode) {
        debugPrint('FCM TOKEN: $fcmToken');
      }

      final response = await http.post(
        Uri.parse(ApiConstants.fcmToken),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': authToken,
        },
        body: jsonEncode({'fcm_token': fcmToken.trim()}),
      );

      if (kDebugMode &&
          (response.statusCode < 200 || response.statusCode >= 300)) {
        debugPrint('FCM token registration failed: ${response.statusCode}');
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('FCM token registration error: $error');
      }
    }
  }

  // ── Login ────────────────────────────────────────────────────────────────
  Future<LoginResponse> login(LoginRequest request) async {
    final response = await http.post(
      Uri.parse(ApiConstants.login),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(request.toJson()),
    );
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final result = LoginResponse.fromJson(json);
    if (result.success && result.data != null) await _persist(result.data!);
    return result;
  }

  // ── Register ─────────────────────────────────────────────────────────────
  Future<LoginResponse> register(RegisterRequest request) async {
    final response = await http.post(
      Uri.parse(ApiConstants.utilisateurs),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(request.toJson()),
    );
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final result = LoginResponse.fromJson(json);
    if (result.success && result.data != null) await _persist(result.data!);
    return result;
  }

  // ── Update profile ────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> updateProfile({
    String? firstName,
    String? lastName,
    String? email,
    String? telephone,
  }) async {
    final body = <String, dynamic>{};
    if (firstName != null) body['first_name'] = firstName;
    if (lastName != null) body['last_name'] = lastName;
    if (email != null) body['email'] = email;
    if (telephone != null) body['telephone'] = telephone;

    final response = await http.patch(
      Uri.parse(ApiConstants.updateMe),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': _currentUser!.token,
      },
      body: jsonEncode(body),
    );
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json['success'] == true && json['data'] != null) {
      final d = json['data'] as Map<String, dynamic>;
      await _persist(
        _currentUser!.copyWithProfile(
          email: d['email'] as String?,
          firstName: d['first_name'] as String?,
          lastName: d['last_name'] as String?,
          telephone: d['telephone'] as String?,
          photo: d['photo_profil'] as String?,
        ),
      );
    }
    return json;
  }

  Future<Map<String, dynamic>> uploadProfilePhoto({
    required List<int> bytes,
    required String filename,
  }) async {
    final user = _currentUser;
    if (user == null) throw Exception('Utilisateur non connecté');

    final request = http.MultipartRequest(
      'POST',
      Uri.parse(ApiConstants.uploadProfilePhoto),
    );
    request.headers['Authorization'] = user.token;
    request.files.add(
      http.MultipartFile.fromBytes('photo_profil', bytes, filename: filename),
    );

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(json['message'] ?? 'Upload impossible');
    }

    if (json['success'] == true && json['data'] != null) {
      final d = json['data'] as Map<String, dynamic>;
      await _persist(
        user.copyWithProfile(
          email: d['email'] as String?,
          firstName: d['first_name'] as String?,
          lastName: d['last_name'] as String?,
          telephone: d['telephone'] as String?,
          photo: d['photo_profil'] as String?,
        ),
      );
    }
    return json;
  }

  // ── Become provider ─────────────────────────────────────────────────────
  Future<Map<String, dynamic>> becomeProvider({
    required String typeService,
    List<int>? serviceIds,
    required String adresseRue,
    required String commune,
    required String ville,
    required String presentation,
  }) async {
    final response = await http.post(
      Uri.parse(ApiConstants.becomeProvider),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': _currentUser!.token,
      },
      body: jsonEncode({
        'type_service': typeService,
        if (serviceIds != null) 'service_ids': serviceIds,
        'adresse_rue': adresseRue,
        'commune': commune,
        'ville': ville,
        'presentation': presentation,
      }),
    );
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json['success'] == true && json['data'] != null) {
      final d = json['data'] as Map<String, dynamic>;
      await _persist(
        _currentUser!.copyWithPrestataire(
          estPrestataire: d['est_prestataire'] as bool? ?? true,
          photo: d['photo_profil'] as String?,
        ),
      );
    }
    return json;
  }

  // ── Mon abonnement ──────────────────────────────────────────────────────
  Future<AbonnementStatut?> getMonAbonnement() async {
    final uri = Uri.parse(ApiConstants.monAbonnement).replace(
      queryParameters: {'_': DateTime.now().millisecondsSinceEpoch.toString()},
    );
    final response = await http.get(
      uri,
      headers: {
        'Authorization': _currentUser!.token,
        'Cache-Control': 'no-cache',
        'Pragma': 'no-cache',
      },
    );
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json['success'] == true && json['data'] != null) {
      return AbonnementStatut.fromJson(json['data'] as Map<String, dynamic>);
    }
    return null;
  }

  // ── Tarifs abonnement ────────────────────────────────────────────────────
  Future<List<TarifAbonnement>> getTarifsAbonnement() async {
    final response = await http.get(
      Uri.parse(ApiConstants.tarifsAbonnement),
      headers: {'Authorization': _currentUser!.token},
    );
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json['success'] == true && json['data'] != null) {
      final data = json['data'] as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>;
      return results
          .map((e) => TarifAbonnement.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  Future<PaiementConfig> getPaiementConfig() async {
    final response = await http.get(
      Uri.parse(ApiConstants.paiementConfig),
      headers: {'Authorization': _currentUser!.token},
    );
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(json['message'] ?? 'Configuration paiement indisponible');
    }
    return PaiementConfig.fromJson(json);
  }

  Future<PaiementTransaction> createPaiement({
    required String phone,
    required String currency,
    required int dureeMois,
  }) async {
    final response = await http.post(
      Uri.parse(ApiConstants.paiementCreate),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': _currentUser!.token,
      },
      body: jsonEncode({
        'phone': phone,
        'currency': currency,
        'duree_mois': dureeMois,
      }),
    );
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = json['error'] as Map<String, dynamic>?;
      throw Exception(
        error?['message'] ?? json['message'] ?? 'Paiement impossible',
      );
    }
    final data = json['data'] as Map<String, dynamic>? ?? const {};
    return PaiementTransaction.fromJson(
      data['transaction'] as Map<String, dynamic>? ?? const {},
    );
  }

  Future<PaiementTransaction> getPaiementStatus(int transactionId) async {
    final uri = Uri.parse(ApiConstants.paiementStatus(transactionId)).replace(
      queryParameters: {'_': DateTime.now().millisecondsSinceEpoch.toString()},
    );
    final response = await http.get(
      uri,
      headers: {'Authorization': _currentUser!.token},
    );
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(json['message'] ?? 'Statut paiement indisponible');
    }
    final data = json['data'] as Map<String, dynamic>? ?? const {};
    final rawTransaction = data['transaction'] ?? data;
    final transaction = PaiementTransaction.fromJson(
      rawTransaction as Map<String, dynamic>? ?? const {},
    );
    if (transaction.statut.toUpperCase() == 'SUCCESS') {
      _notifyAbonnementChanged();
    }
    return transaction;
  }

  Future<List<PaiementTransaction>> getPaiementHistory() async {
    final response = await http.get(
      Uri.parse(ApiConstants.paiementHistory),
      headers: {'Authorization': _currentUser!.token},
    );
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json['success'] == true && json['data'] is List<dynamic>) {
      return (json['data'] as List<dynamic>)
          .map((e) => PaiementTransaction.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  // ── Souscrire ────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> souscrireAbonnement({
    required String typeAbonnement,
    required String methodePaiement,
  }) async {
    final response = await http.post(
      Uri.parse(ApiConstants.souscrire),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': _currentUser!.token,
      },
      body: jsonEncode({
        'type_abonnement': typeAbonnement,
        'methode_paiement': methodePaiement,
      }),
    );
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json['success'] == true) _notifyAbonnementChanged();
    return json;
  }

  // ── Renouveler ───────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> renouvelerAbonnement({
    required int abonnementId,
    required String methodePaiement,
  }) async {
    final response = await http.post(
      Uri.parse(ApiConstants.renouvelerAbonnement(abonnementId)),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': _currentUser!.token,
      },
      body: jsonEncode({'methode_paiement': methodePaiement}),
    );
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json['success'] == true) _notifyAbonnementChanged();
    return json;
  }

  // ── Change password ───────────────────────────────────────────────────────
  Future<Map<String, dynamic>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final response = await http.post(
      Uri.parse(ApiConstants.changePassword),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': _currentUser!.token,
      },
      body: jsonEncode({
        'current_password': currentPassword,
        'new_password': newPassword,
      }),
    );
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}
