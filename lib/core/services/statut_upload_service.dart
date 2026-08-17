import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';
import 'package:video_compress/video_compress.dart';

import '../constants/api_constants.dart';
import '../models/statut_prestataire_models.dart';
import 'auth_service.dart';
import 'statut_prestataire_service.dart';
import 'statut_realtime_service.dart';

/// État d'une publication en cours.
enum StatutUploadStatus { idle, preparing, uploading, done, failed }

/// Publication de statut en arrière-plan, façon WhatsApp :
/// l'upload démarre immédiatement, l'utilisateur peut continuer à naviguer,
/// une progression claire est affichée, et une nouvelle tentative est
/// possible en cas d'échec réseau.
class StatutUploadService {
  StatutUploadService._();

  static final StatutUploadService instance = StatutUploadService._();

  /// Notifie les écrans de l'état de la publication en cours.
  final ValueNotifier<StatutUploadStatus> status =
      ValueNotifier<StatutUploadStatus>(StatutUploadStatus.idle);

  /// Progression 0.0 → 1.0.
  final ValueNotifier<double> progress = ValueNotifier<double>(0);

  /// Message d'erreur en cas d'échec.
  final ValueNotifier<String?> error = ValueNotifier<String?>(null);

  /// Dernier statut créé avec succès (pour mise à jour immédiate de l'UI).
  StatutPrestataire? lastCreatedStatut;

  /// Légende associée à la publication en cours.
  String? _legende;

  /// Fichier en cours d'envoi.
  XFileLike? _pendingFile;
  String _typeMedia = 'photo';
  int? _dureeVideo;
  bool _cancelled = false;

  bool get isUploading =>
      status.value == StatutUploadStatus.preparing ||
      status.value == StatutUploadStatus.uploading;

  /// Démarre la publication immédiatement en arrière-plan.
  Future<void> startUpload({
    required String path,
    required String filename,
    required String typeMedia,
    String? legende,
    int? dureeVideo,
  }) async {
    // Annule une éventuelle publication précédente.
    _cancelled = true;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    _cancelled = false;

    _legende = legende;
    _typeMedia = typeMedia;
    _dureeVideo = dureeVideo;
    _pendingFile = XFileLike(path: path, name: filename);
    error.value = null;
    progress.value = 0;
    status.value = StatutUploadStatus.preparing;

    unawaited(_run());
  }

  Future<void> _run() async {
    try {
      // 1. Compression rapide (images déjà compressées par image_picker).
      final prepared = await _prepareForUpload();
      if (_cancelled || prepared == null) return;

      // 2. Upload avec progression.
      status.value = StatutUploadStatus.uploading;
      final statut = await _uploadWithProgress(prepared);
      if (_cancelled) return;

      // 3. Succès → notifier les écrans.
      lastCreatedStatut = statut;
      status.value = StatutUploadStatus.done;
      progress.value = 1.0;
      StatutPrestataireService.instance.notifyChanged();
      StatutRealtimeService.instance.applyHttpUpdate(statut);
    } catch (e) {
      if (_cancelled) return;
      status.value = StatutUploadStatus.failed;
      error.value = _friendlyError(e);
      debugPrint('[StatutUpload] failed: $e');
    }
  }

  /// Prépare le fichier : compression vidéo rapide si nécessaire.
  Future<XFileLike?> _prepareForUpload() async {
    final file = _pendingFile;
    if (file == null) return null;

    if (_typeMedia == 'video') {
      // Sur iOS, la galerie retourne souvent des vidéos .mov (QuickTime).
      // On les convertit en MP4 pour garantir la compatibilité serveur.
      final isMov = _isMovFile(file.name) || _isMovFile(file.path);
      if (isMov) {
        try {
          final compressed = await VideoCompress.compressVideo(
            file.path,
            quality: VideoQuality.MediumQuality,
            deleteOrigin: false,
            includeAudio: true,
          );
          final path = compressed?.path;
          if (path != null && path.isNotEmpty) {
            return XFileLike(path: path, name: 'statut.mp4');
          }
        } catch (e) {
          debugPrint('[StatutUpload] mov→mp4 conversion error: $e');
          // On envoie l'original si la conversion échoue.
        }
      }

      // Compression rapide en LowQuality (suffisant pour un statut 24h).
      // On ne compresse que si le fichier dépasse 8 Mo pour éviter
      // les traitements inutiles sur les petites vidéos.
      final size = await _fileSize(file.path);
      if (size > 8 * 1024 * 1024) {
        try {
          final compressed = await VideoCompress.compressVideo(
            file.path,
            quality: VideoQuality.LowQuality,
            deleteOrigin: false,
            includeAudio: true,
          );
          final path = compressed?.path;
          if (path != null && path.isNotEmpty) {
            return XFileLike(path: path, name: 'statut.mp4');
          }
        } catch (e) {
          debugPrint('[StatutUpload] video compress error: $e');
          // On envoie l'original si la compression échoue.
        }
      }
    }
    return file;
  }

  bool _isMovFile(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.mov') || lower.endsWith('.quicktime');
  }

