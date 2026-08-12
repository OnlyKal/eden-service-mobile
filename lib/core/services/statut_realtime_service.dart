import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../constants/api_constants.dart';
import '../models/statut_prestataire_models.dart';
import 'app_refresh_service.dart';
import 'auth_service.dart';

class StatutRealtimeService {
  StatutRealtimeService._();

  static final StatutRealtimeService instance = StatutRealtimeService._();

  final ValueNotifier<int> changes = ValueNotifier<int>(0);

  final Map<String, _StatutRealtimeSocket> _sockets =
      <String, _StatutRealtimeSocket>{};
  final Map<int, int> _statutWatchers = <int, int>{};
  int _globalWatchers = 0;
  int _userWatchers = 0;
  final Map<int, DateTime> _recentLocalUpdates = <int, DateTime>{};
  final Set<int> _realtimeUpdatedStatutIds = <int>{};
  final Map<int, StatutPrestataire> _statuts = <int, StatutPrestataire>{};
  final Map<int, List<StatutCommentaire>> _commentaires =
      <int, List<StatutCommentaire>>{};

  void registerStatuts(Iterable<StatutPrestataire> statuts) {
    final seenIds = <int>{};
    for (final statut in statuts) {
      if (statut.id <= 0) continue;
      seenIds.add(statut.id);
      final current = _statuts[statut.id];
      _statuts[statut.id] = current == null
          ? statut
          : _realtimeUpdatedStatutIds.contains(statut.id)
          ? _mergeStatut(statut, current)
          : _mergeStatut(current, statut);
      if (statut.commentaires.isNotEmpty) {
        _commentaires[statut.id] = _mergeCommentaires(
          _commentaires[statut.id] ?? const [],
          statut.commentaires,
        );
      }
    }
    // Purge realtime-override flags for statuts no longer present in the
    // incoming list: the next fresh API registration will then be able to
    // overwrite the cached values (avoids stale counters after deletions,
    // corrections, etc.).
    _realtimeUpdatedStatutIds.retainAll(seenIds);
  }

  void watchGlobal() {
    _globalWatchers++;
    final token = AuthService.instance.currentUser?.token;
    _ensureSocket(
      key: 'global',
      uri: ApiConstants.statutsPrestatairesWs(token),
      fallbackId: 0,
    );
  }

  void unwatchGlobal() {
    if (_globalWatchers > 0) _globalWatchers--;
    if (_globalWatchers == 0) _closeSocket('global');
  }

  void watchUser() {
    final token = AuthService.instance.currentUser?.token;
    if (token == null || token.trim().isEmpty) return;
    _userWatchers++;
    _ensureSocket(
      key: 'user',
      uri: ApiConstants.userRealtimeWs(token),
      fallbackId: 0,
    );
  }

  void unwatchUser() {
    if (_userWatchers > 0) _userWatchers--;
    if (_userWatchers == 0) _closeSocket('user');
  }

  void watchStatut(int statutId) {
    if (statutId <= 0) return;
    _statutWatchers[statutId] = (_statutWatchers[statutId] ?? 0) + 1;
    final token = AuthService.instance.currentUser?.token;
    _ensureSocket(
      key: _statutKey(statutId),
      uri: ApiConstants.statutPrestataireInteractionsWs(statutId, token),
      fallbackId: statutId,
    );
  }

  void unwatchStatut(int statutId) {
    if (statutId <= 0) return;
    final next = (_statutWatchers[statutId] ?? 0) - 1;
    if (next > 0) {
      _statutWatchers[statutId] = next;
      return;
    }
    _statutWatchers.remove(statutId);
    _closeSocket(_statutKey(statutId));
  }

  void watchStatuts(Iterable<int?> statutIds) {
    for (final statutId in statutIds.whereType<int>()) {
      watchStatut(statutId);
    }
  }

  void _ensureSocket({
    required String key,
    required Uri uri,
    required int fallbackId,
  }) {
    final socket = _sockets[key];
    if (socket != null && socket.uri == uri) return;
    socket?.dispose();
    _sockets[key] = _StatutRealtimeSocket(
      key: key,
      uri: uri,
      fallbackId: fallbackId,
      onEvent: _handleEvent,
      shouldReconnect: () => _shouldKeepSocket(key, fallbackId),
    )..connect();
  }

