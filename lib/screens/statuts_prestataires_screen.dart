import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_player/video_player.dart';

import '../core/constants/api_constants.dart';
import '../core/models/prestataire_models.dart';
import '../core/models/statut_prestataire_models.dart';
import '../core/services/app_refresh_service.dart';
import '../core/services/auth_service.dart';
import '../core/services/prestataire_service.dart';
import '../core/services/statut_prestataire_service.dart';
import '../core/services/statut_realtime_service.dart';
import '../core/services/statut_unread_service.dart';
import '../core/services/statut_upload_service.dart';
import '../theme/app_colors.dart';
import '../widgets/gradient_background.dart';
import 'prestataire_detail_screen.dart';

Future<void> _openPrestataireProfile(
  BuildContext context,
  StatutPrestataire statut,
) async {
  try {
    final prestataire = await PrestataireService.instance.getPrestataire(
      statut.prestataire,
    );
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PrestataireDetailScreen(prestataire: prestataire),
      ),
    );
  } catch (e) {
    debugPrint('[Statuts] open profile error: $e');
  }
}

int _maxActiveStatutsForLevel(String niveau) {
  return niveau.trim().toLowerCase() == 'expert' ? 2 : 1;
}

List<StatutCommentaire> _sortCommentairesRecents(
  List<StatutCommentaire> commentaires,
) {
  return List<StatutCommentaire>.from(commentaires)
    ..sort(_compareCommentairesRecents);
}

int _compareCommentairesRecents(StatutCommentaire a, StatutCommentaire b) {
  final dateA = a.dateCreation;
  final dateB = b.dateCreation;
  if (dateA != null && dateB != null) return dateB.compareTo(dateA);
  if (dateA != null) return -1;
  if (dateB != null) return 1;
  return b.id.compareTo(a.id);
}

StatutPrestataire _optimisticLikeToggle(StatutPrestataire statut) {
  final nextLiked = !statut.aimeParMoi;
  final delta = nextLiked ? 1 : -1;
  return statut.copyWith(
    aimeParMoi: nextLiked,
    nombreLikes: (statut.nombreLikes + delta).clamp(0, 1 << 31).toInt(),
  );
}

int _compareStatutsPriority(StatutPrestataire a, StatutPrestataire b) {
  if (a.vuParMoi != b.vuParMoi) return a.vuParMoi ? 1 : -1;
  final dateA = a.dateCreation;
  final dateB = b.dateCreation;
  if (dateA != null && dateB != null) return dateB.compareTo(dateA);
  if (dateA != null) return -1;
  if (dateB != null) return 1;
  return b.id.compareTo(a.id);
}

void _sortStatutsPriority(List<StatutPrestataire> statuts) {
  statuts.sort(_compareStatutsPriority);
}

class StatutsPrestatairesScreen extends StatefulWidget {
  StatutsPrestatairesScreen({super.key});

  @override
  State<StatutsPrestatairesScreen> createState() =>
      _StatutsPrestatairesScreenState();
}

class _StatutsPrestatairesScreenState extends State<StatutsPrestatairesScreen> {
  final _scrollCtrl = ScrollController();
  final List<StatutPrestataire> _statuts = [];
  final List<StatutPrestataire> _mesStatuts = [];
  bool _uploadDoneHandled = false;
  String _monNiveau = '';
  Timer? _timer;
  Timer? _externalLoadDebounce;
  int _lastRefreshTick = 0;
  bool _loading = true;
  bool _loadingMonStatut = false;
  bool _loadingMore = false;
  bool _hasNext = false;
  int _page = 1;
  String? _error;
  final Set<int> _likeBusyIds = {};
  final Set<int> _watchedRealtimeStatutIds = {};

  int get _maxMesStatuts => _maxActiveStatutsForLevel(_monNiveau);
  bool get _canPublishMine => _mesStatuts.length < _maxMesStatuts;
  StatutPrestataire? get _monStatutPreview =>
      _mesStatuts.isEmpty ? null : _mesStatuts.first;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    StatutPrestataireService.instance.changes.addListener(_onExternalChangeDebounced);
    StatutRealtimeService.instance.changes.addListener(_onRealtimeChange);
    StatutRealtimeService.instance.watchGlobal();
    StatutRealtimeService.instance.watchUser();
    // Force a lightweight sync of unread statuts so avatar badges are accurate on open.
    unawaited(StatutUnreadService.instance.syncUnreadCount());
    AppRefreshService.instance.tick.addListener(_onAppRefresh);
    // Écoute l'upload en arrière-plan pour recharger quand il est terminé.
    StatutUploadService.instance.status.addListener(_onUploadStatusChanged);
    _load(refresh: true);
    _timer = Timer.periodic(Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scrollCtrl.dispose();
    StatutPrestataireService.instance.changes.removeListener(_onExternalChangeDebounced);
    StatutRealtimeService.instance.changes.removeListener(_onRealtimeChange);
    StatutUploadService.instance.status.removeListener(_onUploadStatusChanged);
    _externalLoadDebounce?.cancel();
    StatutRealtimeService.instance.unwatchGlobal();
    StatutRealtimeService.instance.unwatchUser();
    _unwatchVisibleStatuts();
    AppRefreshService.instance.tick.removeListener(_onAppRefresh);
    super.dispose();
  }

  void _onUploadStatusChanged() {
    if (!mounted) return;
    final status = StatutUploadService.instance.status.value;
    if (status == StatutUploadStatus.done && !_uploadDoneHandled) {
      _uploadDoneHandled = true;
      // Recharge automatiquement quand l'upload est terminé.
      _load(refresh: true);
      // Réinitialise après un court délai pour permettre les futurs uploads.
      Future.delayed(const Duration(seconds: 2), () {
        _uploadDoneHandled = false;
      });
    } else if (status == StatutUploadStatus.preparing ||
        status == StatutUploadStatus.uploading) {
      // Rebuild pour afficher la progression sur le cercle "Mon statut".
      setState(() {});
    } else if (status == StatutUploadStatus.failed) {
      setState(() {});
    }
  }

  void _onExternalChangeDebounced() {
    _externalLoadDebounce?.cancel();
    _externalLoadDebounce = Timer(Duration(milliseconds: 700), () {
      if (!mounted) return;
      _load(refresh: true);
    });
  }

  void _onRealtimeChange() {
    if (!mounted) return;
    setState(() {
      final updates = StatutRealtimeService.instance;
      for (var i = 0; i < _statuts.length; i++) {
        _statuts[i] = updates.applyTo(_statuts[i]);
      }
      for (var i = 0; i < _mesStatuts.length; i++) {
        _mesStatuts[i] = updates.applyTo(_mesStatuts[i]);
      }
      _sortStatutsPriority(_statuts);
    });
    StatutUnreadService.instance.registerStatuts(_statuts);
  }

  void _onAppRefresh() {
    final refresh = AppRefreshService.instance;
    if (_lastRefreshTick == refresh.tick.value) return;
    _lastRefreshTick = refresh.tick.value;
    if (refresh.hasAny({AppRefreshTopic.auth, AppRefreshTopic.statuts})) {
      _load(refresh: true);
    }
  }

