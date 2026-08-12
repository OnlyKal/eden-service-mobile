import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';
import '../models/demande_service_models.dart';
import 'app_refresh_service.dart';
import 'auth_service.dart';

class DemandeServiceService {
  DemandeServiceService._();
  static final DemandeServiceService instance = DemandeServiceService._();

  void _notifyDemandesChanged() {
    AppRefreshService.instance.notify(const {
      AppRefreshTopic.demandes,
      AppRefreshTopic.conversations,
      AppRefreshTopic.notifications,
      AppRefreshTopic.home,
      AppRefreshTopic.prestataires,
    });
  }

  Future<PaginatedDemandesService> getDemandes({
    int page = 1,
    int? prestataire,
    int? client,
    String? statut,
    String? ordering,
  }) async {
    final params = <String, String>{
      'page': page.toString(),
      if (prestataire != null) 'prestataire': prestataire.toString(),
      if (client != null) 'client': client.toString(),
      if (statut != null && statut.isNotEmpty) 'statut': statut,
      if (ordering != null && ordering.isNotEmpty) 'ordering': ordering,
    };

    final uri = Uri.parse(
      ApiConstants.demandesService,
    ).replace(queryParameters: params);
    final token = AuthService.instance.currentUser?.token;
    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': token,
      },
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Erreur ${response.statusCode} lors du chargement des demandes de service',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return PaginatedDemandesService.fromJson(json);
  }

  Future<DemandeService> createDemande({
    required int prestataire,
    required String description,
    required DateTime dateSouhaitee,
    required String lieuIntervention,
  }) async {
    final token = AuthService.instance.currentUser?.token;
    final response = await http.post(
      Uri.parse(ApiConstants.demandesService),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': token,
      },
      body: jsonEncode({
        'prestataire': prestataire,
        'description': description,
        'date_souhaitee': dateSouhaitee.toUtc().toIso8601String(),
        'lieu_intervention': lieuIntervention,
      }),
    );

    if (response.statusCode != 201) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(
        body['message'] ??
            'Erreur ${response.statusCode} lors de la création de la demande',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final demande = DemandeService.fromJson(
      json['data'] as Map<String, dynamic>,
    );
    _notifyDemandesChanged();
    return demande;
  }

  Future<DemandeService> getDemande(int demandeId) async {
    final uri = Uri.parse(ApiConstants.demandeServiceDetail(demandeId));
    final token = AuthService.instance.currentUser?.token;
    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': token,
      },
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Erreur ${response.statusCode} lors de la récupération de la demande',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final demande = DemandeService.fromJson(
      json['data'] as Map<String, dynamic>,
    );
    _notifyDemandesChanged();
    return demande;
  }

  Future<DemandeService> updateDemande(
    int demandeId, {
    String? description,
    DateTime? dateSouhaitee,
    String? lieuIntervention,
    String? statut,
    String? commentaireClient,
    int? noteClient,
  }) async {
    final body = <String, dynamic>{};
    if (description != null) body['description'] = description;
    if (dateSouhaitee != null) {
      body['date_souhaitee'] = dateSouhaitee.toUtc().toIso8601String();
    }
    if (lieuIntervention != null) body['lieu_intervention'] = lieuIntervention;
    if (statut != null) body['statut'] = statut;
    if (commentaireClient != null) {
      body['commentaire_client'] = commentaireClient;
    }
    if (noteClient != null) body['note_client'] = noteClient;

    final token = AuthService.instance.currentUser?.token;
    final response = await http.patch(
      Uri.parse(ApiConstants.demandeServiceDetail(demandeId)),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': token,
      },
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      final bodyJson = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(
        bodyJson['message'] ??
            'Erreur ${response.statusCode} lors de la mise à jour de la demande',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return DemandeService.fromJson(json['data'] as Map<String, dynamic>);
  }

  Future<void> deleteDemande(int demandeId) async {
    final token = AuthService.instance.currentUser?.token;
    final response = await http.delete(
      Uri.parse(ApiConstants.demandeServiceDetail(demandeId)),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': token,
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(
        body['message'] ??
            'Erreur ${response.statusCode} lors de la suppression de la demande',
      );
    }
    _notifyDemandesChanged();
  }

  Future<DemandeService> accepterDemande(int demandeId) async {
    return _postAction(demandeId, ApiConstants.accepterDemande);
  }

  Future<DemandeService> refuserDemande(int demandeId) async {
    return _postAction(demandeId, ApiConstants.refuserDemande);
  }

  Future<DemandeService> demarrerDemande(int demandeId) async {
    return _postAction(demandeId, ApiConstants.demarrerDemande);
  }

  Future<DemandeService> terminerDemande(int demandeId) async {
    return _postAction(demandeId, ApiConstants.terminerDemande);
  }

  Future<DemandeService> annulerDemande(int demandeId) async {
    return _postAction(demandeId, ApiConstants.annulerDemande);
  }

  Future<DemandeService> _postAction(
    int demandeId,
    String Function(int) endpointBuilder,
  ) async {
    final token = AuthService.instance.currentUser?.token;
    final response = await http.post(
      Uri.parse(endpointBuilder(demandeId)),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': token,
      },
    );

    if (response.statusCode != 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(
        body['message'] ??
            'Erreur ${response.statusCode} lors de l\'action sur la demande',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final demande = DemandeService.fromJson(
      json['data'] as Map<String, dynamic>,
    );
    _notifyDemandesChanged();
    return demande;
  }
}