  StatutPrestataire applyTo(StatutPrestataire statut) {
    final cached = _statuts[statut.id];
    if (cached == null) return statut;
    return _mergeStatut(statut, cached);
  }

  List<StatutPrestataire> applyToList(List<StatutPrestataire> statuts) {
    return statuts.map(applyTo).toList();
  }

  List<StatutCommentaire> commentairesFor(
    int statutId,
    List<StatutCommentaire> fallback,
  ) {
    return List<StatutCommentaire>.from(_commentaires[statutId] ?? fallback)
      ..sort(_compareCommentairesRecents);
  }

  void applyHttpUpdate(StatutPrestataire statut) {
    if (statut.id <= 0) return;
    _recentLocalUpdates[statut.id] = DateTime.now();
    _realtimeUpdatedStatutIds.add(statut.id);
    _statuts[statut.id] = _mergeStatut(_statuts[statut.id] ?? statut, statut);
    if (statut.commentaires.isNotEmpty) {
      _commentaires[statut.id] = _mergeCommentaires(
        _commentaires[statut.id] ?? const [],
        statut.commentaires,
      );
    }
    _emit();
  }

  void applyCommentaire(
    StatutCommentaire commentaire, {
    bool incrementCount = true,
  }) {
    if (commentaire.statut <= 0 || commentaire.contenu.trim().isEmpty) return;
    final currentList = _commentaires[commentaire.statut] ?? const [];
    final alreadyKnown = currentList.any(
      (item) =>
          (item.id > 0 && item.id == commentaire.id) ||
          (item.id <= 0 && _sameComment(item, commentaire)),
    );
    _commentaires[commentaire.statut] = _mergeCommentaires(currentList, [
      commentaire,
    ]);
    final current = _statuts[commentaire.statut];
    if (current != null) {
      final localCount = _commentaires[commentaire.statut]!.length;
      final realtimeCount = alreadyKnown
          ? current.nombreCommentaires
          : incrementCount
          ? current.nombreCommentaires + 1
          : current.nombreCommentaires;
      _statuts[commentaire.statut] = current.copyWith(
        nombreCommentaires: localCount > realtimeCount
            ? localCount
            : realtimeCount,
        commentaires: _commentaires[commentaire.statut],
      );
      _realtimeUpdatedStatutIds.add(commentaire.statut);
    }
    _emit();
  }

  void removeCommentaire(
    StatutCommentaire commentaire, {
    StatutPrestataire? statut,
    bool decrementCount = true,
  }) {
    if (statut != null) applyHttpUpdate(statut);
    _removeCommentaire(
      commentaire,
      decrementCount: statut == null && decrementCount,
    );
  }

  void applyStatutPayload(int fallbackId, Map<String, dynamic> raw) {
    _applyStatutRaw(
      fallbackId,
      raw,
      allowAimeParMoiUpdate: true,
      replaceCommentaires: false,
    );
  }

  void _handleEvent(int statutId, dynamic event) {
    try {
      final payload = _decodePayload(event);
      if (payload == null) {
        if (kDebugMode) {
          debugPrint('[StatutRealtime] ignored unsupported event=$event');
        }
        return;
      }
      final type = (payload['type'] ?? payload['event'])?.toString();
      var handled = false;
      for (final body in _candidateBodies(payload)) {
        handled = _applyRealtimeBody(statutId, body, type) || handled;
      }
      debugPrint(
        '[StatutRealtime] type=$type fallback=$statutId handled=$handled payload=$payload',
      );

      final action = _firstValue(payload, const ['action'])?.toString();
      if (handled &&
          (type == 'like' ||
              type == 'liked' ||
              type == 'commentaire' ||
              type == 'comment' ||
              type == 'commentaire_supprime' ||
              type == 'statut_interaction' ||
              type == 'status_update' ||
              action == 'like' ||
              action == 'like_added' ||
              action == 'like_removed' ||
              action == 'commentaire' ||
              action == 'comment_added' ||
              action == 'commentaire_supprime' ||
              type == 'notification')) {
        AppRefreshService.instance.notify(const {
          AppRefreshTopic.notifications,
        });
      }
    } catch (error, stackTrace) {
      // Keep realtime resilient to unexpected payload shapes.
      if (kDebugMode) {
        debugPrint('[StatutRealtime] failed to handle event=$event');
        debugPrint('$error');
        debugPrint('$stackTrace');
      }
    }
  }