  void _tick() {
    if (!mounted) return;
    final before = _statuts.length;
    final beforeMine = _mesStatuts.length;
    setState(() {
      _statuts.removeWhere((s) => s.isExpiredNow);
      _mesStatuts.removeWhere((s) => s.isExpiredNow);
    });
    if (before != _statuts.length || beforeMine != _mesStatuts.length) {
      // Les statuts expirés sont déjà retirés localement : pas besoin de
      // re-fetch réseau complet (évite le flash de chargement).
      StatutUnreadService.instance.registerStatuts(_statuts);
    }
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 260) {
      _loadMore();
    }
  }

  Future<void> _load({required bool refresh}) async {
    if (refresh) {
      setState(() {
        _loading = true;
        _error = null;
        _page = 1;
      });
    }
    try {
      final response = await StatutPrestataireService.instance.getStatuts(
        page: refresh ? 1 : _page,
      );
      if (refresh) await _loadMonStatut(showLoader: false);
      if (!mounted) return;
      setState(() {
        if (refresh) {
          _statuts
            ..clear()
            ..addAll(response.results.where((s) => !s.isExpiredNow));
        } else {
          _statuts.addAll(response.results.where((s) => !s.isExpiredNow));
        }
        _sortStatutsPriority(_statuts);
        _page = response.currentPage;
        _hasNext = response.hasNext;
        _loading = false;
        _loadingMore = false;
      });
      StatutRealtimeService.instance.registerStatuts(_statuts);
      StatutUnreadService.instance.registerStatuts(_statuts);
      _syncVisibleStatutSockets();
      _onRealtimeChange();
      _precacheNextImages();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Impossible de charger les statuts.';
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasNext) return;
    setState(() => _loadingMore = true);
    _page += 1;
    await _load(refresh: false);
  }

  void _syncVisibleStatutSockets() {
    final nextIds = <int>{
      ..._statuts.map((statut) => statut.id).where((id) => id > 0),
      ..._mesStatuts.map((statut) => statut.id).where((id) => id > 0),
    };
    for (final id in _watchedRealtimeStatutIds.difference(nextIds)) {
      StatutRealtimeService.instance.unwatchStatut(id);
    }
    for (final id in nextIds.difference(_watchedRealtimeStatutIds)) {
      StatutRealtimeService.instance.watchStatut(id);
    }
    _watchedRealtimeStatutIds
      ..clear()
      ..addAll(nextIds);
  }

  void _unwatchVisibleStatuts() {
    for (final id in _watchedRealtimeStatutIds) {
      StatutRealtimeService.instance.unwatchStatut(id);
    }
    _watchedRealtimeStatutIds.clear();
  }

  Future<void> _loadMonStatut({bool showLoader = true}) async {
    if (!AuthService.instance.isLoggedIn) return;
    if (showLoader && mounted) setState(() => _loadingMonStatut = true);
    try {
      final isProvider =
          AuthService.instance.currentUser?.estPrestataire == true;
      final statuts =
          await StatutPrestataireService.instance.getMonStatut();
      String niveau = '';
      if (isProvider) {
        try {
          final profil = await PrestataireService.instance.getMonProfil();
          niveau = profil.niveau;
        } catch (_) {
          // Le profil prestataire peut échouer ; on garde un niveau vide.
        }
      }
      if (!mounted) return;
      setState(() {
        _mesStatuts
          ..clear()
          ..addAll(statuts.where((s) => !s.isExpiredNow));
        _monNiveau = niveau;
        _loadingMonStatut = false;
        // Fusionner mes statuts dans la liste globale (sans doublon).
        for (final mine in _mesStatuts) {
          final existingIndex = _statuts.indexWhere((s) => s.id == mine.id);
          if (existingIndex >= 0) {
            _statuts[existingIndex] = mine;
          } else {
            _statuts.add(mine);
          }
        }
        _sortStatutsPriority(_statuts);
      });
      StatutRealtimeService.instance.registerStatuts(_mesStatuts);
      _syncVisibleStatutSockets();
    } catch (_) {
      if (mounted) setState(() => _loadingMonStatut = false);
    }
  }

  void _precacheNextImages() {
    for (final statut in _statuts.take(5)) {
      if (!statut.isVideo && statut.mediaUrl.isNotEmpty) {
        precacheImage(NetworkImage(statut.mediaUrl), context);
      }
    }
  }

  Future<void> _openViewer(int index) async {
    if (_statuts.isEmpty) return;
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        pageBuilder: (_, animation, __) => FadeTransition(
          opacity: animation,
          child: StatutViewerScreen(
            statuts: List.of(_statuts),
            initialIndex: index,
          ),
        ),
      ),
    );
  }

  Future<void> _openViewerMine(int index) async {
    if (_mesStatuts.isEmpty) return;
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        pageBuilder: (_, animation, __) => FadeTransition(
          opacity: animation,
          child: StatutViewerScreen(
            statuts: List.of(_mesStatuts),
            initialIndex: index,
          ),
        ),
      ),
    );
  }

  Future<void> _toggleLikeFromList(StatutPrestataire statut) async {
    if (_likeBusyIds.contains(statut.id)) return;
    if (!AuthService.instance.isLoggedIn) {
      return;
    }

    final optimistic = _optimisticLikeToggle(statut);
    _likeBusyIds.add(statut.id);
    _applyStatutUpdate(optimistic);
    StatutRealtimeService.instance.applyHttpUpdate(optimistic);
    try {
      final update = await StatutPrestataireService.instance.toggleLike(
        statut.id,
      );
      if (!mounted) return;
      StatutRealtimeService.instance.applyHttpUpdate(update);
    } catch (e) {
      if (!mounted) return;
      _applyStatutUpdate(statut);
      StatutRealtimeService.instance.applyHttpUpdate(statut);
      debugPrint('[Statuts] like from list error: $e');
    } finally {
      _likeBusyIds.remove(statut.id);
    }
  }

  Future<void> _openCommentsFromList(StatutPrestataire statut) async {
    final update = await showModalBottomSheet<StatutPrestataire>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _StatutCommentsSheet(statut: statut),
    );
    if (update == null || !mounted) return;
    StatutRealtimeService.instance.applyHttpUpdate(update);
  }

  void _applyStatutUpdate(StatutPrestataire update) {
    setState(() {
      final index = _statuts.indexWhere((s) => s.id == update.id);
      if (index >= 0) {
        _statuts[index] = StatutRealtimeService.instance.applyTo(update);
        _sortStatutsPriority(_statuts);
      }
      final mineIndex = _mesStatuts.indexWhere((s) => s.id == update.id);
      if (mineIndex >= 0) {
        _mesStatuts[mineIndex] = StatutRealtimeService.instance.applyTo(update);
      }
    });
    StatutUnreadService.instance.registerStatuts(_statuts);
  }

  void _openMine() {
    if (_loadingMonStatut) return;
    if (_mesStatuts.isEmpty) {
      _showPublishSheet();
      return;
    }
    _showManageMineSheet();
  }

  void _showPublishSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PublishStatutSheet(
        onPublished: () {
          _load(refresh: true);
        },
      ),
    );
  }

  void _showManageMineSheet() {
    if (_mesStatuts.isEmpty) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ManageStatutSheet(
        statuts: List.of(_mesStatuts),
        maxStatuts: _maxMesStatuts,
        canPublish: _canPublishMine,
        onAdd: () {
          Navigator.pop(context);
          _showPublishSheet();
        },
        onView: (statut) {
          Navigator.pop(context);
          final index = _mesStatuts.indexWhere((s) => s.id == statut.id);
          if (index >= 0) _openViewerMine(index);
        },
        onDelete: (statut) async {
          Navigator.pop(context);
          await StatutPrestataireService.instance.supprimerStatut(statut.id);
          if (!mounted) return;
          setState(() {
            _mesStatuts.removeWhere((s) => s.id == statut.id);
            _statuts.removeWhere((s) => s.id == statut.id);
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GradientBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _Header(
                onBack: () => Navigator.maybePop(context),
                onRefresh: () => _load(refresh: true),
              ),
              Expanded(
                child: RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: () => _load(refresh: true),
                  child: _buildBody(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    final isLoggedIn = AuthService.instance.isLoggedIn;
    if (_error != null && _statuts.isEmpty) {
      return _StatusStateList(
        icon: Icons.error_outline_rounded,
        title: _error!,
        subtitle: 'Réessayez dans un instant.',
        color: AppColors.error,
        leading: isLoggedIn
            ? _MyStatusCircle(
                statut: _monStatutPreview,
                count: _mesStatuts.length,
                maxCount: _maxMesStatuts,
                loading: _loadingMonStatut,
                onTap: _openMine,
              )
            : null,
      );
    }
    return Column(
      children: [
        // Rangée horizontale des avatars (stories) en haut, compacte pour
        // laisser le maximum d'espace au feed vertical des statuts.
        SizedBox(
          height: 104,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: BouncingScrollPhysics(),
            padding: EdgeInsets.symmetric(horizontal: 20),
            itemCount: _statuts.length + (isLoggedIn ? 1 : 0),
            separatorBuilder: (_, __) => SizedBox(width: 12),
            itemBuilder: (_, index) {
              if (isLoggedIn && index == 0) {
                return _MyStatusCircle(
                  statut: _monStatutPreview,
                  count: _mesStatuts.length,
                  maxCount: _maxMesStatuts,
                  loading: _loadingMonStatut,
                  onTap: _openMine,
                );
              }
              final statutIndex = isLoggedIn ? index - 1 : index;
              return StatutStoryAvatar(
                statut: _statuts[statutIndex],
                likeBusy: _likeBusyIds.contains(_statuts[statutIndex].id),
                onTap: () => _openViewer(statutIndex),
                onLike: () => _toggleLikeFromList(_statuts[statutIndex]),
                onComments: () => _openCommentsFromList(_statuts[statutIndex]),
              );
            },
          ),
        ),
        if (_statuts.isEmpty)
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(24, 40, 24, 0),
              child: _EmptyStatutsPanel(),
            ),
          )
        else
          Expanded(
            child: _VerticalStatutFeed(
              statuts: _statuts,
              likeBusyIds: _likeBusyIds,
              onLike: _toggleLikeFromList,
              onComments: _openCommentsFromList,
              onLoadMore: _loadMore,
              hasMore: _hasNext,
              loadingMore: _loadingMore,
            ),
          ),
      ],
    );
  }
}

/// Feed vertical type TikTok/Reels pour les statuts récents.
/// 1 écran = 1 statut, swipe vertical, autoplay vidéo, play/pause au clic,
/// barre de progression synchronisée.
class _VerticalStatutFeed extends StatefulWidget {
  const _VerticalStatutFeed({
    required this.statuts,
    required this.likeBusyIds,
    required this.onLike,
    required this.onComments,
    required this.onLoadMore,
    required this.hasMore,
    required this.loadingMore,
  });

  final List<StatutPrestataire> statuts;
  final Set<int> likeBusyIds;
  final ValueChanged<StatutPrestataire> onLike;
  final ValueChanged<StatutPrestataire> onComments;
  final VoidCallback onLoadMore;
  final bool hasMore;
  final bool loadingMore;

  @override
  State<_VerticalStatutFeed> createState() => _VerticalStatutFeedState();
}

class _VerticalStatutFeedState extends State<_VerticalStatutFeed> {
  final PageController _pageCtrl = PageController();
  int _currentIndex = 0;
  final Map<int, _VerticalStatutCardController> _cardControllers = {};

  @override
  void initState() {
    super.initState();
    _pageCtrl.addListener(_onPageScroll);
  }

  @override
  void dispose() {
    _pageCtrl.removeListener(_onPageScroll);
    _pageCtrl.dispose();
    for (final ctrl in _cardControllers.values) {
      ctrl.dispose();
    }
    _cardControllers.clear();
    super.dispose();
  }

  void _onPageScroll() {
    // Charge plus de statuts quand on approche de la fin.
    if (_pageCtrl.position.pixels >=
        _pageCtrl.position.maxScrollExtent - 200) {
      if (widget.hasMore && !widget.loadingMore) {
        widget.onLoadMore();
      }
    }
  }

  void _onPageChanged(int index) {
    setState(() => _currentIndex = index);
    // Pause toutes les vidéos sauf celle active.
    for (final entry in _cardControllers.entries) {
      if (entry.key != index) {
        entry.value.pause();
      }
    }
    // Démarre la vidéo active.
    _cardControllers[index]?.play();
  }

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: _pageCtrl,
      scrollDirection: Axis.vertical,
      physics: const PageScrollPhysics(),
      itemCount: widget.statuts.length,
      onPageChanged: _onPageChanged,
      itemBuilder: (context, index) {
        final statut = widget.statuts[index];
        return _VerticalStatutCard(
          statut: statut,
          isActive: index == _currentIndex,
          likeBusy: widget.likeBusyIds.contains(statut.id),
          onLike: () => widget.onLike(statut),
          onComments: () => widget.onComments(statut),
          onControllerCreated: (controller) {
            _cardControllers[index] = controller;
            if (index == _currentIndex) {
              controller.play();
            }
          },
          onControllerDisposed: (index) {
            _cardControllers.remove(index);
          },
        );
      },
    );
  }
}

/// Contrôleur partagé pour chaque carte vidéo du feed vertical.
class _VerticalStatutCardController {
  VideoPlayerController? _videoCtrl;
  bool _isPlaying = false;
  bool _isPausedByUser = false;

  void attach(VideoPlayerController ctrl) {
    _videoCtrl = ctrl;
  }

  void detach() {
    _videoCtrl = null;
  }

  Future<void> play() async {
    _isPausedByUser = false;
    final ctrl = _videoCtrl;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (!ctrl.value.isPlaying) {
      _isPlaying = true;
      await ctrl.play();
    }
  }

  Future<void> pause() async {
    final ctrl = _videoCtrl;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (ctrl.value.isPlaying) {
      _isPlaying = false;
      await ctrl.pause();
    }
  }

