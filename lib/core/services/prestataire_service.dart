import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';
import '../constants/api_constants.dart';
import '../models/prestataire_models.dart';
import 'app_refresh_service.dart';
import 'auth_service.dart';

class PrestataireService {
  PrestataireService._();
  static final PrestataireService instance = PrestataireService._();

  void _notifyPrestatairesChanged({bool ratings = false}) {
    AppRefreshService.instance.notify({
      AppRefreshTopic.prestataires,
      AppRefreshTopic.profile,
      AppRefreshTopic.home,
      if (ratings) AppRefreshTopic.ratings,
    });
  }

  /// Récupère la liste paginée des prestataires.
  ///
  /// Paramètres optionnels :
  /// - [page]         : numéro de page (défaut : 1)
  /// - [pageSize]     : éléments par page (défaut : 20, max : 100)
  /// - [search]       : recherche plein texte
  /// - [typeService]  : filtre par type exact
  /// - [commune]      : filtre par commune exacte
  /// - [ville]        : filtre par ville exacte
  /// - [estValide]    : filtre par statut de validation
  /// - [disponible]   : filtre par disponibilité du prestataire
  /// - [ordering]     : champ de tri (préfixe `-` pour descend.)
  Future<PaginatedPrestataires> getPrestataires({
    int page = 1,
    int pageSize = 20,
    String? search,
    String? typeService,
    int? serviceId,
    String? commune,
    String? ville,
    bool? estValide,
    bool? disponible,
    String? ordering,
  }) async {
    final params = <String, String>{
      'page': page.toString(),
      'page_size': pageSize.toString(),
      if (search != null && search.isNotEmpty) 'search': search,
      if (typeService != null && typeService.isNotEmpty)
        'type_service': typeService,
      if (serviceId != null) 'service_id': serviceId.toString(),
      if (commune != null && commune.isNotEmpty) 'commune': commune,
      if (ville != null && ville.isNotEmpty) 'ville': ville,
      if (estValide != null) 'est_valide': estValide.toString(),
      if (disponible != null) 'is_available': disponible.toString(),
      if (ordering != null && ordering.isNotEmpty) 'ordering': ordering,
    };

    final uri = Uri.parse(
      ApiConstants.prestataires,
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
        'Erreur ${response.statusCode} lors du chargement des prestataires',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return PaginatedPrestataires.fromJson(json);
  }

  Future<List<ServiceDisponible>> getServices({
    int page = 1,
    int pageSize = 200,
    String? search,
    bool? actif,
  }) async {
    final params = <String, String>{
      'page': page.toString(),
      'page_size': pageSize.toString(),
      if (search != null && search.isNotEmpty) 'search': search,
      if (actif != null) 'actif': actif.toString(),
    };

    final response = await http.get(
      Uri.parse(ApiConstants.services).replace(queryParameters: params),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Erreur ${response.statusCode} lors du chargement des services',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final data = json['data'] as Map<String, dynamic>? ?? {};
    return (data['results'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(ServiceDisponible.fromJson)
        .where((service) => service.nom.isNotEmpty)
        .toList()
      ..sort((a, b) => a.nom.toLowerCase().compareTo(b.nom.toLowerCase()));
  }

  /// Récupère le détail complet d'un prestataire.
  Future<Prestataire> getPrestataire(int prestataireId) async {
    final token = AuthService.instance.currentUser?.token;
    final response = await http.get(
      Uri.parse(ApiConstants.prestataireDetail(prestataireId)),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': token,
      },
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Erreur ${response.statusCode} lors du chargement du prestataire',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final data = json['data'] as Map<String, dynamic>? ?? json;
    return Prestataire.fromJson(data);
  }

  /// Met à jour le profil du prestataire connecté.
  Future<Map<String, dynamic>> updateMonProfil({
    String? typeService,
    List<int>? serviceIds,
    String? presentation,
    String? adresseRue,
    String? commune,
    String? ville,
    String? codePostal,
  }) async {
    final body = <String, dynamic>{};
    if (typeService != null) body['type_service'] = typeService;
    if (serviceIds != null) body['service_ids'] = serviceIds;
    if (presentation != null) body['presentation'] = presentation;
    if (adresseRue != null) body['adresse_rue'] = adresseRue;
    if (commune != null) body['commune'] = commune;
    if (ville != null) body['ville'] = ville;
    if (codePostal != null) body['code_postal'] = codePostal;

    final token = AuthService.instance.currentUser?.token;
    final response = await http.patch(
      Uri.parse(ApiConstants.monProfilPrestataire),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': token,
      },
      body: jsonEncode(body),
    );
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 200 && response.statusCode < 300) {
      _notifyPrestatairesChanged();
    }
    return json;
  }

  /// Récupère le profil complet du prestataire connecté.
  Future<MonProfilPrestataire> getMonProfil() async {
    final token = AuthService.instance.currentUser?.token;
    final response = await http.get(
      Uri.parse(ApiConstants.monProfilPrestataire),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': token,
      },
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Échec chargement profil prestataire: ${response.statusCode}',
      );
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return MonProfilPrestataire.fromJson(json['data'] as Map<String, dynamic>);
  }

  /// Récupère les photos d'un prestataire.
  Future<List<PrestatairePhoto>> getPhotos(int prestataireId) async {
    final uri = Uri.parse(
      ApiConstants.photos,
    ).replace(queryParameters: {'prestataire': prestataireId.toString()});

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
        'Erreur ${response.statusCode} lors du chargement des photos',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final data = json['data'] as Map<String, dynamic>;
    final results = data['results'] as List<dynamic>;
    return results
        .map((e) => PrestatairePhoto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Ajoute une photo au portfolio du prestataire connecté.
  ///
  /// [image]       : fichier image à uploader.
  /// [description] : légende de la photo (peut être vide).
  Future<Map<String, dynamic>> addPhoto({
    required File image,
    required String description,
  }) async {
    final token = AuthService.instance.currentUser?.token;
    final request = http.MultipartRequest(
      'POST',
      Uri.parse(ApiConstants.addPhoto),
    );
    if (token != null) request.headers['Authorization'] = token;
    request.fields['description'] = description;
    final mimeType = lookupMimeType(image.path) ?? 'image/jpeg';
    request.files.add(
      await http.MultipartFile.fromPath(
        'image',
        image.path,
        contentType: MediaType.parse(mimeType),
      ),
    );
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        body['message'] ?? 'Erreur ${response.statusCode} lors de l\'upload',
      );
    }
    _notifyPrestatairesChanged();
    return body;
  }

  /// Supprime une photo du portfolio du prestataire connecté.
  Future<void> deletePhoto(int photoId) async {
    final token = AuthService.instance.currentUser?.token;
    final response = await http.delete(
      Uri.parse(ApiConstants.deletePhoto(photoId)),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': token,
      },
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        body['message'] ??
            'Erreur ${response.statusCode} lors de la suppression',
      );
    }
    _notifyPrestatairesChanged();
  }

  /// Récupère les notations d'un prestataire.
  Future<NotationsResponse> getProviderRatings(int prestataireId) async {
    final token = AuthService.instance.currentUser?.token;
    final uri = Uri.parse(
      ApiConstants.providerRatings,
    ).replace(queryParameters: {'prestataire_id': prestataireId.toString()});
    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': token,
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Échec chargement notations: ${response.statusCode}');
    }
    return NotationsResponse.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Évalue un prestataire (note 1-5, avis optionnel).
  Future<Map<String, dynamic>> rateProvider({
    required int prestataireId,
    required int note,
    String avis = '',
  }) async {
    final token = AuthService.instance.currentUser?.token;
    final response = await http.post(
      Uri.parse(ApiConstants.rateProvider),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': token,
      },
      body: jsonEncode({
        'prestataire_id': prestataireId,
        'note': note,
        if (avis.isNotEmpty) 'avis': avis,
      }),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        body['message'] ?? 'Erreur ${response.statusCode} lors de la notation',
      );
    }
    _notifyPrestatairesChanged(ratings: true);
    return body;
  }
}