  bool _applyRealtimeBody(
    int fallbackId,
    Map<String, dynamic> body,
    String? type,
  ) {
    var handled = false;
    final action = _firstValue(body, const [
      'action',
      'operation',
    ])?.toString().toLowerCase();
    final eventUserId = _parseInt(
      _firstValue(body, const [
        'utilisateur',
        'utilisateur_id',
        'user',
        'user_id',
      ]),
    );
    // When the backend omits user_id for like events, we still want to apply
    // aime_par_moi if the event carries an explicit `liked` flag AND a recent
    // local update exists for this statut (this is almost certainly our own
    // echo). Otherwise we keep the field untouched.
    final allowAimeParMoiUpdate =
        eventUserId != null &&
        eventUserId == AuthService.instance.currentUser?.userId;
    final hasCounterUpdate =
        _looksLikeStatutUpdate(body) ||
        _mapValue(body, const [
              'statut',
              'status',
              'statut_prestataire',
              'status_prestataire',
            ]) !=
            null;

    final statutRaw =
        _mapValue(body, const [
          'statut',
          'status',
          'statut_prestataire',
          'status_prestataire',
        ]) ??
        (_looksLikeStatutUpdate(body) ? body : null);
    if (statutRaw != null) {
      final liked = _firstValue(body, const ['liked', 'aime_par_moi']);
      final rawWithUserLike = allowAimeParMoiUpdate && liked != null
          ? <String, dynamic>{...statutRaw, 'aime_par_moi': liked}
          : statutRaw;
      _applyStatutRaw(
        fallbackId,
        rawWithUserLike,
        allowAimeParMoiUpdate: allowAimeParMoiUpdate,
        replaceCommentaires: action != null && action.contains('comment'),
      );
      handled = true;
    }

    final commentaireRaw =
        _mapValue(body, const [
          'commentaire',
          'comment',
          'new_comment',
          'commentaire_statut',
        ]) ??
        (_looksLikeCommentaire(body) ? body : null);
    if (commentaireRaw != null) {
      final commentaire = _commentaireFromRaw(
        _resolveStatutIdForComment(
          fallbackId: fallbackId,
          body: body,
          statutRaw: statutRaw,
          commentaireRaw: commentaireRaw,
        ),
        commentaireRaw,
      );
      if (_isCommentDeleteAction(action)) {
        _removeCommentaire(commentaire, decrementCount: statutRaw == null);
      } else {
        applyCommentaire(
          commentaire,
          incrementCount: statutRaw == null && !_isCommentUpdateAction(action),
        );
      }
      handled = true;
    }

    if (!hasCounterUpdate && _looksLikeLikeEvent(type, body)) {
      handled = _applyLikeDelta(fallbackId, body, type) || handled;
    }

    if (!hasCounterUpdate &&
        commentaireRaw == null &&
        _looksLikeCommentaireEvent(type, body)) {
      handled = _applyCommentaireDelta(fallbackId, body) || handled;
    }

    return handled;
  }

