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

double? _parseDouble(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

// ── Utilisateur ──────────────────────────────────────────────────────────────

class Utilisateur {
  final int id;
  final String username;
  final String email;
  final String firstName;
  final String lastName;
  final String? telephone;
  final bool estPrestataire;
  final String? photoProfil;
  final String statutCompte;
  final String dateJoined;

  const Utilisateur({
    required this.id,
    required this.username,
    required this.email,
    required this.firstName,
    required this.lastName,
    this.telephone,
    required this.estPrestataire,
    this.photoProfil,
    required this.statutCompte,
    required this.dateJoined,
  });

  factory Utilisateur.fromJson(Map<String, dynamic> json) => Utilisateur(
    id: json['id'] as int,
    username: json['username'] as String,
    email: json['email'] as String,
    firstName: json['first_name'] as String? ?? '',
    lastName: json['last_name'] as String? ?? '',
    telephone: json['telephone'] as String?,
    estPrestataire: _parseBool(json['est_prestataire']),
    photoProfil: json['photo_profil'] as String?,
    statutCompte: json['statut_compte'] as String? ?? '',
    dateJoined: json['date_joined'] as String? ?? '',
  );

  /// Nom complet ou username si absent
  String get displayName {
    final full = '$firstName $lastName'.trim();
    return full.isNotEmpty ? full : 'Utilisateur';
  }
}

// ── Prestataire ──────────────────────────────────────────────────────────────

class ServiceDisponible {
  final int id;
  final String nom;
  final String? description;
  final bool actif;
  final String dateCreation;

  const ServiceDisponible({
    required this.id,
    required this.nom,
    this.description,
    required this.actif,
    required this.dateCreation,
  });

  factory ServiceDisponible.fromJson(
    Map<String, dynamic> json,
  ) => ServiceDisponible(
    id: _parseInt(json['id']),
    nom: (json['nom'] ?? json['title'] ?? json['label'] ?? json['name'] ?? '')
        .toString()
        .trim(),
    description: json['description'] as String?,
    actif: json.containsKey('actif') ? _parseBool(json['actif']) : true,
    dateCreation: json['date_creation'] as String? ?? '',
  );
}

class Prestataire {
  final int id;
  final Utilisateur utilisateur;
  final String typeService;
  final List<ServiceDisponible> services;
  final String presentation;
  final String commune;
  final String ville;
  final bool estValide;

  /// Certification du compte, gérée exclusivement par l'administrateur
  /// Django. Sert uniquement à afficher le badge bleu à côté du nom.
  /// Ne doit jamais être envoyé par l'application.
  final bool isCertified;
  final bool isAvailable;
  final int nombrePhotos;
  final int nombreCommentaires;
  final double? moyenneNotes;
  final String niveau;
  final int scoreNiveau;
  final double? noteMoyenne;
  final int missionsReussies;
  final int tauxReponse;
  final int tauxSatisfaction;
  final int tauxRespectEngagements;
  final String? dateDernierCalculNiveau;

  const Prestataire({
    required this.id,
    required this.utilisateur,
    required this.typeService,
    required this.services,
    required this.presentation,
    required this.commune,
    required this.ville,
    required this.estValide,
    this.isCertified = false,
    required this.isAvailable,
    required this.nombrePhotos,
    required this.nombreCommentaires,
    this.moyenneNotes,
    required this.niveau,
    required this.scoreNiveau,
    this.noteMoyenne,
    required this.missionsReussies,
    required this.tauxReponse,
    required this.tauxSatisfaction,
    required this.tauxRespectEngagements,
    this.dateDernierCalculNiveau,
  });

  factory Prestataire.fromJson(Map<String, dynamic> json) => Prestataire(
    id: json['id'] as int,
    utilisateur: Utilisateur.fromJson(
      json['utilisateur'] as Map<String, dynamic>,
    ),
    typeService: json['type_service'] as String? ?? '',
    services: (json['services'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(ServiceDisponible.fromJson)
        .where((service) => service.nom.isNotEmpty)
        .toList(),
    presentation: json['presentation'] as String? ?? '',
    commune: json['commune'] as String? ?? '',
    ville: json['ville'] as String? ?? '',
    estValide: _parseBool(json['est_valide']),
    isCertified: _parseBool(json['is_certified']),
    isAvailable: _parseBool(json['is_available']),
    nombrePhotos: json['nombre_photos'] as int? ?? 0,
    nombreCommentaires: json['nombre_commentaires'] as int? ?? 0,
    moyenneNotes: _parseDouble(json['moyenne_notes']),
    niveau: json['niveau'] as String? ?? '',
    scoreNiveau: _parseInt(json['score_niveau']),
    noteMoyenne: _parseDouble(json['note_moyenne']),
    missionsReussies: _parseInt(json['missions_reussies']),
    tauxReponse: _parseInt(json['taux_reponse']),
    tauxSatisfaction: _parseInt(json['taux_satisfaction']),
    tauxRespectEngagements: _parseInt(json['taux_respect_engagements']),
    dateDernierCalculNiveau: json['date_dernier_calcul_niveau'] as String?,
  );

  /// La certification est conservée telle quelle : elle n'est gérée que par
  /// l'administrateur Django.
  Prestataire copyWith({bool? isAvailable, bool? estValide}) {
    return Prestataire(
      id: id,
      utilisateur: utilisateur,
      typeService: typeService,
      services: services,
      presentation: presentation,
      commune: commune,
      ville: ville,
      estValide: estValide ?? this.estValide,
      isCertified: isCertified,
      isAvailable: isAvailable ?? this.isAvailable,
      nombrePhotos: nombrePhotos,
      nombreCommentaires: nombreCommentaires,
      moyenneNotes: moyenneNotes,
      niveau: niveau,
      scoreNiveau: scoreNiveau,
      noteMoyenne: noteMoyenne,
      missionsReussies: missionsReussies,
      tauxReponse: tauxReponse,
      tauxSatisfaction: tauxSatisfaction,
      tauxRespectEngagements: tauxRespectEngagements,
      dateDernierCalculNiveau: dateDernierCalculNiveau,
    );
  }

  List<String> get serviceNames {
    final names = services
        .map((service) => service.nom)
        .where((s) => s.isNotEmpty);
    final unique = <String>{};
    for (final name in names) {
      unique.add(name);
    }
    if (unique.isEmpty && typeService.isNotEmpty) unique.add(typeService);
    return unique.toList();
  }

  String get servicesLabel => serviceNames.join(', ');
}

// ── MonProfilPrestataire ────────────────────────────────────────────────────

class MonProfilPrestataire {
  final int id;
  final String typeService;
  final List<ServiceDisponible> services;
  final String presentation;
  final String? adresseRue;
  final String commune;
  final String ville;
  final String? codePostal;
  final String? dateDebutAbonnement;
  final String? dateFinAbonnement;
  final bool estValide;

  /// Certification du compte (`is_certified`), gérée uniquement par
  /// l'administrateur Django.
  final bool isCertified;
  final bool isAvailable;
  final List<PrestatairePhoto> photos;
  final String niveau;
  final int scoreNiveau;
  final double? noteMoyenne;
  final int missionsReussies;
  final int tauxReponse;
  final int tauxSatisfaction;
  final int tauxRespectEngagements;
  final String? dateDernierCalculNiveau;

  const MonProfilPrestataire({
    required this.id,
    required this.typeService,
    required this.services,
    required this.presentation,
    this.adresseRue,
    required this.commune,
    required this.ville,
    this.codePostal,
    this.dateDebutAbonnement,
    this.dateFinAbonnement,
    required this.estValide,
    this.isCertified = false,
    required this.isAvailable,
    required this.photos,
    required this.niveau,
    required this.scoreNiveau,
    this.noteMoyenne,
    required this.missionsReussies,
    required this.tauxReponse,
    required this.tauxSatisfaction,
    required this.tauxRespectEngagements,
    this.dateDernierCalculNiveau,
  });

  factory MonProfilPrestataire.fromJson(Map<String, dynamic> json) =>
      MonProfilPrestataire(
        id: json['id'] as int,
        typeService: json['type_service'] as String? ?? '',
        services: (json['services'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(ServiceDisponible.fromJson)
            .where((service) => service.nom.isNotEmpty)
            .toList(),
        presentation: json['presentation'] as String? ?? '',
        adresseRue: json['adresse_rue'] as String?,
        commune: json['commune'] as String? ?? '',
        ville: json['ville'] as String? ?? '',
        codePostal: json['code_postal'] as String?,
        dateDebutAbonnement: json['date_debut_abonnement'] as String?,
        dateFinAbonnement: json['date_fin_abonnement'] as String?,
        estValide: _parseBool(json['est_valide']),
        isCertified: _parseBool(json['is_certified']),
        isAvailable: _parseBool(json['is_available']),
        photos: (json['photos'] as List<dynamic>? ?? [])
            .map((e) => PrestatairePhoto.fromJson(e as Map<String, dynamic>))
            .toList(),
        niveau: json['niveau'] as String? ?? '',
        scoreNiveau: _parseInt(json['score_niveau']),
        noteMoyenne: _parseDouble(json['note_moyenne']),
        missionsReussies: _parseInt(json['missions_reussies']),
        tauxReponse: _parseInt(json['taux_reponse']),
        tauxSatisfaction: _parseInt(json['taux_satisfaction']),
        tauxRespectEngagements: _parseInt(json['taux_respect_engagements']),
        dateDernierCalculNiveau: json['date_dernier_calcul_niveau'] as String?,
      );

  List<String> get serviceNames {
    final names = services
        .map((service) => service.nom)
        .where((s) => s.isNotEmpty);
    final unique = <String>{};
    for (final name in names) {
      unique.add(name);
    }
    if (unique.isEmpty && typeService.isNotEmpty) unique.add(typeService);
    return unique.toList();
  }

  List<int> get serviceIds =>
      services.map((service) => service.id).where((id) => id > 0).toList();

  String get servicesLabel => serviceNames.join(', ');
}

// ── PrestatairePhoto ─────────────────────────────────────────────────────────

class PrestatairePhoto {
  final int id;
  final int prestataire;
  final String image;
  final String description;
  final String dateAjout;

  const PrestatairePhoto({
    required this.id,
    required this.prestataire,
    required this.image,
    required this.description,
    required this.dateAjout,
  });

  factory PrestatairePhoto.fromJson(Map<String, dynamic> json) =>
      PrestatairePhoto(
        id: json['id'] as int,
        prestataire: json['prestataire'] as int,
        image: json['image'] as String,
        description: json['description'] as String? ?? '',
        dateAjout: json['date_ajout'] as String? ?? '',
      );
}

// ── Notation ─────────────────────────────────────────────────────────────────

class Notation {
  final int id;
  final Utilisateur utilisateur;
  final int prestataire;
  final int note;
  final String noteDisplay;
  final String avis;
  final String dateCreation;

  const Notation({
    required this.id,
    required this.utilisateur,
    required this.prestataire,
    required this.note,
    required this.noteDisplay,
    required this.avis,
    required this.dateCreation,
  });

  factory Notation.fromJson(Map<String, dynamic> json) => Notation(
    id: json['id'] as int? ?? 0,
    utilisateur: json['utilisateur'] is Map<String, dynamic>
        ? Utilisateur.fromJson(json['utilisateur'] as Map<String, dynamic>)
        : const Utilisateur(
            id: 0,
            username: 'Client',
            email: '',
            firstName: '',
            lastName: '',
            estPrestataire: false,
            statutCompte: '',
            dateJoined: '',
          ),
    prestataire: json['prestataire'] as int? ?? 0,
    note: json['note'] as int? ?? 0,
    noteDisplay: json['get_note_display'] as String? ?? '',
    avis: json['avis'] as String? ?? '',
    dateCreation: json['date_creation'] as String? ?? '',
  );
}

class NotationsResponse {
  final double averageRating;
  final int totalRatings;
  final List<Notation> ratings;

  const NotationsResponse({
    required this.averageRating,
    required this.totalRatings,
    required this.ratings,
  });

  factory NotationsResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>;
    return NotationsResponse(
      averageRating: (data['average_rating'] as num?)?.toDouble() ?? 0.0,
      totalRatings: data['total_ratings'] as int? ?? 0,
      ratings: (data['ratings'] as List<dynamic>? ?? [])
          .map((e) => Notation.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

// ── Pagination ────────────────────────────────────────────────────────────────

class PaginatedPrestataires {
  final int totalItems;
  final int totalPages;
  final int currentPage;
  final int pageSize;
  final String? nextPageUrl;
  final String? previousPageUrl;
  final bool hasNext;
  final bool hasPrevious;
  final List<Prestataire> results;

  const PaginatedPrestataires({
    required this.totalItems,
    required this.totalPages,
    required this.currentPage,
    required this.pageSize,
    this.nextPageUrl,
    this.previousPageUrl,
    required this.hasNext,
    required this.hasPrevious,
    required this.results,
  });

  factory PaginatedPrestataires.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>;
    return PaginatedPrestataires(
      totalItems: data['total_items'] as int? ?? 0,
      totalPages: data['total_pages'] as int? ?? 1,
      currentPage: data['current_page'] as int? ?? 1,
      pageSize: data['page_size'] as int? ?? 20,
      nextPageUrl: data['next_page_url'] as String?,
      previousPageUrl: data['previous_page_url'] as String?,
      hasNext: data['has_next'] as bool? ?? false,
      hasPrevious: data['has_previous'] as bool? ?? false,
      results: (data['results'] as List<dynamic>? ?? [])
          .map((e) => Prestataire.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