  Future<void> togglePlayPause() async {
    final ctrl = _videoCtrl;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (ctrl.value.isPlaying) {
      _isPausedByUser = true;
      _isPlaying = false;
      await ctrl.pause();
    } else {
      _isPausedByUser = false;
      _isPlaying = true;
      await ctrl.play();
    }
  }

  bool get isPlaying => _isPlaying;
  bool get isPausedByUser => _isPausedByUser;

  void dispose() {
    _videoCtrl?.dispose();
    _videoCtrl = null;
  }
}

/// Carte plein écran pour un statut dans le feed vertical.
class _VerticalStatutCard extends StatefulWidget {
  const _VerticalStatutCard({
    required this.statut,
    required this.isActive,
    required this.likeBusy,
    required this.onLike,
    required this.onComments,
    required this.onControllerCreated,
    required this.onControllerDisposed,
  });

  final StatutPrestataire statut;
  final bool isActive;
  final bool likeBusy;
  final VoidCallback onLike;
  final VoidCallback onComments;
  final ValueChanged<_VerticalStatutCardController> onControllerCreated;
  final ValueChanged<int> onControllerDisposed;

  @override
  State<_VerticalStatutCard> createState() => _VerticalStatutCardState();
}

class _VerticalStatutCardState extends State<_VerticalStatutCard> {
  VideoPlayerController? _videoCtrl;
  bool _videoReady = false;
  bool _videoFailed = false;
  bool _showPlayIcon = false;
  Timer? _playIconTimer;
  double _progress = 0;
  bool _legendeExpanded = false;
  final _VerticalStatutCardController _controller =
      _VerticalStatutCardController();

  @override
  void initState() {
    super.initState();
    widget.onControllerCreated(_controller);
    if (widget.statut.isVideo) {
      _initVideo();
    }
  }