  void _applyStatutRaw(
    int fallbackId,
    Map<String, dynamic> raw, {
    required bool allowAimeParMoiUpdate,
    required bool replaceCommentaires,
  }) {
    final statutId =
        _parseInt(
          _firstValue(raw, const [
            'id',
            'statut',
            'status',
            'statut_id',
            'status_id',
            'statut_prestataire',
          ]),
        ) ??
        fallbackId;
    if (statutId <= 0) return;

    final existing = _statuts[statutId];
    if (existing != null) {
      _statuts[statutId] = existing.copyWith(
        nombreVues: _parseInt(
          _firstValue(raw, const ['nombre_vues', 'vues', 'views_count']),
        ),
        nombreLikes: _parseInt(
          _firstValue(raw, const [
            'nombre_likes',
            'likes',
            'likes_count',
            'like_count',
            'total_likes',
          ]),
        ),
        nombreCommentaires: _parseInt(
          _firstValue(raw, const [
            'nombre_commentaires',
            'commentaires',
            'comments',
            'comments_count',
            'comment_count',
            'total_comments',
          ]),
        ),
        vuParMoi: allowAimeParMoiUpdate
            ? _parseBoolOrNull(
                _firstValue(raw, const [
                  'vu_par_moi',
                  'vue_par_moi',
                  'viewed_by_me',
                  'deja_vu',
                  'is_viewed',
                ]),
              )
            : null,
        aimeParMoi: allowAimeParMoiUpdate
            ? _parseBoolOrNull(
                _firstValue(raw, const [
                  'aime_par_moi',
                  'liked_by_me',
                  'is_liked',
                  'liked',
                ]),
              )
            : null,
      );
      _realtimeUpdatedStatutIds.add(statutId);
      final commentairesRaw = raw['commentaires'];
      if (commentairesRaw is List) {
        final commentaires = commentairesRaw
            .whereType<Map<String, dynamic>>()
            .map(StatutCommentaire.fromJson)
            .where((commentaire) => commentaire.contenu.trim().isNotEmpty)
            .toList();
        if (replaceCommentaires || commentaires.isNotEmpty) {
          _commentaires[statutId] = replaceCommentaires
              ? commentaires
              : _mergeCommentaires(
                  _commentaires[statutId] ?? const [],
                  commentaires,
                );
          _statuts[statutId] = _statuts[statutId]!.copyWith(
            commentaires: _commentaires[statutId],
          );
        }
      }
    } else {
      _statuts[statutId] = StatutPrestataire.fromJson(raw);
      _realtimeUpdatedStatutIds.add(statutId);
    }
    _emit();
  }

  StatutPrestataire _mergeStatut(
    StatutPrestataire base,
    StatutPrestataire update,
  ) {
    return base.copyWith(
      nombreVues: update.nombreVues,
      nombreLikes: update.nombreLikes,
      nombreCommentaires: update.nombreCommentaires,
      aimeParMoi: update.aimeParMoi,
      vuParMoi: update.vuParMoi,
      commentaires: update.commentaires.isEmpty
          ? base.commentaires
          : _mergeCommentaires(base.commentaires, update.commentaires),
    );
  }

  List<StatutCommentaire> _mergeCommentaires(
    List<StatutCommentaire> existing,
    List<StatutCommentaire> incoming,
  ) {
    final byId = <int, StatutCommentaire>{
      for (final item in existing)
        if (item.id > 0) item.id: item,
    };
    final withoutId = <StatutCommentaire>[
      ...existing.where((item) => item.id <= 0),
    ];

    for (final item in incoming) {
      if (item.contenu.trim().isEmpty) continue;
      if (item.id > 0) {
        byId[item.id] = item;
      } else if (!withoutId.any((old) => _sameComment(old, item))) {
        withoutId.add(item);
      }
    }

    return <StatutCommentaire>[...byId.values, ...withoutId]
      ..sort(_compareCommentairesRecents);
  }

  bool _sameComment(StatutCommentaire a, StatutCommentaire b) {
    return a.statut == b.statut &&
        a.utilisateur?.id == b.utilisateur?.id &&
        a.contenu == b.contenu &&
        a.dateCreation?.toIso8601String() == b.dateCreation?.toIso8601String();
  }

  void _closeSocket(String key) {
    final socket = _sockets.remove(key);
    socket?.dispose();
  }

  void _emit() {
    if (kDebugMode) {
      debugPrint('[StatutRealtime] emit changes=${changes.value + 1}');
    }
    // Prune stale local-update markers so they do not grow unbounded.
    final now = DateTime.now();
    _recentLocalUpdates.removeWhere(
      (_, at) => now.difference(at) > const Duration(seconds: 10),
    );
    changes.value++;
  }

  bool _applyLikeDelta(int fallbackId, Map<String, dynamic> raw, String? type) {
    final statutId = _statutIdFromRaw(raw) ?? fallbackId;
    final current = _statuts[statutId];
    if (statutId <= 0 || current == null) return false;
    if (_isRecentEchoFromCurrentUser(statutId, raw, current)) return true;

    final delta = _isUnlikeEvent(type, raw) ? -1 : 1;
    final nextCount = (current.nombreLikes + delta).clamp(0, 1 << 31).toInt();
    final eventUserId = _parseInt(
      _firstValue(raw, const [
        'utilisateur',
        'utilisateur_id',
        'user',
        'user_id',
      ]),
    );
    final allowAimeParMoiUpdate =
        eventUserId != null &&
        eventUserId == AuthService.instance.currentUser?.userId;
    _statuts[statutId] = current.copyWith(
      nombreLikes: nextCount,
      aimeParMoi: allowAimeParMoiUpdate
          ? _parseBoolOrNull(
              _firstValue(raw, const [
                'aime_par_moi',
                'liked_by_me',
                'is_liked',
                'liked',
              ]),
            )
          : null,
    );
    _realtimeUpdatedStatutIds.add(statutId);
    _emit();
    return true;
  }

