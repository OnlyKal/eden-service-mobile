class FavoriUtilisateur {
  const FavoriUtilisateur({required this.id, required this.username});

  final int id;
  final String username;

  factory FavoriUtilisateur.fromJson(Map<String, dynamic> json) {
    return FavoriUtilisateur(
      id: json['id'] as int? ?? 0,
      username: json['username'] as String? ?? '',
    );
  }
}

class FavoriPrestataireDetail {
  const FavoriPrestataireDetail({
    required this.id,
    required this.typeService,
    required this.commune,
    required this.ville,
    required this.isAvailable,
  });

  final int id;
  final String typeService;
  final String commune;
  final String ville;
  final bool isAvailable;

  factory FavoriPrestataireDetail.fromJson(Map<String, dynamic> json) {
    return FavoriPrestataireDetail(
      id: json['id'] as int? ?? 0,
      typeService: json['type_service'] as String? ?? '',
      commune: json['commune'] as String? ?? '',
      ville: json['ville'] as String? ?? '',
      isAvailable: _parseBool(json['is_available']),
    );
  }
}

class Favori {
  const Favori({
    required this.id,
    this.utilisateur,
    required this.prestataire,
    this.prestataireDetail,
    this.dateCreation,
  });

  final int id;
  final FavoriUtilisateur? utilisateur;
  final int prestataire;
  final FavoriPrestataireDetail? prestataireDetail;
  final DateTime? dateCreation;

  factory Favori.fromJson(Map<String, dynamic> json) {
    final utilisateurRaw = json['utilisateur'];
    final detailRaw = json['prestataire_detail'];
    final prestataireRaw = json['prestataire'];
    final dateRaw = json['date_creation'] as String?;

    return Favori(
      id: json['id'] as int? ?? 0,
      utilisateur: utilisateurRaw is Map<String, dynamic>
          ? FavoriUtilisateur.fromJson(utilisateurRaw)
          : null,
      prestataire: prestataireRaw is int
          ? prestataireRaw
          : int.tryParse('$prestataireRaw') ?? 0,
      prestataireDetail: detailRaw is Map<String, dynamic>
          ? FavoriPrestataireDetail.fromJson(detailRaw)
          : null,
      dateCreation: dateRaw == null ? null : DateTime.tryParse(dateRaw),
    );
  }
}

class PaginatedFavoris {
  const PaginatedFavoris({
    required this.count,
    this.next,
    this.previous,
    required this.results,
  });

  final int count;
  final String? next;
  final String? previous;
  final List<Favori> results;

  factory PaginatedFavoris.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? const {};
    return PaginatedFavoris(
      count: data['count'] as int? ?? 0,
      next: data['next'] as String?,
      previous: data['previous'] as String?,
      results: (data['results'] as List<dynamic>? ?? const [])
          .map((e) => Favori.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

bool _parseBool(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final lower = value.toLowerCase();
    return lower == 'true' || lower == '1' || lower == 'yes';
  }
  return false;
}