  Future<int> _fileSize(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) return await file.length();
    } catch (_) {}
    return 0;
  }

  /// Upload avec suivi de progression via le stream de la requête.
  Future<StatutPrestataire> _uploadWithProgress(XFileLike file) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse(ApiConstants.statutsPrestataires),
    );
    final token = AuthService.instance.currentUser?.token;
    request.headers.addAll({
      if (token != null) 'Authorization': token,
    });
    request.fields['type_media'] = _typeMedia;
    if (_legende != null && _legende!.trim().isNotEmpty) {
      request.fields['legende'] = _legende!.trim();
    }
    if (_dureeVideo != null) {
      request.fields['duree_video'] = _dureeVideo.toString();
    }

    final uploadFilename = _normalizedFilename(file.name, _typeMedia);
    final mime = _typeMedia == 'video'
        ? 'video/mp4'
        : lookupMimeType(uploadFilename) ?? 'image/jpeg';

    // IMPORTANT (iOS) : on lit le fichier en bytes AVANT de créer la requête.
    // Sur iOS, les chemins temporaires de image_picker peuvent être nettoyés
    // par le système entre la sélection et l'upload. Lire les bytes
    // immédiatement garantit que le fichier est disponible.
    final bytes = await _readFileBytes(file.path);
    if (bytes == null) {
      throw Exception('Impossible de lire le fichier sélectionné.');
    }

    final filePart = http.MultipartFile.fromBytes(
      'media',
      bytes,
      filename: uploadFilename,
      contentType: MediaType.parse(mime),
    );
    request.files.add(filePart);

    // Envoi avec suivi de progression.
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Publication impossible (${response.statusCode}).');
    }

    final body = _decodeJsonObject(response.body);
    final statut = StatutPrestataire.fromJson(
      body['data'] as Map<String, dynamic>,
    );
    return statut;
  }

  /// Lit le fichier en bytes de manière robuste (iOS/Android/web).
  Future<Uint8List?> _readFileBytes(String path) async {
    try {
      if (kIsWeb) {
        // Sur web, le path est une URL blob/data.
        final response = await http.get(Uri.parse(path));
        if (response.statusCode == 200) return response.bodyBytes;
        return null;
      }
      final file = File(path);
      if (!await file.exists()) return null;
      return await file.readAsBytes();
    } catch (e) {
      debugPrint('[StatutUpload] read file bytes error: $e');
      return null;
    }
  }

  /// Nouvelle tentative après échec.
  Future<void> retry() async {
    final file = _pendingFile;
    if (file == null) return;
    error.value = null;
    progress.value = 0;
    status.value = StatutUploadStatus.preparing;
    unawaited(_run());
  }

  /// Annule la publication en cours.
  void cancel() {
    _cancelled = true;
    _pendingFile = null;
    lastCreatedStatut = null;
    status.value = StatutUploadStatus.idle;
    progress.value = 0;
    error.value = null;
  }

  String _friendlyError(Object e) {
    final raw = e.toString().replaceFirst('Exception: ', '').trim();
    if (raw.contains('SocketException') ||
        raw.contains('Connection refused') ||
        raw.contains('timed out') ||
        raw.contains('TimeoutException')) {
      return 'Connexion perdue. Vérifiez votre réseau et réessayez.';
    }
    if (raw.contains('NOT_PROVIDER')) {
      return 'La publication de statut est réservée aux prestataires.';
    }
    if (raw.contains('SUBSCRIPTION_REQUIRED')) {
      return 'Un abonnement actif est nécessaire pour publier un statut.';
    }
    if (raw.contains('ACTIVE_STATUS_EXISTS')) {
      return 'Vous avez déjà un statut actif.';
    }
    if (raw.contains('DAILY_LIMIT_REACHED')) {
      return 'Vous avez déjà publié votre statut du jour. Revenez demain !';
    }
    if (raw.contains('Impossible de lire le fichier')) {
      return 'Impossible de lire le fichier. Réessayez avec un autre média.';
    }
    return raw.isEmpty ? 'Une erreur est survenue.' : raw;
  }

  String _normalizedFilename(String filename, String typeMedia) {
    final trimmed = filename.trim();
    final fallback = typeMedia == 'video' ? 'statut.mp4' : 'statut.jpg';
    if (trimmed.isEmpty) return fallback;

    // Si c'est une vidéo .mov (iOS), on renomme en .mp4.
    if (typeMedia == 'video' && _isMovFile(trimmed)) {
      return 'statut.mp4';
    }

    if (typeMedia == 'video' && !trimmed.toLowerCase().endsWith('.mp4')) {
      final dotIndex = trimmed.lastIndexOf('.');
      if (dotIndex > 0) {
        return '${trimmed.substring(0, dotIndex)}.mp4';
      }
      return 'statut.mp4';
    }
    if (trimmed.contains('.')) return trimmed;
    return '$trimmed${typeMedia == 'video' ? '.mp4' : '.jpg'}';
  }

  Map<String, dynamic> _decodeJsonObject(String source) {
    try {
      final decoded = jsonDecode(source);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return const {};
  }
}

/// Représente un fichier à uploader (chemin + nom).
class XFileLike {
  const XFileLike({required this.path, required this.name});

  final String path;
  final String name;
}