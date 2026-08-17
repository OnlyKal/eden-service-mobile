class ApiConstants {
  ApiConstants._();

  // static const String baseUrl = 'http://localhost:8000/service/api';
  // static const String mediaBase = 'http://localhost:8000';
  // static const String wsBase = 'ws://127.0.0.1:8000';

  static const String baseUrl = 'https://zwacop.liviatech.store/service/api';
  static const String mediaBase = 'https://zwacop.liviatech.store';
  static const String wsBase = 'wss://zwacop.liviatech.store';

  /// Converts a relative path returned by the API (e.g. /media/avatars/…)
  /// into an absolute URL.  Full URLs (starting with http) are returned as-is.
  static String resolveUrl(String path) {
    if (path.startsWith('http')) return path;
    return '$mediaBase$path';
  }

  // ── Auth ────────────────────────────────────────────────────────────────
  static const String login = '$baseUrl/auth/login/';
  static const String utilisateurs = '$baseUrl/utilisateurs/';
  static const String fcmToken = '$baseUrl/utilisateurs/fcm-token/';
  static const String changePassword = '$baseUrl/utilisateurs/change_password/';
  static const String updateMe = '$baseUrl/utilisateurs/me/';
  static const String uploadProfilePhoto =
      '$baseUrl/utilisateurs/upload-photo/';
  static const String becomeProvider = '$baseUrl/utilisateurs/become-provider/';

  // ── Prestataires ─────────────────────────────────────────────────────────
  static const String prestataires = '$baseUrl/prestataires/';
  static String prestataireDetail(int id) => '$baseUrl/prestataires/$id/';
  static Uri prestatairesWs() => _webSocketUri('/ws/prestataires/');
  static const String monProfilPrestataire =
      '$baseUrl/prestataires/mon_profil/';
  static const String services = '$baseUrl/services/';

  // ── Photos ───────────────────────────────────────────────────────────────
  static const String photos = '$baseUrl/photos/';
  static const String addPhoto = '$baseUrl/photos/add-photo/';
  static String deletePhoto(int id) => '$baseUrl/photos/$id/delete-photo/';

  // ── Notations ─────────────────────────────────────────────────────
  static const String rateProvider = '$baseUrl/notations/rate-provider/';
  static const String providerRatings = '$baseUrl/notations/provider-ratings/';

  // ── Abonnements ───────────────────────────────────────────────────
  static const String monAbonnement = '$baseUrl/abonnements/mon_abonnement/';
  static const String tarifsAbonnement = '$baseUrl/tarifs-abonnement/';
  static const String souscrire = '$baseUrl/abonnements/souscrire/';
  static String renouvelerAbonnement(int id) =>
      '$baseUrl/abonnements/$id/renouveler/';

  // ── Paiements abonnement ────────────────────────────────────────────────
  static const String paiementConfig = '$baseUrl/paiements/config/';
  static const String paiementCreate = '$baseUrl/paiements/create/';
  static String paiementStatus(int id) => '$baseUrl/paiements/$id/status/';
  static const String paiementHistory = '$baseUrl/paiements/history/';

  // ── Demandes de service ─────────────────────────────────────────────
  static const String demandesService = '$baseUrl/demandes-service/';
  static String demandeServiceDetail(int id) =>
      '$baseUrl/demandes-service/$id/';
  static String accepterDemande(int id) =>
      '$baseUrl/demandes-service/$id/accepter/';
  static String refuserDemande(int id) =>
      '$baseUrl/demandes-service/$id/refuser/';
  static String demarrerDemande(int id) =>
      '$baseUrl/demandes-service/$id/commencer/';
  static String terminerDemande(int id) =>
      '$baseUrl/demandes-service/$id/terminer/';
  static String annulerDemande(int id) =>
      '$baseUrl/demandes-service/$id/annuler/';

  // ── Favoris ─────────────────────────────────────────────────────────────
  static const String favoris = '$baseUrl/favoris/';
  static String favoriDetail(int id) => '$baseUrl/favoris/$id/';
  static const String retirerFavori = '$baseUrl/favoris/retirer/';

  // ── Conversations / Chat realtime ───────────────────────────────────────
  static const String conversations = '$baseUrl/conversations/';
  static String conversationMessages(int id) =>
      '$baseUrl/conversations/$id/messages/';
  static Uri conversationWs(int id, String token) {
    final rawToken = token
        .replaceFirst(RegExp(r'^\s*Token\s+', caseSensitive: false), '')
        .trim();

    return _webSocketUri('/ws/conversations/$id/', rawToken);
  }

  static Uri userRealtimeWs(String token) =>
      _webSocketUri('/ws/user/', _cleanWsToken(token));

  // ── Notifications ───────────────────────────────────────────────────────
  static const String notifications = '$baseUrl/notifications/';
  static String marquerNotificationLue(int id) =>
      '$baseUrl/notifications/$id/marquer_lue/';
  static const String toutMarquerNotificationsLu =
      '$baseUrl/notifications/tout_marquer_lu/';

  // ── Versions app ────────────────────────────────────────────────────────
  static const String versionAppActuelle =
      '$baseUrl/versions-app/actuelle/';

  // ── Statuts prestataires ───────────────────────────────────────────────
  static const String statutsPrestataires = '$baseUrl/statuts-prestataires/';
  static String statutPrestataireDetail(int id) =>
      '$baseUrl/statuts-prestataires/$id/';
  static String aimerStatutPrestataire(int id) =>
      '$baseUrl/statuts-prestataires/$id/aimer/';
  static String commentairesStatutPrestataire(int id) =>
      '$baseUrl/statuts-prestataires/$id/commentaires/';
  static Uri statutsPrestatairesWs([String? token]) =>
      _webSocketUri('/ws/statuts-prestataires/', _cleanWsToken(token));
  static Uri statutPrestataireInteractionsWs(int id, [String? token]) {
    return _webSocketUri('/ws/statuts-prestataires/$id/', _cleanWsToken(token));
  }

  static const String monStatutPrestataire =
      '$baseUrl/statuts-prestataires/mon_statut/';

  static Uri _webSocketUri(String path, [String? token]) {
    final wsUri = Uri.parse(wsBase);
    final scheme = wsUri.scheme == 'ws' ? 'ws' : 'wss';
    final host = wsUri.host;
    final authority = wsUri.hasPort && wsUri.port != 0
        ? '$host:${wsUri.port}'
        : host;
    final query = token == null
        ? ''
        : '?${Uri(queryParameters: {'token': token}).query}';

    return Uri.parse('$scheme://$authority$path$query');
  }

  static String? _cleanWsToken(String? token) {
    if (token == null) return null;
    final rawToken = token
        .replaceFirst(RegExp(r'^\s*Token\s+', caseSensitive: false), '')
        .trim();
    return rawToken.isEmpty ? null : rawToken;
  }
}