  bool _applyCommentaireDelta(int fallbackId, Map<String, dynamic> raw) {
    final statutId = _statutIdFromRaw(raw) ?? fallbackId;
    final current = _statuts[statutId];
    if (statutId <= 0 || current == null) return false;
    if (_isRecentEchoFromCurrentUser(statutId, raw, current)) return true;

    _statuts[statutId] = current.copyWith(
      nombreCommentaires: current.nombreCommentaires + 1,
    );
    _realtimeUpdatedStatutIds.add(statutId);
    _emit();
    return true;
  }

  void _removeCommentaire(
    StatutCommentaire commentaire, {
    required bool decrementCount,
  }) {
    if (commentaire.statut <= 0) return;
    final currentList = _commentaires[commentaire.statut] ?? const [];
    final nextList = currentList
        .where((item) => item.id <= 0 || item.id != commentaire.id)
        .toList();
    _commentaires[commentaire.statut] = nextList;
    final current = _statuts[commentaire.statut];
    if (current != null) {
      _statuts[commentaire.statut] = current.copyWith(
        nombreCommentaires: decrementCount
            ? (current.nombreCommentaires - 1).clamp(0, 1 << 31).toInt()
            : current.nombreCommentaires,
        commentaires: nextList,
      );
      _realtimeUpdatedStatutIds.add(commentaire.statut);
    }
    _emit();
  }

