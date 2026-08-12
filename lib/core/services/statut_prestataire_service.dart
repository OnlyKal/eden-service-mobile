import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';

import '../constants/api_constants.dart';
import '../models/statut_prestataire_models.dart';
import 'app_refresh_service.dart';
import 'auth_service.dart';
import 'statut_realtime_service.dart';

class StatutPrestataireService {
  StatutPrestataireService._();
  static final StatutPrestataireService instance = StatutPrestataireService._();

  final ValueNotifier<int> changes = ValueNotifier<int>(0);

  Future<PaginatedStatutsPrestataires> getStatuts({
    int page = 1,
    int pageSize = 20,
  }) async {
    final uri = Uri.parse(ApiConstants.statutsPrestataires).replace(
      queryParameters: {
        'page': page.toString(),
        'page_size': pageSize.toString(),
      },
    );
    final response = await http.get(uri, headers: _headers());
    if (response.statusCode != 200) {
      throw Exception('Impossible de charger les statuts.');
    }
    return PaginatedStatutsPrestataires.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<List<StatutPrestataire>> getMonStatut() async {
    final response = await http.get(
      Uri.parse(ApiConstants.monStatutPrestataire),
      headers: _headers(),
    );
    if (response.statusCode != 200) {
      throw Exception('Impossible de charger votre statut.');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final data = body['data'];
    if (data is List) {
      return data
          .whereType<Map<String, dynamic>>()
          .map(StatutPrestataire.fromJson)
          .where((statut) => !statut.isExpiredNow)
          .toList();
    }
    if (data is Map<String, dynamic>) {
      final statut = StatutPrestataire.fromJson(data);
      return statut.isExpiredNow ? [] : [statut];
    }
    return [];
  }

  Future<StatutPrestataire> getStatut(int statutId) async {
    final response = await http.get(
      Uri.parse(ApiConstants.statutPrestataireDetail(statutId)),
      headers: _headers(),
    );
    if (response.statusCode != 200) {
      throw Exception('Impossible de charger le statut.');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final data = body['data'] as Map<String, dynamic>? ?? body;
    return StatutPrestataire.fromJson(data);
  }

  Future<StatutPrestataire> toggleLike(int statutId) async {
    final response = await http.post(
      Uri.parse(ApiConstants.aimerStatutPrestataire(statutId)),
      headers: _headers(),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_errorMessage(body, 'Action impossible.'));
    }
    final data = body['data'] as Map<String, dynamic>? ?? body;
    final statut = StatutPrestataire.fromJson(data);
    StatutRealtimeService.instance.applyHttpUpdate(statut);
    return statut;
  }

  Future<List<StatutCommentaire>> getCommentaires(int statutId) async {
    final response = await http.get(
      Uri.parse(ApiConstants.commentairesStatutPrestataire(statutId)),
      headers: _headers(),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw Exception(
        _errorMessage(body, 'Impossible de charger les commentaires.'),
      );
    }
    final data = body['data'] as Map<String, dynamic>? ?? {};
    final commentaires = (data['results'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(StatutCommentaire.fromJson)
        .where((commentaire) => commentaire.contenu.trim().isNotEmpty)
        .toList();
    commentaires.sort(_compareCommentairesRecents);
    return commentaires;
  }

  Future<({StatutCommentaire commentaire, StatutPrestataire statut})>
  ajouterCommentaire(int statutId, String contenu) async {
    final response = await http.post(
      Uri.parse(ApiConstants.commentairesStatutPrestataire(statutId)),
      headers: _headers(),
      body: jsonEncode({'contenu': contenu.trim()}),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_errorMessage(body, 'Commentaire impossible.'));
    }
    final data = body['data'] as Map<String, dynamic>? ?? {};
    final commentaireRaw = data['commentaire'] as Map<String, dynamic>? ?? {};
    final statutRaw = data['statut'] as Map<String, dynamic>? ?? {};
    final commentaire = StatutCommentaire.fromJson(commentaireRaw);
    final statut = StatutPrestataire.fromJson(statutRaw);
    StatutRealtimeService.instance.applyHttpUpdate(statut);
    StatutRealtimeService.instance.applyCommentaire(
      commentaire,
      incrementCount: false,
    );
    return (commentaire: commentaire, statut: statut);
  }

  Future<StatutPrestataire> publierStatut({
    Uint8List? bytes,
    String? path,
    required String filename,
    required String typeMedia,
    String? legende,
    int? dureeVideo,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse(ApiConstants.statutsPrestataires),
    );
    request.headers.addAll(_headers(includeContentType: false));
    request.fields['type_media'] = typeMedia;
    if (legende != null && legende.trim().isNotEmpty) {
      request.fields['legende'] = legende.trim();
    }
    if (dureeVideo != null) {
      request.fields['duree_video'] = dureeVideo.toString();
    }
    final uploadFilename = _normalizedFilename(filename, typeMedia);
    if (path != null && path.isNotEmpty) {
      // Stream file from path to avoid loading entire bytes into memory.
      final mime = typeMedia == 'video' ? 'video/mp4' : lookupMimeType(uploadFilename) ?? 'image/jpeg';
      final filePart = await http.MultipartFile.fromPath(
        'media',
        path,
        filename: uploadFilename,
        contentType: MediaType.parse(mime),
      );
      request.files.add(filePart);
    } else if (bytes != null) {
      final mimeType = _uploadMimeType(uploadFilename, typeMedia, bytes);
      request.files.add(
        http.MultipartFile.fromBytes(
          'media',
          bytes,
          filename: uploadFilename,
          contentType: MediaType.parse(mimeType),
        ),
      );
    } else {
      throw Exception('No media provided for publication.');
    }

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    final body = _decodeJsonObject(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = body['error'] as Map<String, dynamic>?;
      debugPrint(
        '[StatutPrestataireService] publish failed '
        '${response.statusCode}: ${response.body}',
      );
      throw Exception(
        error?['message'] ?? body['message'] ?? 'Publication impossible.',
      );
    }
    final statut = StatutPrestataire.fromJson(
      body['data'] as Map<String, dynamic>,
    );
    notifyChanged();
    StatutRealtimeService.instance.applyHttpUpdate(statut);
    return statut;
  }

  Future<void> supprimerStatut(int statutId) async {
    final response = await http.delete(
      Uri.parse(ApiConstants.statutPrestataireDetail(statutId)),
      headers: _headers(),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Suppression impossible.');
    }
    notifyChanged();
  }

  void notifyChanged() {
    changes.value++;
    AppRefreshService.instance.notify(const {
      AppRefreshTopic.statuts,
      AppRefreshTopic.home,
      AppRefreshTopic.profile,
    });
  }

  Map<String, String> _headers({bool includeContentType = true}) {
    final token = AuthService.instance.currentUser?.token;
    return {
      if (includeContentType) 'Content-Type': 'application/json',
      if (token != null) 'Authorization': token,
    };
  }

  String _errorMessage(Map<String, dynamic> body, String fallback) {
    final error = body['error'];
    if (error is Map<String, dynamic> && error['message'] != null) {
      return error['message'].toString();
    }
    if (body['message'] != null) return body['message'].toString();
    return fallback;
  }
}

String _normalizedFilename(String filename, String typeMedia) {
  final trimmed = filename.trim();
  final fallback = typeMedia == 'video' ? 'statut.mp4' : 'statut.jpg';
  if (trimmed.isEmpty) return fallback;
  if (typeMedia == 'video' && !_hasAllowedVideoExtension(trimmed)) {
    return '${_filenameWithoutExtension(trimmed)}.mp4';
  }
  if (trimmed.contains('.')) return trimmed;
  return '$trimmed${typeMedia == 'video' ? '.mp4' : '.jpg'}';
}

String _uploadMimeType(String filename, String typeMedia, Uint8List bytes) {
  if (typeMedia == 'video') return 'video/mp4';
  return lookupMimeType(filename, headerBytes: bytes) ?? 'image/jpeg';
}

bool _hasAllowedVideoExtension(String filename) {
  final lower = filename.toLowerCase();
  return lower.endsWith('.mp4') || lower.endsWith('.m4v');
}

String _filenameWithoutExtension(String filename) {
  final slashIndex = filename.lastIndexOf(RegExp(r'[/\\]'));
  final start = slashIndex == -1 ? 0 : slashIndex + 1;
  final dotIndex = filename.lastIndexOf('.');
  if (dotIndex <= start) return filename;
  return filename.substring(0, dotIndex);
}

Map<String, dynamic> _decodeJsonObject(String source) {
  try {
    final decoded = jsonDecode(source);
    if (decoded is Map<String, dynamic>) return decoded;
  } catch (_) {
    // The status endpoint normally returns JSON, but HTML/plain-text errors
    // should still surface as a controlled publication failure.
  }
  return const {};
}

int _compareCommentairesRecents(StatutCommentaire a, StatutCommentaire b) {
  final dateA = a.dateCreation;
  final dateB = b.dateCreation;
  if (dateA != null && dateB != null) return dateB.compareTo(dateA);
  if (dateA != null) return -1;
  if (dateB != null) return 1;
  return b.id.compareTo(a.id);
}
