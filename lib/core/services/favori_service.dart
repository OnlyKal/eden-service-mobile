import 'dart:convert';

import 'package:http/http.dart' as http;

import '../constants/api_constants.dart';
import '../models/favori_models.dart';
import 'app_refresh_service.dart';
import 'auth_service.dart';

class FavoriService {
  FavoriService._();
  static final FavoriService instance = FavoriService._();

  Future<PaginatedFavoris> getFavoris() async {
    final response = await http.get(
      Uri.parse(ApiConstants.favoris),
      headers: _headers(),
    );

    if (response.statusCode != 200) {
      throw Exception(
        _errorMessage(
          response,
          'Erreur ${response.statusCode} lors du chargement des favoris',
        ),
      );
    }

    return PaginatedFavoris.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<Favori> addFavori(int prestataireId) async {
    final response = await http.post(
      Uri.parse(ApiConstants.favoris),
      headers: _headers(),
      body: jsonEncode({'prestataire': prestataireId}),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        _errorMessage(
          response,
          'Erreur ${response.statusCode} lors de l’ajout aux favoris',
        ),
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final favori = Favori.fromJson(json['data'] as Map<String, dynamic>);
    AppRefreshService.instance.notify(const {
      AppRefreshTopic.favorites,
      AppRefreshTopic.home,
      AppRefreshTopic.prestataires,
    });
    return favori;
  }

  Future<void> removeFavori(int favoriId) async {
    final response = await http.delete(
      Uri.parse(ApiConstants.favoriDetail(favoriId)),
      headers: _headers(),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        _errorMessage(
          response,
          'Erreur ${response.statusCode} lors du retrait du favori',
        ),
      );
    }
    AppRefreshService.instance.notify(const {
      AppRefreshTopic.favorites,
      AppRefreshTopic.home,
      AppRefreshTopic.prestataires,
    });
  }

  Future<void> removeFavoriByPrestataire(int prestataireId) async {
    final response = await http.delete(
      Uri.parse(ApiConstants.retirerFavori),
      headers: _headers(),
      body: jsonEncode({'prestataire': prestataireId}),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        _errorMessage(
          response,
          'Erreur ${response.statusCode} lors du retrait du favori',
        ),
      );
    }
    AppRefreshService.instance.notify(const {
      AppRefreshTopic.favorites,
      AppRefreshTopic.home,
      AppRefreshTopic.prestataires,
    });
  }

  Map<String, String> _headers() {
    final token = AuthService.instance.currentUser?.token;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': token,
    };
  }

  String _errorMessage(http.Response response, String fallback) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final error = body['error'];
      if (error is Map<String, dynamic> && error['message'] != null) {
        return error['message'] as String;
      }
      if (body['message'] != null) return body['message'] as String;
    } catch (_) {
      return fallback;
    }
    return fallback;
  }
}
