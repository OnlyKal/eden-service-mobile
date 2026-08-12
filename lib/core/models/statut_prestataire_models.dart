import '../constants/api_constants.dart';
import 'prestataire_models.dart';

bool _parseBool(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final lower = value.toLowerCase();
    return lower == 'true' || lower == '1' || lower == 'yes';
  }
  return false;
}

int _parseInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

class StatutPrestataire {
  const StatutPrestataire({
    required this.id,
    required this.prestataire,
    this.prestataireDetail,
    required this.mediaUrl,
    required this.typeMedia,
    this.legende,
    this.dureeVideo,
    required this.dateCreation,
    required this.dateExpiration,
    required this.secondesRestantes,
    required this.nombreVues,
    required this.nombreLikes,
    required this.nombreCommentaires,
    required this.aimeParMoi,
    required this.vuParMoi,
    required this.commentaires,
  });

  final int id;
  final int prestataire;
  final Prestataire? prestataireDetail;
  final String mediaUrl;
  final String typeMedia;
  final String? legende;
  final int? dureeVideo;
  final DateTime? dateCreation;
  final DateTime? dateExpiration;
  final int secondesRestantes;
  final int nombreVues;
  final int nombreLikes;
  final int nombreCommentaires;
  final bool aimeParMoi;
  final bool vuParMoi;
  final List<StatutCommentaire> commentaires;

  factory StatutPrestataire.fromJson(Map<String, dynamic> json) {
    final media = (json['media_url'] ?? json['media'] ?? '').toString();
    final detail = json['prestataire_detail'];
    return StatutPrestataire(
      id: _parseInt(json['id']),
      prestataire: _parseInt(json['prestataire']),
      prestataireDetail: detail is Map<String, dynamic>
          ? Prestataire.fromJson(detail)
          : null,
      mediaUrl: media.isEmpty ? '' : ApiConstants.resolveUrl(media),
      typeMedia: json['type_media']?.toString() ?? 'photo',
      legende: json['legende']?.toString(),
      dureeVideo: json['duree_video'] == null
          ? null
          : _parseInt(json['duree_video']),
      dateCreation: DateTime.tryParse(json['date_creation']?.toString() ?? ''),
      dateExpiration: DateTime.tryParse(
        json['date_expiration']?.toString() ?? '',
      ),
      secondesRestantes: _parseInt(json['secondes_restantes']),
      nombreVues: _parseInt(json['nombre_vues']),
      nombreLikes: _parseInt(json['nombre_likes']),
      nombreCommentaires: _parseInt(json['nombre_commentaires']),
      aimeParMoi: _parseBool(json['aime_par_moi']),
      vuParMoi: _parseBool(
        json['vu_par_moi'] ??
            json['vue_par_moi'] ??
            json['viewed_by_me'] ??
            json['deja_vu'] ??
            json['is_viewed'],
      ),
      commentaires: (json['commentaires'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(StatutCommentaire.fromJson)
          .where((commentaire) => commentaire.contenu.trim().isNotEmpty)
          .toList(),
    );
  }

  StatutPrestataire copyWith({
    int? nombreVues,
    int? nombreLikes,
    int? nombreCommentaires,
    bool? aimeParMoi,
    bool? vuParMoi,
    List<StatutCommentaire>? commentaires,
  }) {
    return StatutPrestataire(
      id: id,
      prestataire: prestataire,
      prestataireDetail: prestataireDetail,
      mediaUrl: mediaUrl,
      typeMedia: typeMedia,
      legende: legende,
      dureeVideo: dureeVideo,
      dateCreation: dateCreation,
      dateExpiration: dateExpiration,
      secondesRestantes: secondesRestantes,
      nombreVues: nombreVues ?? this.nombreVues,
      nombreLikes: nombreLikes ?? this.nombreLikes,
      nombreCommentaires: nombreCommentaires ?? this.nombreCommentaires,
      aimeParMoi: aimeParMoi ?? this.aimeParMoi,
      vuParMoi: vuParMoi ?? this.vuParMoi,
      commentaires: commentaires ?? this.commentaires,
    );
  }

  bool get isVideo => typeMedia == 'video';

  int get remainingSeconds {
    if (dateExpiration != null) {
      return dateExpiration!
          .difference(DateTime.now())
          .inSeconds
          .clamp(0, 1 << 31)
          .toInt();
    }
    return secondesRestantes;
  }

  bool get isExpiredNow => remainingSeconds <= 0;

  int get minutesRestantes => (remainingSeconds / 60).ceil();

  String get remainingLabel {
    final seconds = remainingSeconds;
    if (seconds <= 0) return 'expiré';
    if (seconds < 60) return '$seconds sec restantes';
    final minutes = (seconds / 60).ceil();
    if (minutes < 60) return '$minutes min restantes';
    final hours = (minutes / 60).floor();
    return '$hours h restantes';
  }
}

class StatutCommentaireUtilisateur {
  const StatutCommentaireUtilisateur({
    required this.id,
    required this.username,
    this.firstName,
    this.lastName,
    this.photoProfil,
  });

  final int id;
  final String username;
  final String? firstName;
  final String? lastName;
  final String? photoProfil;

  factory StatutCommentaireUtilisateur.fromJson(Map<String, dynamic> json) {
    return StatutCommentaireUtilisateur(
      id: _parseInt(json['id']),
      username: json['username']?.toString() ?? 'Utilisateur',
      firstName: json['first_name']?.toString(),
      lastName: json['last_name']?.toString(),
      photoProfil: (json['photo_profil'] ?? json['photo'] ?? json['avatar'])
          ?.toString(),
    );
  }

  String get displayName {
    final full = '${firstName ?? ''} ${lastName ?? ''}'.trim();
    return full.isNotEmpty ? full : 'Utilisateur';
  }
}

class StatutCommentaire {
  const StatutCommentaire({
    required this.id,
    required this.statut,
    this.utilisateur,
    required this.contenu,
    this.dateCreation,
    this.dateModification,
  });

  final int id;
  final int statut;
  final StatutCommentaireUtilisateur? utilisateur;
  final String contenu;
  final DateTime? dateCreation;
  final DateTime? dateModification;

  factory StatutCommentaire.fromJson(Map<String, dynamic> json) {
    final user = json['utilisateur'];
    return StatutCommentaire(
      id: _parseInt(json['id']),
      statut: _parseInt(
        json['statut'] ?? json['statut_id'] ?? json['status_id'],
      ),
      utilisateur: user is Map<String, dynamic>
          ? StatutCommentaireUtilisateur.fromJson(user)
          : null,
      contenu: json['contenu']?.toString() ?? '',
      dateCreation: DateTime.tryParse(json['date_creation']?.toString() ?? ''),
      dateModification: DateTime.tryParse(
        json['date_modification']?.toString() ?? '',
      ),
    );
  }
}

class PaginatedStatutsPrestataires {
  const PaginatedStatutsPrestataires({
    required this.totalItems,
    required this.hasNext,
    required this.currentPage,
    required this.results,
  });

  final int totalItems;
  final bool hasNext;
  final int currentPage;
  final List<StatutPrestataire> results;

  factory PaginatedStatutsPrestataires.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? const {};
    return PaginatedStatutsPrestataires(
      totalItems: data['total_items'] as int? ?? data['count'] as int? ?? 0,
      hasNext: data['has_next'] as bool? ?? data['next'] != null,
      currentPage: data['current_page'] as int? ?? 1,
      results: (data['results'] as List<dynamic>? ?? const [])
          .map((e) => StatutPrestataire.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