  int? _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  bool? _parseBoolOrNull(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final lower = value.toLowerCase().trim();
      if (lower == 'true' || lower == '1' || lower == 'yes') return true;
      if (lower == 'false' || lower == '0' || lower == 'no') return false;
    }
    return null;
  }

  List<Map<String, dynamic>> _candidateBodies(Map<String, dynamic> payload) {
    final bodies = <Map<String, dynamic>>[payload];
    for (final key in const ['data', 'payload', 'message', 'event_data']) {
      final value = payload[key];
      if (value is Map<String, dynamic>) {
        bodies.add({
          if (payload['action'] != null && value['action'] == null)
            'action': payload['action'],
          if (payload['status_id'] != null && value['statut'] == null)
            'statut_id': payload['status_id'],
          if (payload['status_id'] != null && value['status_id'] == null)
            'status_id': payload['status_id'],
          ...value,
        });
      }
    }
    return bodies;
  }

  Map<String, dynamic>? _mapValue(Map<String, dynamic> raw, List<String> keys) {
    for (final key in keys) {
      final value = raw[key];
      if (value is Map<String, dynamic>) return value;
    }
    return null;
  }

  dynamic _firstValue(Map<String, dynamic> raw, List<String> keys) {
    for (final key in keys) {
      if (raw.containsKey(key) && raw[key] != null) return raw[key];
    }
    return null;
  }

  bool _looksLikeStatutUpdate(Map<String, dynamic> raw) {
    return _firstValue(raw, const [
          'nombre_likes',
          'likes_count',
          'like_count',
          'total_likes',
          'nombre_commentaires',
          'comments_count',
          'comment_count',
          'total_comments',
          'aime_par_moi',
          'liked_by_me',
          'is_liked',
        ]) !=
        null;
  }

  bool _looksLikeLikeEvent(String? type, Map<String, dynamic> raw) {
    final lowerType = type?.toLowerCase() ?? '';
    if (lowerType.contains('like') || lowerType.contains('aime')) return true;
    final action = _firstValue(raw, const [
      'action',
      'operation',
      'event',
      'type',
    ])?.toString().toLowerCase();
    return action != null &&
        (action.contains('like') || action.contains('aime'));
  }

  bool _looksLikeCommentaireEvent(String? type, Map<String, dynamic> raw) {
    final lowerType = type?.toLowerCase() ?? '';
    if (lowerType.contains('comment') || lowerType.contains('commentaire')) {
      return true;
    }
    final action = _firstValue(raw, const [
      'action',
      'operation',
      'event',
      'type',
    ])?.toString().toLowerCase();
    return action != null &&
        (action.contains('comment') || action.contains('commentaire'));
  }

  bool _isCommentDeleteAction(String? action) {
    if (action == null) return false;
    return action.contains('delete') ||
        action.contains('remove') ||
        action.contains('supprim');
  }

  bool _isCommentUpdateAction(String? action) {
    if (action == null) return false;
    return action.contains('update') ||
        action.contains('edit') ||
        action.contains('modif');
  }

  bool _isUnlikeEvent(String? type, Map<String, dynamic> raw) {
    final action = [
      type,
      _firstValue(raw, const [
        'action',
        'operation',
        'event',
        'type',
      ])?.toString(),
    ].whereType<String>().join(' ').toLowerCase();
    final explicitLiked = _parseBoolOrNull(
      _firstValue(raw, const [
        'liked',
        'is_liked',
        'aime_par_moi',
        'liked_by_me',
      ]),
    );
    return explicitLiked == false ||
        action.contains('unlike') ||
        action.contains('dislike') ||
        action.contains('remove') ||
        action.contains('delete') ||
        action.contains('unliked');
  }

  bool _isRecentEchoFromCurrentUser(
    int statutId,
    Map<String, dynamic> raw,
    StatutPrestataire current,
  ) {
    final currentUserId = AuthService.instance.currentUser?.userId;
    final localUpdateAt = _recentLocalUpdates[statutId];
    if (localUpdateAt == null) return false;
    if (DateTime.now().difference(localUpdateAt) >= Duration(seconds: 3)) {
      return false;
    }
    final eventUserId = _parseInt(
      _firstValue(raw, const [
        'user',
        'user_id',
        'utilisateur',
        'utilisateur_id',
        'sender',
        'sender_id',
      ]),
    );
    // Ignore echo clearly from the current user.
    if (eventUserId != null) {
      return eventUserId == currentUserId;
    }
    // No user_id in the payload: we need heuristics to avoid both double-counting
    // our own optimistic like AND missing likes from other users.
    final likedFlag = _parseBoolOrNull(
      _firstValue(raw, const [
        'aime_par_moi',
        'liked_by_me',
        'is_liked',
        'liked',
      ]),
    );
    if (likedFlag != null) {
      // If the flag matches our current local state, this is our own echo
      // (we already optimistically applied it). A different flag means another
      // user liked/unliked or a server correction → apply it.
      return likedFlag == current.aimeParMoi;
    }
    // No explicit flag and no user_id: ambiguous. Treat as our own echo only
    // if the event arrives within the first second of the local update, which
    // is the typical timing of a websocket echo. Beyond that, apply the delta.
    return DateTime.now().difference(localUpdateAt) < Duration(seconds: 1);
  }

  int? _statutIdFromRaw(Map<String, dynamic> raw) {
    return _parseInt(
      _firstValue(raw, const [
        'id',
        'statut',
        'status',
        'statut_id',
        'status_id',
        'statut_prestataire',
        'statut_prestataire_id',
      ]),
    );
  }

  int _resolveStatutIdForComment({
    required int fallbackId,
    required Map<String, dynamic> body,
    required Map<String, dynamic>? statutRaw,
    required Map<String, dynamic> commentaireRaw,
  }) {
    return _commentaireStatutIdFromRaw(commentaireRaw) ??
        _commentaireStatutIdFromRaw(body) ??
        (statutRaw == null ? null : _statutIdFromRaw(statutRaw)) ??
        fallbackId;
  }

  int? _commentaireStatutIdFromRaw(Map<String, dynamic> raw) {
    return _parseInt(
      _firstValue(raw, const [
        'statut',
        'status',
        'statut_id',
        'status_id',
        'statut_prestataire',
        'statut_prestataire_id',
      ]),
    );
  }

  bool _shouldKeepSocket(String key, int fallbackId) {
    if (key == 'global') return _globalWatchers > 0;
    if (key == 'user') return _userWatchers > 0;
    return fallbackId > 0 && (_statutWatchers[fallbackId] ?? 0) > 0;
  }

  String _statutKey(int statutId) => 'statut:$statutId';

  Map<String, dynamic>? _decodePayload(dynamic event) {
    final decoded = switch (event) {
      String() => jsonDecode(event),
      List<int>() => jsonDecode(utf8.decode(event)),
      Map<String, dynamic>() => event,
      _ => null,
    };
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  bool _looksLikeCommentaire(Map<String, dynamic> raw) {
    return _firstValue(raw, const [
              'contenu',
              'content',
              'texte',
              'text',
              'commentaire',
              'comment',
            ]) !=
            null &&
        _firstValue(raw, const [
              'statut',
              'status',
              'statut_id',
              'status_id',
              'statut_prestataire',
            ]) !=
            null;
  }

  StatutCommentaire _commentaireFromRaw(
    int fallbackId,
    Map<String, dynamic> raw,
  ) {
    return StatutCommentaire.fromJson({
      ...raw,
      'statut':
          _parseInt(
            _firstValue(raw, const [
              'statut',
              'status',
              'statut_id',
              'status_id',
              'statut_prestataire',
            ]),
          ) ??
          fallbackId,
      'contenu':
          _firstValue(raw, const [
            'contenu',
            'content',
            'texte',
            'text',
            'commentaire',
            'comment',
          ])?.toString() ??
          '',
    });
  }
}

