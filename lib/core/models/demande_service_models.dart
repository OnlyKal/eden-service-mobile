class DemandeServiceClient {
  final int id;
  final String username;
  final String email;
  final String firstName;
  final String lastName;

  const DemandeServiceClient({
    required this.id,
    required this.username,
    required this.email,
    this.firstName = '',
    this.lastName = '',
  });

  factory DemandeServiceClient.fromJson(Map<String, dynamic> json) =>
      DemandeServiceClient(
        id: json['id'] as int? ?? 0,
        username: json['username'] as String? ?? 'Client',
        email: json['email'] as String? ?? '',
        firstName: json['first_name'] as String? ?? '',
        lastName: json['last_name'] as String? ?? '',
      );

  String get displayName {
    final full = '$firstName $lastName'.trim();
    return full.isNotEmpty ? full : 'Client';
  }
}

class DemandeServicePrestataire {
  final int id;
  final String? typeService;
  final String? presentation;
  final String? commune;
  final String? ville;

  const DemandeServicePrestataire({
    required this.id,
    this.typeService,
    this.presentation,
    this.commune,
    this.ville,
  });

  factory DemandeServicePrestataire.fromJson(Map<String, dynamic> json) =>
      DemandeServicePrestataire(
        id: json['id'] as int? ?? 0,
        typeService: json['type_service'] as String?,
        presentation: json['presentation'] as String?,
        commune: json['commune'] as String?,
        ville: json['ville'] as String?,
      );
}

class DemandeService {
  final int id;
  final DemandeServiceClient client;
  final DemandeServicePrestataire prestataire;
  final String description;
  final DateTime dateSouhaitee;
  final String lieuIntervention;
  final String statut;
  final DateTime? dateCreation;
  final DateTime? dateModification;
  final DateTime? dateAcceptation;
  final DateTime? dateTerminaison;
  final String? commentaireClient;
  final int? noteClient;
  final int? conversationId;

  const DemandeService({
    required this.id,
    required this.client,
    required this.prestataire,
    required this.description,
    required this.dateSouhaitee,
    required this.lieuIntervention,
    required this.statut,
    this.dateCreation,
    this.dateModification,
    this.dateAcceptation,
    this.dateTerminaison,
    this.commentaireClient,
    this.noteClient,
    this.conversationId,
  });

  factory DemandeService.fromJson(Map<String, dynamic> json) {
    final dateSouhaiteeRaw = json['date_souhaitee'] as String?;
    final dateCreationRaw = json['date_creation'] as String?;
    final dateModificationRaw = json['date_modification'] as String?;
    final dateAcceptationRaw = json['date_acceptation'] as String?;
    final dateTerminaisonRaw = json['date_terminaison'] as String?;

    final prestataireRaw = json['prestataire'];
    final clientRaw = json['client'];
    final conversationRaw = json['conversation'];
    final conversationId =
        json['conversation_id'] as int? ??
        (conversationRaw is int ? conversationRaw : null) ??
        (conversationRaw is Map<String, dynamic>
            ? conversationRaw['id'] as int?
            : null);

    return DemandeService(
      id: json['id'] as int? ?? 0,
      client: clientRaw is Map<String, dynamic>
          ? DemandeServiceClient.fromJson(clientRaw)
          : const DemandeServiceClient(id: 0, username: 'Client', email: ''),
      prestataire: prestataireRaw is Map<String, dynamic>
          ? DemandeServicePrestataire.fromJson(prestataireRaw)
          : DemandeServicePrestataire(
              id: prestataireRaw is int ? prestataireRaw : 0,
            ),
      description: json['description'] as String? ?? '',
      dateSouhaitee:
          DateTime.tryParse(dateSouhaiteeRaw ?? '') ?? DateTime.now(),
      lieuIntervention: json['lieu_intervention'] as String? ?? '',
      statut: json['statut'] as String? ?? '',
      dateCreation: dateCreationRaw != null
          ? DateTime.tryParse(dateCreationRaw)
          : null,
      dateModification: dateModificationRaw != null
          ? DateTime.tryParse(dateModificationRaw)
          : null,
      dateAcceptation: dateAcceptationRaw != null
          ? DateTime.tryParse(dateAcceptationRaw)
          : null,
      dateTerminaison: dateTerminaisonRaw != null
          ? DateTime.tryParse(dateTerminaisonRaw)
          : null,
      commentaireClient: json['commentaire_client'] as String?,
      noteClient: json['note_client'] as int?,
      conversationId: conversationId,
    );
  }

  DemandeService copyWith({
    String? statut,
    DateTime? dateModification,
    DateTime? dateAcceptation,
    DateTime? dateTerminaison,
  }) {
    return DemandeService(
      id: id,
      client: client,
      prestataire: prestataire,
      description: description,
      dateSouhaitee: dateSouhaitee,
      lieuIntervention: lieuIntervention,
      statut: statut ?? this.statut,
      dateCreation: dateCreation,
      dateModification: dateModification ?? this.dateModification,
      dateAcceptation: dateAcceptation ?? this.dateAcceptation,
      dateTerminaison: dateTerminaison ?? this.dateTerminaison,
      commentaireClient: commentaireClient,
      noteClient: noteClient,
      conversationId: conversationId,
    );
  }
}

class PaginatedDemandesService {
  final int totalItems;
  final int totalPages;
  final int currentPage;
  final int pageSize;
  final String? nextPageUrl;
  final String? previousPageUrl;
  final bool hasNext;
  final bool hasPrevious;
  final List<DemandeService> results;

  const PaginatedDemandesService({
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

  factory PaginatedDemandesService.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>;
    return PaginatedDemandesService(
      totalItems: data['total_items'] as int? ?? 0,
      totalPages: data['total_pages'] as int? ?? 1,
      currentPage: data['current_page'] as int? ?? 1,
      pageSize: data['page_size'] as int? ?? 20,
      nextPageUrl: data['next_page_url'] as String?,
      previousPageUrl: data['previous_page_url'] as String?,
      hasNext: data['has_next'] as bool? ?? false,
      hasPrevious: data['has_previous'] as bool? ?? false,
      results: (data['results'] as List<dynamic>? ?? [])
          .map((e) => DemandeService.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
