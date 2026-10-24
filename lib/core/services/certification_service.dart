import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

import '../constants/api_constants.dart';
import 'auth_service.dart';

class CertificationService {
  CertificationService._();
  static final CertificationService instance = CertificationService._();

  String get _token => AuthService.instance.currentUser?.token ?? '';

  Future<Map<String, dynamic>> getDemande() async {
    final response = await http.get(
      Uri.parse(ApiConstants.maDemandeCertification),
      headers: {'Authorization': _token, 'Cache-Control': 'no-cache'},
    );
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        json['success'] == false) {
      throw Exception(
        json['message'] ?? 'Demande de certification indisponible',
      );
    }
    final data = json['data'];
    return data is Map<String, dynamic> ? data : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> createPayment({
    required String phone,
    required String currency,
  }) async {
    final response = await http.post(
      Uri.parse(ApiConstants.paiementCertificationCreate),
      headers: {'Authorization': _token, 'Content-Type': 'application/json'},
      body: jsonEncode({'phone': phone, 'currency': currency}),
    ).timeout(const Duration(seconds: 45));
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        json['success'] == false) {
      final error = json['error'];
      throw Exception(
        error is Map
            ? error['message']
            : json['message'] ?? 'Paiement de certification impossible',
      );
    }
    return (json['data'] as Map<String, dynamic>?) ?? const {};
  }

  Future<void> submitDocuments({
    required int demandeId,
    required String typeDocumentIdentite,
    required PlatformFile documentIdentite,
    required PlatformFile documentCompetence,
  }) async {
    final identityBytes = documentIdentite.bytes;
    final competenceBytes = documentCompetence.bytes;
    if (identityBytes == null || competenceBytes == null) {
      throw Exception('Impossible de lire les fichiers sélectionnés.');
    }
    final request = http.MultipartRequest(
      'POST',
      Uri.parse(ApiConstants.documentsCertification(demandeId)),
    )..headers['Authorization'] = _token;
    request.fields['type_document_identite'] = typeDocumentIdentite;
    request.files.add(
      http.MultipartFile.fromBytes(
        'document_identite',
        identityBytes,
        filename: documentIdentite.name,
      ),
    );
    request.files.add(
      http.MultipartFile.fromBytes(
        'document_competence',
        competenceBytes,
        filename: documentCompetence.name,
      ),
    );
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        json['success'] == false) {
      throw Exception(json['message'] ?? 'Envoi des documents impossible');
    }
  }
}