  @override
  void didUpdateWidget(covariant _VerticalStatutCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      if (widget.isActive) {
        _controller.play();
      } else {
        _controller.pause();
      }
    }
  }

  @override
  void dispose() {
    _playIconTimer?.cancel();
    _videoCtrl?.removeListener(_onVideoUpdate);
    _videoCtrl?.dispose();
    _controller.dispose();
    widget.onControllerDisposed(widget.statut.id);
    super.dispose();
  }

  Future<void> _initVideo() async {
    final ctrl = VideoPlayerController.networkUrl(
      Uri.parse(widget.statut.mediaUrl),
    );
    _videoCtrl = ctrl;
    _controller.attach(ctrl);
    ctrl.addListener(_onVideoUpdate);
    try {
      await ctrl.initialize();
      if (!mounted || _videoCtrl != ctrl) return;
      setState(() => _videoReady = true);
      if (widget.isActive) {
        await _controller.play();
      }
    } catch (_) {
      if (!mounted || _videoCtrl != ctrl) return;
      setState(() => _videoFailed = true);
    }
  }

  void _onVideoUpdate() {
    final ctrl = _videoCtrl;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    final duration = ctrl.value.duration.inMilliseconds;
    final position = ctrl.value.position.inMilliseconds;
    if (duration > 0) {
      final newProgress = (position / duration).clamp(0.0, 1.0);
      if ((newProgress - _progress).abs() > 0.001) {
        setState(() => _progress = newProgress);
      }
    }
    // Boucle la vidéo quand elle est terminée.
    if (ctrl.value.isCompleted) {
      ctrl.seekTo(Duration.zero);
      if (widget.isActive && !_controller.isPausedByUser) {
        ctrl.play();
      }
    }
  }

  void _handleTap() {
    if (!widget.statut.isVideo || !_videoReady) return;
    _controller.togglePlayPause();
    setState(() {
      _showPlayIcon = _controller.isPausedByUser;
    });
    if (_showPlayIcon) {
      _playIconTimer?.cancel();
      _playIconTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _showPlayIcon = false);
      });
    }
  }

  void _seekTo(double value) {
    final ctrl = _videoCtrl;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    final target = Duration(
      milliseconds: (value * ctrl.value.duration.inMilliseconds).round(),
    );
    ctrl.seekTo(target);
    setState(() => _progress = value);
  }

  @override
  Widget build(BuildContext context) {
    final statut = widget.statut;
    final prestataire = statut.prestataireDetail;
    final user = prestataire?.utilisateur;
    final name = user?.displayName ?? 'Prestataire';
    final userPhoto = user?.photoProfil == null
        ? null
        : ApiConstants.resolveUrl(user!.photoProfil!);

    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Média (vidéo ou image) en plein écran.
          _buildMedia(),

          // Dégradé pour lisibilité.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.15),
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.55),
                ],
                stops: const [0.0, 0.4, 1.0],
              ),
            ),
          ),

          // Icône Play au centre quand en pause.
          if (_showPlayIcon)
            Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white54, width: 2),
                ),
                child: Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 44,
                ),
              ),
            ),

          // GestureDetector pour play/pause (sous les boutons d'action).
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _handleTap,
            ),
          ),

          // Boutons d'action verticaux à droite (style TikTok).
          Positioned(
            right: 12,
            bottom: 90,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Like
                _TikTokActionButton(
                  icon: statut.aimeParMoi
                      ? CupertinoIcons.heart_fill
                      : CupertinoIcons.heart,
                  color: statut.aimeParMoi ? AppColors.error : Colors.white,
                  label: _compactCount(statut.nombreLikes),
                  busy: widget.likeBusy,
                  onTap: widget.onLike,
                ),
                SizedBox(height: 24),
                // Commentaires
                _TikTokActionButton(
                  icon: CupertinoIcons.chat_bubble,
                  color: Colors.white,
                  label: _compactCount(statut.nombreCommentaires),
                  onTap: widget.onComments,
                ),
              ],
            ),
          ),

          // Informations en bas (à gauche).
          Positioned(
            left: 16,
            right: 76,
            bottom: 18,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: Colors.white24,
                      backgroundImage: userPhoto == null
                          ? null
                          : NetworkImage(userPhoto),
                      child: userPhoto == null
                          ? Text(
                              (name.isNotEmpty ? name[0] : '?').toUpperCase(),
                              style: TextStyle(color: Colors.white),
                            )
                          : null,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (prestataire != null)
                            Text(
                              '${prestataire.servicesLabel} · ${prestataire.commune}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (prestataire != null)
                      _WhiteProfileButton(
                        dark: true,
                        onTap: () => _openPrestataireProfile(context, statut),
                      ),
                  ],
                ),
                if (statut.legende != null && statut.legende!.isNotEmpty) ...[
                  SizedBox(height: 10),
                  _buildLegende(statut.legende!),
                ],
                SizedBox(height: 10),
                Row(
                  children: [
                    _Pill(
                      icon: statut.isVideo
                          ? Icons.videocam_rounded
                          : Icons.image_rounded,
                      text: statut.remainingLabel,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Barre de progression en bas.
          if (statut.isVideo && _videoReady)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: GestureDetector(
                onTapDown: (details) {
                  final width = MediaQuery.of(context).size.width;
                  final value = (details.localPosition.dx / width).clamp(0.0, 1.0);
                  _seekTo(value);
                },
                child: Container(
                  height: 4,
                  color: Colors.black26,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: _progress,
                      child: Container(
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMedia() {
    if (widget.statut.isVideo) {
      if (!_videoReady || _videoCtrl == null) {
        return Center(
          child: _videoFailed
              ? Icon(
                  Icons.videocam_off_outlined,
                  color: Colors.white54,
                  size: 48,
                )
              : CircularProgressIndicator(color: Colors.white),
        );
      }
      return Center(
        child: AspectRatio(
          aspectRatio: _videoCtrl!.value.aspectRatio,
          child: VideoPlayer(_videoCtrl!),
        ),
      );
    }
    return Image.network(
      widget.statut.mediaUrl,
      fit: BoxFit.cover,
      loadingBuilder: (_, child, progress) => progress == null
          ? child
          : Center(child: CircularProgressIndicator(color: Colors.white)),
      errorBuilder: (_, __, ___) => _MediaError(dark: true),
    );
  }

  /// Légende extensible : affiche 2 lignes par défaut, "plus" pour tout voir,
  /// "moins" pour replier.
  Widget _buildLegende(String legende) {
    final isLong = legende.length > 80;
    if (!isLong) {
      return Text(
        legende,
        style: TextStyle(
          color: Colors.white,
          fontSize: 14,
          height: 1.35,
          fontWeight: FontWeight.w600,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          legende,
          maxLines: _legendeExpanded ? null : 2,
          overflow: _legendeExpanded ? null : TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            height: 1.35,
            fontWeight: FontWeight.w600,
          ),
        ),
        GestureDetector(
          onTap: () => setState(() => _legendeExpanded = !_legendeExpanded),
          child: Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              _legendeExpanded ? 'moins' : 'plus',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Bouton d'action vertical style TikTok (icône + compteur).
class _TikTokActionButton extends StatelessWidget {
  const _TikTokActionButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
    this.busy = false,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.30),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24, width: 1),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              shadows: [
                Shadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class HomeStatutsStories extends StatefulWidget {
  HomeStatutsStories({super.key});

  @override
  State<HomeStatutsStories> createState() => _HomeStatutsStoriesState();
}

class _HomeStatutsStoriesState extends State<HomeStatutsStories> {
  final List<StatutPrestataire> _statuts = [];
  final Set<int> _likeBusyIds = {};
  Timer? _timer;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    StatutPrestataireService.instance.changes.addListener(_load);
    StatutRealtimeService.instance.changes.addListener(_onRealtimeChange);
    StatutRealtimeService.instance.watchGlobal();
    StatutRealtimeService.instance.watchUser();
    _load();
    _timer = Timer.periodic(Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    StatutPrestataireService.instance.changes.removeListener(_load);
    StatutRealtimeService.instance.changes.removeListener(_onRealtimeChange);
    StatutRealtimeService.instance.unwatchGlobal();
    StatutRealtimeService.instance.unwatchUser();
    super.dispose();
  }

  void _onRealtimeChange() {
    if (!mounted) return;
    setState(() {
      final updates = StatutRealtimeService.instance;
      for (var i = 0; i < _statuts.length; i++) {
        _statuts[i] = updates.applyTo(_statuts[i]);
      }
      _sortStatutsPriority(_statuts);
    });
    StatutUnreadService.instance.registerStatuts(_statuts);
  }

  void _tick() {
    if (!mounted || _statuts.isEmpty) return;
    final before = _statuts.length;
    setState(() => _statuts.removeWhere((s) => s.isExpiredNow));
    if (before != _statuts.length) {
      StatutUnreadService.instance.registerStatuts(_statuts);
    }
  }

  Future<void> _load() async {
    try {
      final response = await StatutPrestataireService.instance.getStatuts(
        pageSize: 12,
      );
      if (!mounted) return;
      setState(() {
        _statuts
          ..clear()
          ..addAll(response.results.where((s) => !s.isExpiredNow));
        _sortStatutsPriority(_statuts);
        _loading = false;
      });
      StatutRealtimeService.instance.registerStatuts(_statuts);
      StatutUnreadService.instance.registerStatuts(_statuts);
      _onRealtimeChange();
      for (final statut in _statuts.take(4)) {
        if (!statut.isVideo && statut.mediaUrl.isNotEmpty && mounted) {
          precacheImage(NetworkImage(statut.mediaUrl), context);
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openViewer(int index) async {
    await Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, animation, __) => FadeTransition(
          opacity: animation,
          child: StatutViewerScreen(
            statuts: List.of(_statuts),
            initialIndex: index,
          ),
        ),
      ),
    );
  }

  Future<void> _toggleLike(StatutPrestataire statut) async {
    if (_likeBusyIds.contains(statut.id)) return;
    if (!AuthService.instance.isLoggedIn) {
      return;
    }
    final optimistic = _optimisticLikeToggle(statut);
    _likeBusyIds.add(statut.id);
    _applyStatutUpdate(optimistic);
    StatutRealtimeService.instance.applyHttpUpdate(optimistic);
    try {
      final update = await StatutPrestataireService.instance.toggleLike(
        statut.id,
      );
      if (!mounted) return;
      StatutRealtimeService.instance.applyHttpUpdate(update);
    } catch (e) {
      if (!mounted) return;
      _applyStatutUpdate(statut);
      StatutRealtimeService.instance.applyHttpUpdate(statut);
      debugPrint('[Statuts] like error: $e');
    } finally {
      _likeBusyIds.remove(statut.id);
    }
  }

  Future<void> _openComments(StatutPrestataire statut) async {
    final update = await showModalBottomSheet<StatutPrestataire>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _StatutCommentsSheet(statut: statut),
    );
    if (update == null || !mounted) return;
    StatutRealtimeService.instance.applyHttpUpdate(update);
  }

  void _applyStatutUpdate(StatutPrestataire update) {
    setState(() {
      final index = _statuts.indexWhere((s) => s.id == update.id);
      if (index >= 0) {
        _statuts[index] = StatutRealtimeService.instance.applyTo(update);
        _sortStatutsPriority(_statuts);
      }
    });
    StatutUnreadService.instance.registerStatuts(_statuts);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return SizedBox(
        height: 106,
        child: Center(
          child: CircularProgressIndicator(
            color: AppColors.primary,
            strokeWidth: 2.2,
          ),
        ),
      );
    }
    if (_statuts.isEmpty) return SizedBox.shrink();

    return SizedBox(
      height: 146,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(20, 8, 20, 14),
        itemCount: _statuts.length,
        separatorBuilder: (_, __) => SizedBox(width: 12),
        itemBuilder: (_, index) => StatutStoryAvatar(
          statut: _statuts[index],
          likeBusy: _likeBusyIds.contains(_statuts[index].id),
          onTap: () => _openViewer(index),
          onLike: () => _toggleLike(_statuts[index]),
          onComments: () => _openComments(_statuts[index]),
        ),
      ),
    );
  }
}

class StatutStoryAvatar extends StatefulWidget {
  StatutStoryAvatar({
    super.key,
    required this.statut,
    required this.onTap,
    required this.onLike,
    required this.onComments,
    this.likeBusy = false,
  });
  final StatutPrestataire statut;
  final VoidCallback onTap;
  final VoidCallback onLike;
  final VoidCallback onComments;
  final bool likeBusy;

  @override
  State<StatutStoryAvatar> createState() => _StatutStoryAvatarState();
}

class _StatutStoryAvatarState extends State<StatutStoryAvatar> {
  @override
  void initState() {
    super.initState();
    StatutRealtimeService.instance.changes.addListener(_onRealtimeChange);
  }

  @override
  void dispose() {
    StatutRealtimeService.instance.changes.removeListener(_onRealtimeChange);
    super.dispose();
  }

  void _onRealtimeChange() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final statut = widget.statut;
    final prestataire = statut.prestataireDetail;
    final user = prestataire?.utilisateur;
    final name = user?.displayName ?? 'Prestataire';
    return SizedBox(
      width: 86,
      child: Column(
        children: [
          GestureDetector(
            onTap: widget.onTap,
            child: Container(
              padding: EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppColors.primaryGradient,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.24),
                    blurRadius: 12,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipOval(
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: _StoryMediaThumb(statut: statut),
                    ),
                  ),
                  // No unread badge here: home page shows the orange badge only.
                ],
              ),
            ),
          ),
          SizedBox(height: 6),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 5),
          // Mini actions removed to keep avatar UI minimal; actions remain in "Statuts récents".
          SizedBox.shrink(),
        ],
      ),
    );
  }
}

class _StoryMiniAction extends StatelessWidget {
  _StoryMiniAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: SizedBox(
        height: 24,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 15),
            SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoryMediaThumb extends StatelessWidget {
  _StoryMediaThumb({required this.statut});
  final StatutPrestataire statut;

  @override
  Widget build(BuildContext context) {
    if (statut.isVideo) {
      return _VideoPreviewThumb(url: statut.mediaUrl, iconSize: 28);
    }
    return Image.network(
      statut.mediaUrl,
      fit: BoxFit.cover,
      loadingBuilder: (_, child, progress) =>
          progress == null ? child : Container(color: AppColors.primarySurface),
      errorBuilder: (_, __, ___) => Container(
        color: AppColors.primarySurface,
        child: Icon(Icons.image_outlined, color: AppColors.primary),
      ),
    );
  }
}

class _MyStatusCircle extends StatefulWidget {
  _MyStatusCircle({
    required this.statut,
    required this.count,
    required this.maxCount,
    required this.loading,
    required this.onTap,
  });

  final StatutPrestataire? statut;
  final int count;
  final int maxCount;
  final bool loading;
  final VoidCallback onTap;

  @override
  State<_MyStatusCircle> createState() => _MyStatusCircleState();
}

class _MyStatusCircleState extends State<_MyStatusCircle> {
  @override
  void initState() {
    super.initState();
    StatutUploadService.instance.status.addListener(_onUploadChanged);
    StatutUploadService.instance.progress.addListener(_onUploadChanged);
    StatutUploadService.instance.error.addListener(_onUploadChanged);
  }

  @override
  void dispose() {
    StatutUploadService.instance.status.removeListener(_onUploadChanged);
    StatutUploadService.instance.progress.removeListener(_onUploadChanged);
    StatutUploadService.instance.error.removeListener(_onUploadChanged);
    super.dispose();
  }

  void _onUploadChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final hasStatus = widget.statut != null;
    final uploadStatus = StatutUploadService.instance.status.value;
    final uploadProgress = StatutUploadService.instance.progress.value;
    final uploadError = StatutUploadService.instance.error.value;
    final isUploading = uploadStatus == StatutUploadStatus.preparing ||
        uploadStatus == StatutUploadStatus.uploading;

    // Anneau de progression affiché pendant l'upload.
    Widget ring = Container(
      padding: EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: hasStatus ? AppColors.primaryGradient : null,
        color: hasStatus ? null : AppColors.primarySurface,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipOval(
            child: SizedBox(
              width: 56,
              height: 56,
              child: widget.loading
                  ? ColoredBox(
                      color: Colors.white,
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                          strokeWidth: 2,
                        ),
                      ),
                    )
                  : hasStatus
                  ? _StoryMediaThumb(statut: widget.statut!)
                  : ColoredBox(
                      color: Colors.white,
                      child: Icon(
                        Icons.auto_awesome_motion_outlined,
                        color: AppColors.primary,
                      ),
                    ),
            ),
          ),
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: hasStatus ? AppColors.error : AppColors.primary,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Icon(
                hasStatus ? Icons.more_horiz_rounded : Icons.add_rounded,
                color: Colors.white,
                size: 14,
              ),
            ),
          ),
        ],
      ),
    );

    if (isUploading) {
      // Cercle de progression autour de l'avatar pendant l'upload.
      ring = Padding(
        padding: const EdgeInsets.all(3),
        child: SizedBox(
          width: 62,
          height: 62,
          child: CircularProgressIndicator(
            value: uploadProgress.clamp(0.0, 1.0),
            strokeWidth: 3,
            strokeCap: StrokeCap.round,
            backgroundColor: AppColors.primarySurface,
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        ),
      );
    }

    final statusText = isUploading
        ? (uploadStatus == StatutUploadStatus.preparing
              ? 'Préparation…'
              : 'Publication…')
        : hasStatus
        ? 'Mon statut'
        : 'Ajouter';
    final subText = isUploading
        ? '${(uploadProgress * 100).round()}%'
        : uploadError != null
        ? 'Réessayer'
        : hasStatus
        ? (widget.maxCount > 1
              ? '${widget.statut!.remainingLabel} · ${widget.count}/${widget.maxCount}'
              : widget.statut!.remainingLabel)
        : 'Statut';

    return GestureDetector(
      onTap: uploadError != null ? () => StatutUploadService.instance.retry() : widget.onTap,
      child: SizedBox(
        width: 82,
        child: Column(
          children: [
            ring,
            const SizedBox(height: 6),
            Text(
              statusText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: uploadError != null ? AppColors.error : AppColors.textPrimary,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              subText,
              maxLines: 1,
              style: TextStyle(
                color: uploadError != null ? AppColors.error : AppColors.textHint,
                fontSize: 10.5,
                fontWeight: uploadError != null ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyStatutsPanel extends StatelessWidget {
  _EmptyStatutsPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.glassBorder, width: 1.2),
      ),
      child: Column(
        children: [
          Icon(
            Icons.auto_awesome_motion_outlined,
            color: AppColors.textHint,
            size: 42,
          ),
          SizedBox(height: 10),
          Text(
            'Aucun statut actif',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 5),
          Text(
            'Les statuts des utilisateurs apparaîtront ici dès qu’ils seront publiés.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class StatutListCard extends StatelessWidget {
  StatutListCard({
    super.key,
    required this.statut,
    required this.onTap,
    required this.onLike,
    required this.onComments,
    this.likeBusy = false,
  });
  final StatutPrestataire statut;
  final VoidCallback onTap;
  final VoidCallback onLike;
  final VoidCallback onComments;
  final bool likeBusy;

  @override
  Widget build(BuildContext context) {
    final prestataire = statut.prestataireDetail;
    final name = prestataire?.utilisateur.displayName ?? 'Prestataire';
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(0),
        boxShadow: [
          BoxShadow(
            color: AppColors.glassShadow,
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onTap,
            child: ClipRRect(
              borderRadius: BorderRadius.vertical(top: Radius.circular(0)),
              child: AspectRatio(
                aspectRatio: 16 / 10,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    statut.isVideo
                        ? _VideoPreviewThumb(
                            url: statut.mediaUrl,
                            iconSize: 58,
                            fit: BoxFit.cover,
                          )
                        : Image.network(
                            statut.mediaUrl,
                            fit: BoxFit.cover,
                            loadingBuilder: (_, child, progress) =>
                                progress == null
                                ? child
                                : Center(
                                    child: CircularProgressIndicator(
                                      color: AppColors.primary,
                                      strokeWidth: 2.2,
                                    ),
                                  ),
                            errorBuilder: (_, __, ___) => _MediaError(),
                          ),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: _Pill(
                        icon: statut.isVideo
                            ? Icons.videocam_rounded
                            : Icons.image_rounded,
                        text: statut.remainingLabel,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (prestataire != null) ...[
                  SizedBox(height: 4),
                  Text(
                    '${prestataire.servicesLabel} · ${prestataire.commune}',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                    ),
                  ),
                ],
                if (statut.legende != null && statut.legende!.isNotEmpty) ...[
                  SizedBox(height: 10),
                  Text(
                    statut.legende!,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13.5,
                      height: 1.35,
                    ),
                  ),
                ],
                SizedBox(height: 12),
                Row(
                  children: [
                    if (prestataire != null)
                      _WhiteProfileButton(
                        dark: false,
                        onTap: () => _openPrestataireProfile(context, statut),
                      ),
                    Spacer(),
                    _InlineStatutActions(
                      statut: statut,
                      likeBusy: likeBusy,
                      onLike: onLike,
                      onComments: onComments,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineStatutActions extends StatelessWidget {
  _InlineStatutActions({
    required this.statut,
    required this.likeBusy,
    required this.onLike,
    required this.onComments,
  });

  final StatutPrestataire statut;
  final bool likeBusy;
  final VoidCallback onLike;
  final VoidCallback onComments;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _AnimatedLikeButton(
          liked: statut.aimeParMoi,
          count: statut.nombreLikes,
          busy: likeBusy,
          onTap: onLike,
        ),
        SizedBox(width: 10),
        _InlineStatutAction(
          icon: CupertinoIcons.chat_bubble,
          label: _compactCount(statut.nombreCommentaires),
          color: AppColors.primary,
          onTap: onComments,
        ),
      ],
    );
  }
}

/// Bouton "like" animé façon Twitter/X : mise à l'échelle spectaculaire,
/// rebond élastique, halo lumineux, particules et pulsation douce.
class _AnimatedLikeButton extends StatefulWidget {
  const _AnimatedLikeButton({
    required this.liked,
    required this.count,
    required this.onTap,
    this.busy = false,
  });

  final bool liked;
  final int count;
  final VoidCallback onTap;
  final bool busy;

  @override
  State<_AnimatedLikeButton> createState() => _AnimatedLikeButtonState();
}

class _AnimatedLikeButtonState extends State<_AnimatedLikeButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _glow;
  late final Animation<double> _particles;
  late final Animation<double> _pulse;

  /// Particules générées au moment du like.
  final List<_LikeParticle> _activeParticles = [];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );

    // Phase 1 (0→30%) : le cœur grossit rapidement jusqu'à 1.45×
    // Phase 2 (30→100%) : rebond élastique qui revient à 1.0×
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.45)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.45, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 70,
      ),
    ]).animate(_controller);

    // Halo lumineux : apparaît pendant le scale-up puis s'estompe.
    _glow = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 65,
      ),
    ]).animate(_controller);

    // Particules : s'envolent pendant la première moitié de l'animation.
    _particles = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOutCubic),
    );

    // Pulsation douce et continue quand le cœur est aimé.
    _pulse = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void didUpdateWidget(covariant _AnimatedLikeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.liked != widget.liked) {
      if (widget.liked) {
        // Like → animation spectaculaire + haptique.
        HapticFeedback.lightImpact();
        _spawnParticles();
        _controller.forward(from: 0);
      } else {
        // Un-like → repli rapide + haptique légère.
        HapticFeedback.selectionClick();
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _spawnParticles() {
    _activeParticles
      ..clear()
      ..addAll(List.generate(6, (i) {
        final angle = (i * 60 + 15) * math.pi / 180;
        return _LikeParticle(
          dx: 26 * 0.6 * math.cos(angle),
          dy: -26 * 0.6 * math.sin(angle),
          size: 3.0 + (i % 3) * 1.2,
          delay: i * 25,
        );
      }));
  }

  void _handleTap() {
    if (widget.busy) return;
    // Déclenche l'animation immédiatement pour une réactivité instantanée.
    if (widget.liked) {
      HapticFeedback.lightImpact();
      _spawnParticles();
      _controller.forward(from: 0);
    } else {
      HapticFeedback.selectionClick();
    }
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.liked ? AppColors.error : AppColors.primary;
    return GestureDetector(
      onTap: _handleTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _controller,
              builder: (_, child) {
                // Pulsation douce quand aimé et animation terminée.
                final baseScale = widget.liked && !_controller.isAnimating
                    ? 1.0 + (_pulse.value - 1.0) * 0.5
                    : 1.0;
                final scale = _scale.value * baseScale;
                return Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    // Halo lumineux rouge pendant l'animation.
                    if (_glow.value > 0.01)
                      Container(
                        width: 22 + _glow.value * 16,
                        height: 22 + _glow.value * 16,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.error.withValues(
                            alpha: 0.28 * _glow.value,
                          ),
                        ),
                      ),
                    // Particules qui s'envolent.
                    if (_particles.value > 0.01 && _activeParticles.isNotEmpty)
                      ..._activeParticles.map(
                        (p) => Transform.translate(
                          offset: Offset(
                            p.dx * _particles.value,
                            p.dy * _particles.value,
                          ),
                          child: Opacity(
                            opacity: (1 - _particles.value).clamp(0.0, 1.0),
                            child: Container(
                              width: p.size,
                              height: p.size,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.error.withValues(
                                  alpha: 0.7 * (1 - _particles.value),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    // Cœur avec scale spectaculaire.
                    Transform.scale(
                      scale: scale,
                      child: child,
                    ),
                  ],
                );
              },
              child: Icon(
                widget.liked
                    ? CupertinoIcons.heart_fill
                    : CupertinoIcons.heart,
                color: color,
                size: 22,
                shadows: widget.liked
                    ? [
                        Shadow(
                          color: AppColors.error.withValues(alpha: 0.45),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              _compactCount(widget.count),
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Petite particule qui s'envole lors du like.
class _LikeParticle {
  const _LikeParticle({
    required this.dx,
    required this.dy,
    required this.size,
    required this.delay,
  });

  final double dx;
  final double dy;
  final double size;
  final int delay;
}

class _InlineStatutAction extends StatelessWidget {
  _InlineStatutAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class StatutViewerScreen extends StatefulWidget {
  StatutViewerScreen({
    super.key,
    required this.statuts,
    required this.initialIndex,
  });

  final List<StatutPrestataire> statuts;
  final int initialIndex;

  @override
  State<StatutViewerScreen> createState() => _StatutViewerScreenState();
}

class _StatutViewerScreenState extends State<StatutViewerScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progressCtrl;
  late final PageController _pageCtrl;
  late final List<StatutPrestataire> _statuts;
  final Set<int> _viewedThisSession = {};
  late int _index;
  VideoPlayerController? _videoCtrl;
  int? _watchedStatutId;
  bool _videoReady = false;
  final Set<int> _likeSyncingIds = {};

  StatutPrestataire get _current => _statuts[_index];

  @override
  void initState() {
    super.initState();
    _statuts = List<StatutPrestataire>.from(widget.statuts);
    _index = widget.initialIndex.clamp(0, _statuts.length - 1);
    _pageCtrl = PageController(initialPage: _index);
    _progressCtrl = AnimationController(vsync: this)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _next();
      });
    StatutRealtimeService.instance.registerStatuts(_statuts);
    StatutRealtimeService.instance.changes.addListener(_onRealtimeChange);
    StatutRealtimeService.instance.watchUser();
    _startCurrent();
  }

  @override
  void dispose() {
    _progressCtrl.dispose();
    _pageCtrl.dispose();
    _videoCtrl?.dispose();
    final watchedStatutId = _watchedStatutId;
    if (watchedStatutId != null) {
      StatutRealtimeService.instance.unwatchStatut(watchedStatutId);
    }
    StatutRealtimeService.instance.unwatchUser();
    StatutRealtimeService.instance.changes.removeListener(_onRealtimeChange);
    super.dispose();
  }

  void _onRealtimeChange() {
    if (!mounted) return;
    setState(() {
      final updates = StatutRealtimeService.instance;
      for (var i = 0; i < _statuts.length; i++) {
        _statuts[i] = updates.applyTo(_statuts[i]);
      }
    });
    StatutUnreadService.instance.registerStatuts(_statuts);
  }

  Future<void> _startCurrent() async {
    _markCurrentAsViewed();
    _connectInteractions();
    _progressCtrl.stop();
    _progressCtrl.reset();
    await _videoCtrl?.dispose();
    _videoCtrl = null;
    _videoReady = false;
    if (!mounted) return;
    setState(() {});

    if (_current.isVideo) {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(_current.mediaUrl),
      );
      _videoCtrl = controller;
      try {
        await controller.initialize();
        await controller.setVolume(0);
        await controller.play();
        if (!mounted) return;
        setState(() => _videoReady = true);
        _progressCtrl.duration = controller.value.duration;
        _progressCtrl.forward(from: 0);
        controller.addListener(() {
          if (controller.value.isCompleted) _next();
        });
      } catch (_) {
        if (mounted) _next();
      }
    } else {
      _progressCtrl.duration = Duration(seconds: 5);
      _progressCtrl.forward(from: 0);
    }
  }

  void _connectInteractions() {
    final statutId = _current.id;
    if (statutId <= 0) return;
    if (_watchedStatutId == statutId) return;
    final previous = _watchedStatutId;
    if (previous != null) {
      StatutRealtimeService.instance.unwatchStatut(previous);
    }
    _watchedStatutId = statutId;
    StatutRealtimeService.instance.watchStatut(statutId);
  }

  Future<void> _toggleLike() async {
    final statut = _current;
    if (_likeSyncingIds.contains(statut.id)) return;
    if (!AuthService.instance.isLoggedIn) {
      return;
    }
    final optimistic = _optimisticLikeToggle(statut);
    _likeSyncingIds.add(statut.id);
    setState(() {
      final currentIndex = _statuts.indexWhere((s) => s.id == statut.id);
      if (currentIndex >= 0) _statuts[currentIndex] = optimistic;
    });
    StatutRealtimeService.instance.applyHttpUpdate(optimistic);
    try {
      final update = await StatutPrestataireService.instance.toggleLike(
        statut.id,
      );
      StatutRealtimeService.instance.applyHttpUpdate(update);
      if (!mounted) return;
      setState(() {
        final currentIndex = _statuts.indexWhere((s) => s.id == update.id);
        if (currentIndex >= 0) {
          _statuts[currentIndex] =
              StatutRealtimeService.instance.applyTo(update);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        final currentIndex = _statuts.indexWhere((s) => s.id == statut.id);
        if (currentIndex >= 0) _statuts[currentIndex] = statut;
      });
      StatutRealtimeService.instance.applyHttpUpdate(statut);
      debugPrint('[StatutViewer] like error: $e');
    } finally {
      _likeSyncingIds.remove(statut.id);
    }
  }

  Future<void> _openComments() async {
    final update = await showModalBottomSheet<StatutPrestataire>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _StatutCommentsSheet(statut: _current),
    );
    if (update == null || !mounted) return;
    StatutRealtimeService.instance.applyHttpUpdate(update);
    setState(() {
      final currentIndex = _statuts.indexWhere((s) => s.id == update.id);
      if (currentIndex >= 0) {
        _statuts[currentIndex] =
            StatutRealtimeService.instance.applyTo(update);
      }
    });
  }

  void _next() {
    if (_index >= _statuts.length - 1) {
      Navigator.maybePop(context);
      return;
    }
    _pageCtrl.nextPage(
      duration: Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  void _previous() {
    if (_index <= 0) return;
    _pageCtrl.previousPage(
      duration: Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final prestataire = _current.prestataireDetail;
    final user = prestataire?.utilisateur;
    final userPhoto = user?.photoProfil == null
        ? null
        : ApiConstants.resolveUrl(user!.photoProfil!);
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: PageView.builder(
                controller: _pageCtrl,
                scrollDirection: Axis.horizontal,
                itemCount: _statuts.length,
                onPageChanged: (value) {
                  if (_index == value) return;
                  setState(() => _index = value);
                  _preloadAround(value);
                  _startCurrent();
                },
                itemBuilder: (_, pageIndex) {
                  if (pageIndex == _index) return _buildMedia();
                  return _ViewerPreview(statut: _statuts[pageIndex]);
                },
              ),
            ),
            Positioned.fill(
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _previous,
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _next,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              top: 10,
              child: Row(
                children: List.generate(
                  _statuts.length,
                  (i) => Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 2),
                      child: i == _index
                          ? AnimatedBuilder(
                              animation: _progressCtrl,
                              builder: (_, __) => LinearProgressIndicator(
                                value: _progressCtrl.value,
                                minHeight: 3,
                                backgroundColor: Colors.white30,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : LinearProgressIndicator(
                              value: i < _index ? 1 : 0,
                              minHeight: 3,
                              backgroundColor: Colors.white30,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              top: 28,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.white24,
                    backgroundImage: userPhoto == null
                        ? null
                        : NetworkImage(userPhoto),
                    child: userPhoto == null
                        ? Text(
                            (user?.displayName ?? '?')[0].toUpperCase(),
                            style: TextStyle(color: Colors.white),
                          )
                        : null,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.displayName ?? 'Prestataire',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          prestataire?.servicesLabel ?? _current.remainingLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        if (_current.nombreVues > 0)
                          Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.visibility_outlined,
                                  color: Colors.white70,
                                  size: 13,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  '${_current.nombreVues} vue${_current.nombreVues > 1 ? 's' : ''}',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.maybePop(context),
                    icon: Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
            if (_current.legende != null && _current.legende!.isNotEmpty)
              Positioned(
                left: 18,
                right: 18,
                bottom: 86,
                child: Text(
                  _current.legende!,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (prestataire != null)
              Positioned(
                left: 18,
                bottom: 28,
                child: _WhiteProfileButton(
                  dark: true,
                  onTap: () => _openPrestataireProfile(context, _current),
                ),
              ),
            // Interaction buttons removed from viewer for a minimal reading experience.
          ],
        ),
      ),
    );
  }

  Widget _buildMedia() {
    if (_current.isVideo) {
      if (!_videoReady || _videoCtrl == null) {
        return Center(child: CircularProgressIndicator(color: Colors.white));
      }
      return Center(
        child: AspectRatio(
          aspectRatio: _videoCtrl!.value.aspectRatio,
          child: VideoPlayer(_videoCtrl!),
        ),
      );
    }
    return Image.network(
      _current.mediaUrl,
      fit: BoxFit.contain,
      loadingBuilder: (_, child, progress) => progress == null
          ? child
          : Center(child: CircularProgressIndicator(color: Colors.white)),
      errorBuilder: (_, __, ___) => _MediaError(dark: true),
    );
  }

  void _preloadAround(int index) {
    for (final i in [index + 1, index + 2]) {
      if (i >= _statuts.length) continue;
      final statut = _statuts[i];
      if (!statut.isVideo && statut.mediaUrl.isNotEmpty) {
        precacheImage(NetworkImage(statut.mediaUrl), context);
      }
    }
  }

  Future<void> _markCurrentAsViewed() async {
    final statutId = _current.id;
    if (statutId <= 0 || _viewedThisSession.contains(statutId)) return;
    _viewedThisSession.add(statutId);
    final currentIndex = _statuts.indexWhere(
      (statut) => statut.id == statutId,
    );
    if (currentIndex >= 0 && !_statuts[currentIndex].vuParMoi) {
      final optimistic = _statuts[currentIndex].copyWith(
        vuParMoi: true,
        nombreVues: _statuts[currentIndex].nombreVues + 1,
      );
      setState(() => _statuts[currentIndex] = optimistic);
      StatutRealtimeService.instance.applyHttpUpdate(optimistic);
      StatutUnreadService.instance.markViewed(statutId);
    }
    try {
      final detail = await StatutPrestataireService.instance.getStatut(
        statutId,
      );
      if (!mounted) return;
      final detailIndex = _statuts.indexWhere(
        (statut) => statut.id == statutId,
      );
      if (detailIndex < 0) return;
      setState(() {
        _statuts[detailIndex] = _statuts[detailIndex].copyWith(
          nombreVues: detail.nombreVues,
          nombreLikes: detail.nombreLikes,
          nombreCommentaires: detail.nombreCommentaires,
          aimeParMoi: detail.aimeParMoi,
          vuParMoi: true,
          commentaires: detail.commentaires,
        );
      });
      StatutRealtimeService.instance.applyHttpUpdate(_statuts[detailIndex]);
    } catch (_) {
      // Le compteur de vue ne doit jamais bloquer l'affichage du statut.
    }
  }
}

class _ViewerPreview extends StatelessWidget {
  _ViewerPreview({required this.statut});
  final StatutPrestataire statut;

  @override
  Widget build(BuildContext context) {
    if (statut.isVideo) {
      return _VideoPreviewThumb(
        url: statut.mediaUrl,
        iconSize: 62,
        fit: BoxFit.contain,
      );
    }
    return Image.network(statut.mediaUrl, fit: BoxFit.contain);
  }
}

class _VideoPreviewThumb extends StatefulWidget {
  const _VideoPreviewThumb({
    required this.url,
    this.iconSize = 44,
    this.fit = BoxFit.cover,
  });

  final String url;
  final double iconSize;
  final BoxFit fit;

  @override
  State<_VideoPreviewThumb> createState() => _VideoPreviewThumbState();
}

class _VideoPreviewThumbState extends State<_VideoPreviewThumb> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(covariant _VideoPreviewThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _controller?.dispose();
      _controller = null;
      _ready = false;
      _failed = false;
      _init();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    if (widget.url.trim().isEmpty) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setVolume(0);
      await controller.pause();
      await controller.seekTo(Duration.zero);
      if (!mounted || _controller != controller) return;
      setState(() => _ready = true);
    } catch (_) {
      await controller.dispose();
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_ready && controller != null)
          _VideoFrame(controller: controller, fit: widget.fit)
        else
          DecoratedBox(
            decoration: BoxDecoration(
              color: _failed ? Colors.black : AppColors.primarySurface,
            ),
            child: Center(
              child: _failed
                  ? Icon(
                      Icons.videocam_off_outlined,
                      color: Colors.white54,
                      size: widget.iconSize * 0.75,
                    )
                  : SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                        strokeWidth: 2.2,
                      ),
                    ),
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.05),
                Colors.black.withValues(alpha: 0.28),
              ],
            ),
          ),
        ),
        Center(
          child: Icon(
            Icons.play_circle_fill_rounded,
            color: Colors.white.withValues(alpha: 0.92),
            size: widget.iconSize,
          ),
        ),
      ],
    );
  }
}

class _VideoFrame extends StatelessWidget {
  const _VideoFrame({required this.controller, required this.fit});

  final VideoPlayerController controller;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final size = controller.value.size;
    return FittedBox(
      fit: fit,
      child: SizedBox(
        width: size.width <= 0 ? 1 : size.width,
        height: size.height <= 0 ? 1 : size.height,
        child: VideoPlayer(controller),
      ),
    );
  }
}

class _StatutInteractionBar extends StatelessWidget {
  const _StatutInteractionBar({
    required this.statut,
    required this.likeBusy,
    required this.onLike,
    required this.onComments,
  });

  final StatutPrestataire statut;
  final bool likeBusy;
  final VoidCallback onLike;
  final VoidCallback onComments;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StatutActionButton(
          icon: statut.aimeParMoi
              ? CupertinoIcons.heart_fill
              : CupertinoIcons.heart,
          color: statut.aimeParMoi ? AppColors.error : Colors.white,
          label: _compactCount(statut.nombreLikes),
          busy: likeBusy,
          onTap: onLike,
        ),
        SizedBox(height: 18),
        _StatutActionButton(
          icon: CupertinoIcons.chat_bubble,
          label: _compactCount(statut.nombreCommentaires),
          onTap: onComments,
        ),
      ],
    );
  }
}

class _StatutActionButton extends StatelessWidget {
  const _StatutActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = Colors.white,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.28),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24, width: 1),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          SizedBox(height: 5),
          Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              shadows: [
                Shadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatutCommentsSheet extends StatefulWidget {
  const _StatutCommentsSheet({required this.statut});

  final StatutPrestataire statut;

  @override
  State<_StatutCommentsSheet> createState() => _StatutCommentsSheetState();
}

class _StatutCommentsSheetState extends State<_StatutCommentsSheet> {
  final _controller = TextEditingController();
  final List<StatutCommentaire> _commentaires = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;
  late StatutPrestataire _statut;

  @override
  void initState() {
    super.initState();
    _statut = widget.statut;
    _commentaires.addAll(_sortCommentairesRecents(widget.statut.commentaires));
    StatutRealtimeService.instance.registerStatuts([widget.statut]);
    StatutRealtimeService.instance.watchStatut(widget.statut.id);
    StatutRealtimeService.instance.watchUser();
    StatutRealtimeService.instance.changes.addListener(_onRealtimeChange);
    _load();
  }

  @override
  void dispose() {
    StatutRealtimeService.instance.unwatchStatut(widget.statut.id);
    StatutRealtimeService.instance.unwatchUser();
    StatutRealtimeService.instance.changes.removeListener(_onRealtimeChange);
    _controller.dispose();
    super.dispose();
  }

  void _onRealtimeChange() {
    if (!mounted) return;
    final realtime = StatutRealtimeService.instance;
    final nextStatut = realtime.applyTo(_statut);
    final nextCommentaires = realtime.commentairesFor(
      nextStatut.id,
      _commentaires,
    );
    setState(() {
      _statut = nextStatut;
      _commentaires
        ..clear()
        ..addAll(nextCommentaires);
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final commentaires = await StatutPrestataireService.instance
          .getCommentaires(widget.statut.id);
      if (!mounted) return;
      setState(() {
        _commentaires
          ..clear()
          ..addAll(_sortCommentairesRecents(commentaires));
        _loading = false;
      });
      StatutRealtimeService.instance.applyHttpUpdate(
        _statut.copyWith(commentaires: _commentaires),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Impossible de charger les commentaires.';
      });
    }
  }

  Future<void> _send() async {
    final contenu = _controller.text.trim();
    if (contenu.isEmpty || _sending) return;
    if (!AuthService.instance.isLoggedIn) {
      return;
    }
    setState(() => _sending = true);
    try {
      final result = await StatutPrestataireService.instance.ajouterCommentaire(
        widget.statut.id,
        contenu,
      );
      if (!mounted) return;
      _controller.clear();
      StatutRealtimeService.instance.applyHttpUpdate(result.statut);
      StatutRealtimeService.instance.applyCommentaire(
        result.commentaire,
        incrementCount: false,
      );
      setState(() {
        _insertCommentaire(result.commentaire);
        _statut = _statut.copyWith(
          nombreLikes: result.statut.nombreLikes,
          nombreCommentaires: result.statut.nombreCommentaires,
          aimeParMoi: result.statut.aimeParMoi,
        );
        _sending = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      debugPrint('[CommentairesStatut] send error: $e');
    }
  }

  void _insertCommentaire(StatutCommentaire commentaire) {
    final exists = _commentaires.any((item) => item.id == commentaire.id);
    if (!exists && commentaire.contenu.trim().isNotEmpty) {
      _commentaires.insert(0, commentaire);
      _sortCommentairesRecentsInPlace();
    }
  }

  void _sortCommentairesRecentsInPlace() {
    _commentaires.sort(_compareCommentairesRecents);
  }

  void _close() => Navigator.of(context).pop(_statut);

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return WillPopScope(
      onWillPop: () async {
        _close();
        return false;
      },
      child: ClipRRect(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            height: MediaQuery.of(context).size.height * 0.76,
            padding: EdgeInsets.only(bottom: bottom),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 26,
                  offset: Offset(0, -10),
                ),
              ],
            ),
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(14, 12, 10, 8),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${_statut.nombreCommentaires} commentaire${_statut.nombreCommentaires > 1 ? 's' : ''}',
                              style: TextStyle(
                                color: Color(0xFF161616),
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(width: 5),
                            Icon(
                              Icons.tune_rounded,
                              color: Color(0xFF161616),
                              size: 15,
                            ),
                          ],
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: GestureDetector(
                          onTap: _close,
                          child: Container(
                            width: 38,
                            height: 38,
                            color: Colors.transparent,
                            child: Icon(
                              Icons.close_rounded,
                              color: Color(0xFF151515),
                              size: 30,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(child: _buildContent()),
                Container(
                  padding: EdgeInsets.fromLTRB(14, 9, 14, 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: Color(0xFFECECEC))),
                  ),
                  child: Row(
                    children: [
                      _CurrentUserCommentAvatar(),
                      SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Color(0xFFF1F1F1),
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: TextField(
                            controller: _controller,
                            minLines: 1,
                            maxLines: 3,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _send(),
                            style: TextStyle(
                              color: Color(0xFF111111),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Ajouter un commentaire...',
                              hintStyle: TextStyle(
                                color: Color(0xFF9A9A9A),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 11,
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 10),
                      GestureDetector(
                        onTap: _sending ? null : _send,
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            gradient: _sending
                                ? LinearGradient(
                                    colors: [
                                      AppColors.textHint.withValues(
                                        alpha: 0.22,
                                      ),
                                      AppColors.textHint.withValues(
                                        alpha: 0.14,
                                      ),
                                    ],
                                  )
                                : AppColors.primaryGradient,
                            shape: BoxShape.circle,
                          ),
                          child: _sending
                              ? Center(
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              : Icon(Icons.send_rounded, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            color: AppColors.primary,
            strokeWidth: 2.4,
          ),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.18),
                  ),
                ),
                child: Icon(
                  Icons.chat_bubble_outline_rounded,
                  color: AppColors.error,
                  size: 28,
                ),
              ),
              SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 14),
              GestureDetector(
                onTap: _load,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.82),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Color(0xFFECECEC)),
                  ),
                  child: Text(
                    'Réessayer',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_commentaires.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.primarySurface,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.chat_bubble_outline_rounded,
                  color: AppColors.primary,
                  size: 30,
                ),
              ),
              SizedBox(height: 14),
              Text(
                'Aucun commentaire',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Soyez le premier à réagir à ce statut.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(14, 12, 14, 18),
      itemCount: _commentaires.length,
      separatorBuilder: (_, __) => SizedBox(height: 14),
      itemBuilder: (_, index) {
        final commentaire = _commentaires[index];
        final utilisateur = commentaire.utilisateur;
        final name = utilisateur?.displayName ?? 'Utilisateur';
        final photo = utilisateur?.photoProfil;
        final authorUserId = widget.statut.prestataireDetail?.utilisateur.id;
        final isAuthor =
            authorUserId != null && utilisateur?.id == authorUserId;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CommentAvatar(
              name: name,
              imageUrl: photo == null || photo.isEmpty
                  ? null
                  : ApiConstants.resolveUrl(photo),
              accented: isAuthor,
            ),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Color(0xFF777777),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (isAuthor) ...[
                        SizedBox(width: 7),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primarySurface,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Text(
                            'Auteur',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: 3),
                  Text(
                    commentaire.contenu,
                    style: TextStyle(
                      color: Color(0xFF111111),
                      fontSize: 15,
                      height: 1.28,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(height: 7),
                  Text(
                    _relativeCommentTime(commentaire.dateCreation),
                    style: TextStyle(
                      color: Color(0xFF9A9A9A),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CurrentUserCommentAvatar extends StatelessWidget {
  const _CurrentUserCommentAvatar();

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;
    final photo = user?.photo;
    final name = user?.displayName ?? 'U';
    return _RoundAvatar(
      name: name,
      imageUrl: photo == null || photo.isEmpty
          ? null
          : ApiConstants.resolveUrl(photo),
      size: 38,
      accented: false,
    );
  }
}

class _CommentAvatar extends StatelessWidget {
  const _CommentAvatar({
    required this.name,
    this.imageUrl,
    this.accented = false,
  });

  final String name;
  final String? imageUrl;
  final bool accented;

  @override
  Widget build(BuildContext context) {
    return _RoundAvatar(
      name: name,
      imageUrl: imageUrl,
      size: 42,
      accented: accented,
    );
  }
}

class _RoundAvatar extends StatelessWidget {
  const _RoundAvatar({
    required this.name,
    required this.size,
    required this.accented,
    this.imageUrl,
  });

  final String name;
  final double size;
  final bool accented;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? 'U' : name.trim()[0].toUpperCase();
    final avatar = ClipOval(
      child: Container(
        width: size,
        height: size,
        color: Color(0xFFF2F2F2),
        child: imageUrl == null
            ? Center(
                child: Text(
                  initial,
                  style: TextStyle(
                    color: accented ? AppColors.primary : Color(0xFF555555),
                    fontWeight: FontWeight.w800,
                    fontSize: size * 0.36,
                  ),
                ),
              )
            : Image.network(
                imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Center(
                  child: Text(
                    initial,
                    style: TextStyle(
                      color: Color(0xFF555555),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
      ),
    );

    if (!accented) return avatar;
    return Container(
      width: size + 6,
      height: size + 6,
      padding: EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.primaryLight, width: 2),
      ),
      child: avatar,
    );
  }
}

String _compactCount(int value) {
  if (value < 1000) return value.toString();
  if (value < 1000000) {
    final count = value / 1000;
    return '${count.toStringAsFixed(count >= 10 ? 0 : 1)}k';
  }
  final count = value / 1000000;
  return '${count.toStringAsFixed(count >= 10 ? 0 : 1)}M';
}

String _relativeCommentTime(DateTime? value) {
  if (value == null) return '';
  final diff = DateTime.now().difference(value.toLocal());
  if (diff.inMinutes < 1) return 'à l’instant';
  if (diff.inHours < 1) return '${diff.inMinutes} min';
  if (diff.inDays < 1) return '${diff.inHours} h';
  if (diff.inDays < 7) return '${diff.inDays} j';
  return '${(diff.inDays / 7).floor()} sem';
}

class _Header extends StatelessWidget {
  _Header({required this.onBack, required this.onRefresh});
  final VoidCallback onBack;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 14, 18, 10),
      child: Row(
        children: [
          _IconButton(icon: Icons.arrow_back_rounded, onTap: onBack),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Statuts',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          _IconButton(icon: Icons.refresh_rounded, onTap: onRefresh),
        ],
      ),
    );
  }
}

class _StatusStateList extends StatelessWidget {
  _StatusStateList({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.color,
    this.leading,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color color;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.all(24),
      children: [
        if (leading != null) ...[
          SizedBox(
            height: 118,
            child: Align(alignment: Alignment.centerLeft, child: leading),
          ),
          SizedBox(height: 40),
        ] else
          SizedBox(height: 120),
        Icon(icon, color: color, size: 46),
        SizedBox(height: 12),
        Center(
          child: Text(
            title,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
        ),
        if (subtitle != null) ...[
          SizedBox(height: 6),
          Center(
            child: Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ),
        ],
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  _Pill({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 13),
          SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _WhiteProfileButton extends StatelessWidget {
  _WhiteProfileButton({required this.onTap, required this.dark});

  final VoidCallback onTap;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.25 : 0.08),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.person_search_outlined,
              color: AppColors.primary,
              size: 15,
            ),
            SizedBox(width: 6),
            Text(
              'Voir profil',
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaError extends StatelessWidget {
  _MediaError({this.dark = false});
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: dark ? Colors.black : AppColors.primarySurface,
      child: Center(
        child: Icon(
          Icons.broken_image_outlined,
          color: dark ? Colors.white54 : AppColors.textHint,
        ),
      ),
    );
  }
}

class _ManageStatutSheet extends StatelessWidget {
  _ManageStatutSheet({
    required this.statuts,
    required this.maxStatuts,
    required this.canPublish,
    required this.onAdd,
    required this.onView,
    required this.onDelete,
  });

  final List<StatutPrestataire> statuts;
  final int maxStatuts;
  final bool canPublish;
  final VoidCallback onAdd;
  final ValueChanged<StatutPrestataire> onView;
  final ValueChanged<StatutPrestataire> onDelete;

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            maxStatuts > 1 ? 'Mes statuts actifs' : 'Mon statut actif',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '${statuts.length}/$maxStatuts statut${maxStatuts > 1 ? 's' : ''} actif${statuts.length > 1 ? 's' : ''}',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 16),
          ...statuts.map(
            (statut) => Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primarySurface.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 52,
                        height: 52,
                        child: _StoryMediaThumb(statut: statut),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            statut.legende?.isNotEmpty == true
                                ? statut.legende!
                                : (statut.isVideo ? 'Vidéo' : 'Photo'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            statut.remainingLabel,
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => onView(statut),
                      icon: Icon(
                        Icons.visibility_outlined,
                        color: AppColors.primary,
                      ),
                    ),
                    IconButton(
                      onPressed: () => onDelete(statut),
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        color: AppColors.error,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (canPublish) ...[
            SizedBox(height: 4),
            _SheetActionButton(
              label: 'Ajouter un statut',
              icon: Icons.add_rounded,
              onTap: onAdd,
            ),
          ] else ...[
            SizedBox(height: 4),
            Text(
              'Limite de publication atteinte pour aujourd’hui.',
              style: TextStyle(
                color: AppColors.textHint,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PublishStatutSheet extends StatefulWidget {
  _PublishStatutSheet({required this.onPublished});
  final VoidCallback onPublished;

  @override
  State<_PublishStatutSheet> createState() => _PublishStatutSheetState();
}

class _PublishStatutSheetState extends State<_PublishStatutSheet> {
  final _picker = ImagePicker();
  final _legendeCtrl = TextEditingController();
  XFile? _file;
  String _typeMedia = 'photo';
  int? _dureeVideo;
  bool _preparingVideo = false;
  bool _uploading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _pickMediaFromGallery();
    });
  }

  @override
  void dispose() {
    _legendeCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickMediaFromGallery() async {
    final picked = await _picker.pickMedia(imageQuality: 82, maxWidth: 1600);
    if (picked == null) return;
    final mediaType = await _mediaTypeFor(picked);
    if (mediaType == 'video') {
      await _setVideo(picked);
      return;
    }
    if (mediaType == 'photo') {
      setState(() {
        _file = picked;
        _typeMedia = 'photo';
        _dureeVideo = null;
        _error = null;
      });
      return;
    }
    setState(
      () => _error = 'Format non supporté. Choisissez une image ou une vidéo.',
    );
  }

  Future<void> _setVideo(XFile picked) async {
    final duration = await _readVideoDuration(picked);
    if (duration != null && duration.inSeconds > 30) {
      setState(() {
        _file = null;
        _error = 'La vidéo ne doit pas dépasser 30 secondes.';
      });
      return;
    }
    setState(() {
      _preparingVideo = true;
      _error = null;
    });
    final uploadFile = await _prepareVideoForUpload(picked);
    if (!mounted) return;
    if (uploadFile == null) {
      setState(() {
        _file = null;
        _preparingVideo = false;
        _error =
            'Impossible de préparer cette vidéo. Essayez une autre vidéo MP4.';
      });
      return;
    }
    setState(() {
      _file = uploadFile;
      _typeMedia = 'video';
      _dureeVideo = duration?.inSeconds.clamp(1, 30).toInt() ?? 30;
      _preparingVideo = false;
      _error = null;
    });
  }

  Future<XFile?> _prepareVideoForUpload(XFile picked) async {
    if (kIsWeb || !Platform.isIOS || _isMp4Video(picked)) return picked;
    try {
      final compressed = await VideoCompress.compressVideo(
        picked.path,
        quality: VideoQuality.MediumQuality,
        deleteOrigin: false,
        includeAudio: true,
      );
      final path = compressed?.path;
      if (path == null || path.isEmpty) return null;
      return XFile(path, mimeType: 'video/mp4');
    } catch (e) {
      debugPrint('[Statuts] video mp4 preparation error: $e');
      return null;
    }
  }

  bool _isMp4Video(XFile file) {
    final mimeType = file.mimeType?.toLowerCase();
    if (mimeType == 'video/mp4') return true;
    final name = file.name.toLowerCase();
    final path = file.path.toLowerCase();
    return name.endsWith('.mp4') || path.endsWith('.mp4');
  }

  Future<String?> _mediaTypeFor(XFile file) async {
    final mimeType =
        file.mimeType ?? lookupMimeType(file.name) ?? lookupMimeType(file.path);
    if (mimeType == null) return null;
    if (mimeType.startsWith('image/')) return 'photo';
    if (mimeType.startsWith('video/')) return 'video';
    return null;
  }

  Future<Duration?> _readVideoDuration(XFile file) async {
    VideoPlayerController? controller;
    try {
      controller = kIsWeb
          ? VideoPlayerController.networkUrl(Uri.parse(file.path))
          : VideoPlayerController.file(File(file.path));
      await controller.initialize();
      return controller.value.duration;
    } catch (_) {
      return null;
    } finally {
      await controller?.dispose();
    }
  }

  /// Démarre l'upload immédiatement en arrière-plan (façon WhatsApp),
  /// ferme le sheet et laisse l'utilisateur continuer à naviguer.
  Future<void> _publish() async {
    final file = _file;
    if (file == null || _uploading) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final path = file.path;
      if (path.isNotEmpty) {
        // Envoi en arrière-plan via le service dédié.
        await StatutUploadService.instance.startUpload(
          path: path,
          filename: file.name.isNotEmpty ? file.name : 'statut',
          typeMedia: _typeMedia,
          legende: _legendeCtrl.text,
          dureeVideo: _typeMedia == 'video' ? _dureeVideo : null,
        );
      } else {
        // Fallback pour bytes (web) : upload direct sans blocage du UI.
        await StatutUploadService.instance.startUpload(
          path: path,
          filename: file.name.isNotEmpty ? file.name : 'statut',
          typeMedia: _typeMedia,
          legende: _legendeCtrl.text,
          dureeVideo: _typeMedia == 'video' ? _dureeVideo : null,
        );
      }
      if (!mounted) return;
      // Ferme le sheet immédiatement : l'upload continue en arrière-plan.
      Navigator.pop(context);
      // Déclenche un rechargement via le callback (notifié quand done).
      widget.onPublished();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _cleanStatusError(e);
        _uploading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ajouter un statut',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Photo ou vidéo de 30 secondes maximum, visible pendant 24 heures.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.35,
            ),
          ),
          SizedBox(height: 16),
          _SheetActionButton(
            label: _file == null
                ? 'Choisir dans la galerie'
                : 'Changer le média',
            icon: Icons.photo_library_outlined,
            onTap: _uploading || _preparingVideo ? null : _pickMediaFromGallery,
          ),
          if (_file != null) ...[
            SizedBox(height: 14),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primarySurface.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    _typeMedia == 'video'
                        ? Icons.play_circle_outline_rounded
                        : Icons.image_outlined,
                    color: AppColors.primary,
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _typeMedia == 'video'
                          ? '${_file!.name} • ${_dureeVideo ?? 30}s'
                          : _file!.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          SizedBox(height: 14),
          TextField(
            controller: _legendeCtrl,
            minLines: 2,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Ajouter une légende...',
              filled: true,
              fillColor: AppColors.primarySurface.withValues(alpha: 0.36),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          if (_error != null) ...[
            SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(
                color: AppColors.error,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (_preparingVideo || _uploading) ...[
            SizedBox(height: 14),
            Text(
              _preparingVideo ? 'Préparation de la vidéo...' : 'Publication...',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 8),
            LinearProgressIndicator(color: AppColors.primary),
          ],
          SizedBox(height: 18),
          GestureDetector(
            onTap: _file == null || _uploading || _preparingVideo
                ? null
                : _publish,
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                gradient: _file == null || _uploading || _preparingVideo
                    ? LinearGradient(
                        colors: [
                          AppColors.textHint.withValues(alpha: 0.18),
                          AppColors.textHint.withValues(alpha: 0.1),
                        ],
                      )
                    : AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Text(
                  _uploading ? 'Publication...' : 'Publier',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetShell extends StatelessWidget {
  _SheetShell({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 18,
          right: 18,
          bottom: MediaQuery.of(context).viewInsets.bottom + 18,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              padding: EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.glassBorder, width: 1.2),
              ),
              child: SingleChildScrollView(child: child),
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetActionButton extends StatelessWidget {
  _SheetActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 17),
            SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _cleanStatusError(Object error) {
  final raw = error.toString().replaceFirst('Exception: ', '').trim();
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
  return raw.isEmpty ? 'Une erreur est survenue.' : raw;
}

class _IconButton extends StatelessWidget {
  _IconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Icon(icon, color: AppColors.primary, size: 20),
      ),
    );
  }
}