class _StatutRealtimeSocket {
  _StatutRealtimeSocket({
    required this.key,
    required this.uri,
    required this.fallbackId,
    required this.onEvent,
    required this.shouldReconnect,
  });

  final String key;
  final Uri uri;
  final int fallbackId;
  final void Function(int fallbackId, dynamic event) onEvent;
  final bool Function() shouldReconnect;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  bool _disposed = false;
  int _attempt = 0;

  void connect() {
    if (_disposed || !shouldReconnect()) return;
    try {
      if (kDebugMode) {
        debugPrint('[StatutRealtime] connecting key=$key uri=$uri');
      }
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      unawaited(
        channel.ready
            .then((_) {
              _attempt = 0;
              if (kDebugMode) {
                debugPrint('[StatutRealtime] connected key=$key uri=$uri');
              }
            })
            .catchError((Object error) {
              if (kDebugMode) {
                debugPrint(
                  '[StatutRealtime] ready failed key=$key uri=$uri error=$error',
                );
              }
              _scheduleReconnect();
            }),
      );
      _subscription = channel.stream.listen(
        (event) {
          if (kDebugMode) {
            debugPrint('[StatutRealtime] received key=$key event=$event');
          }
          onEvent(fallbackId, event);
        },
        onError: (Object error) {
          if (kDebugMode) {
            debugPrint(
              '[StatutRealtime] stream error key=$key uri=$uri error=$error',
            );
          }
          _scheduleReconnect();
        },
        onDone: () {
          if (kDebugMode) {
            debugPrint('[StatutRealtime] closed key=$key uri=$uri');
          }
          _scheduleReconnect();
        },
      );
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[StatutRealtime] connect failed key=$key uri=$uri error=$error',
        );
      }
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_disposed || !shouldReconnect() || _reconnectTimer != null) return;
    unawaited(_subscription?.cancel());
    _subscription = null;
    unawaited(_channel?.sink.close());
    _channel = null;

    final seconds = _attempt < 4 ? 1 << _attempt : 16;
    _attempt++;
    if (kDebugMode) {
      debugPrint('[StatutRealtime] reconnect key=$key uri=$uri in ${seconds}s');
    }
    _reconnectTimer = Timer(Duration(seconds: seconds), () {
      _reconnectTimer = null;
      connect();
    });
  }

  void dispose() {
    if (kDebugMode) {
      debugPrint('[StatutRealtime] dispose key=$key uri=$uri');
    }
    _disposed = true;
    _reconnectTimer?.cancel();
    unawaited(_subscription?.cancel());
    unawaited(_channel?.sink.close());
    _subscription = null;
    _channel = null;
  }
}

int _compareCommentairesRecents(StatutCommentaire a, StatutCommentaire b) {
  final dateA = a.dateCreation;
  final dateB = b.dateCreation;
  if (dateA != null && dateB != null) return dateB.compareTo(dateA);
  if (dateA != null) return -1;
  if (dateB != null) return 1;
  return b.id.compareTo(a.id);
}
