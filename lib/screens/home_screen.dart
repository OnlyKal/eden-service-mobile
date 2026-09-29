import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../core/models/prestataire_models.dart';
import '../core/services/app_refresh_service.dart';
import '../core/services/conversation_unread_service.dart';
import '../core/services/favori_service.dart';
import '../core/services/notification_badge_service.dart';
import '../core/services/prestataire_service.dart';
import '../core/services/prestataire_realtime_service.dart';
import '../core/services/auth_service.dart';
import '../core/constants/api_constants.dart';
import '../core/constants/locations.dart';
import '../core/utils/user_friendly_error.dart';
import '../theme/app_colors.dart';
import '../widgets/certification_badge.dart';
import '../widgets/glass_card.dart';
import '../widgets/glass_button.dart';
import '../widgets/gradient_background.dart';
import 'login_screen.dart';
import 'notifications_screen.dart';
import 'profile_screen.dart';
import 'prestataire_detail_screen.dart';
import 'conversation_screen.dart';
import 'demandes_client_screen.dart';
import 'demandes_prestataire_screen.dart';
import 'favoris_screen.dart';
import 'statuts_prestataires_screen.dart';
import '../core/services/statut_unread_service.dart';

class HomeScreen extends StatefulWidget {
  HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  // ── Nav ──────────────────────────────────────────────────────────────────
  int _selectedNavIndex = 0;

  // ── Search ───────────────────────────────────────────────────────────────
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _debounce;
  Timer? _appRefreshDebounce;
  Timer? _availabilityRefreshDebounce;
  int _lastAppRefreshTick = 0;

  // ── Filters ───────────────────────────────────────────────────────────────
  String? _filterTypeService;
  int? _filterServiceId;
  String? _filterCommune;
  String? _filterVille;
  bool? _filterEstValide;
  bool? _filterDisponible;
  String? _filterOrdering;

  int get _activeExtraFilterCount {
    int n = 0;
    if (_filterCommune != null && _filterCommune!.isNotEmpty) n++;
    if (_filterVille != null && _filterVille!.isNotEmpty) n++;
    if ((_filterTypeService != null && _filterTypeService!.isNotEmpty) ||
        _filterServiceId != null) {
      n++;
    }
    if (_filterEstValide != null) n++;
    if (_filterDisponible != null) n++;
    if (_filterOrdering != null && _filterOrdering!.isNotEmpty) n++;
    return n;
  }

  // ── Categories ────────────────────────────────────────────────────────────
  int _selectedCategoryIndex = -1;
  final List<_Category> _categories = [];

  // ── Prestataires state ────────────────────────────────────────────────────
  final List<Prestataire> _prestataires = [];
  final Map<int, NotationsResponse> _ratingSummaries = {};
  final Set<int> _favoritePrestataireIds = {};
  bool _favoritesLoading = false;
  int? _favoriteBusyPrestataireId;
  bool _isLoadingInitial = true;
  bool _isLoadingMore = false;
  bool _hasNextPage = false;
  int _currentPage = 1;
  String? _prestataireError;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppRefreshService.instance.tick.addListener(_onAppRefreshTick);
    ConversationUnreadService.instance.counts.addListener(_onUnreadChanged);
    NotificationBadgeService.instance.count.addListener(_onUnreadChanged);
    // Ensure statut unread count is synced and watched so the home badge updates
    unawaited(StatutUnreadService.instance.syncAndWatch());
    PrestataireRealtimeService.instance.changes.addListener(
      _onPrestataireAvailabilityChanged,
    );
    PrestataireRealtimeService.instance.watch();
    _loadServicesData();
    _loadFavoriteIds();
    _loadPrestataires(page: 1);
    unawaited(ConversationUnreadService.instance.syncAndWatchConversations());
    unawaited(NotificationBadgeService.instance.syncAndWatch());
    _scrollController.addListener(_onScroll);
  }

  Future<void> _loadFavoriteIds({bool silent = false}) async {
    if (!AuthService.instance.isLoggedIn) {
      if (!mounted) return;
      setState(() => _favoritePrestataireIds.clear());
      return;
    }

    if (!silent) setState(() => _favoritesLoading = true);
    try {
      final favoris = await FavoriService.instance.getFavoris();
      if (!mounted) return;
      setState(() {
        _favoritePrestataireIds
          ..clear()
          ..addAll(favoris.results.map((favori) => favori.prestataire));
        if (!silent) _favoritesLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (!silent) setState(() => _favoritesLoading = false);
      debugPrint('[loadFavoriteIds] error: $e');
    }
  }

  Future<void> _toggleFavorite(Prestataire prestataire) async {
    if (!AuthService.instance.isLoggedIn) {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => LoginScreen()));
      await _refreshAfterAuthReturn();
      return;
    }
    if (_isCurrentPrestataire(prestataire)) {
      return;
    }

    final wasFavorite = _favoritePrestataireIds.contains(prestataire.id);
    setState(() {
      _favoriteBusyPrestataireId = prestataire.id;
      if (wasFavorite) {
        _favoritePrestataireIds.remove(prestataire.id);
      } else {
        _favoritePrestataireIds.add(prestataire.id);
      }
    });

    try {
      if (wasFavorite) {
        await FavoriService.instance.removeFavoriByPrestataire(prestataire.id);
      } else {
        await FavoriService.instance.addFavori(prestataire.id);
      }
      if (!mounted) return;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (wasFavorite) {
          _favoritePrestataireIds.add(prestataire.id);
        } else {
          _favoritePrestataireIds.remove(prestataire.id);
        }
      });
      debugPrint('[toggleFavorite] error: $e');
    } finally {
      if (mounted) setState(() => _favoriteBusyPrestataireId = null);
    }
  }

  Future<void> _loadServicesData() async {
    try {
      final apiServices = await PrestataireService.instance.getServices(
        pageSize: 500,
      );
      if (!mounted) return;
      setState(() {
        _categories
          ..clear()
          ..addAll(
            apiServices.map(
              (service) => _Category(
                id: service.id,
                label: service.nom,
                icon: Icons.miscellaneous_services_rounded,
              ),
            ),
          );
      });
    } catch (e) {
      debugPrint('Failed to load services from backend: $e');
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _appRefreshDebounce?.cancel();
    _availabilityRefreshDebounce?.cancel();
    AppRefreshService.instance.tick.removeListener(_onAppRefreshTick);
    ConversationUnreadService.instance.counts.removeListener(_onUnreadChanged);
    NotificationBadgeService.instance.count.removeListener(_onUnreadChanged);
    PrestataireRealtimeService.instance.changes.removeListener(
      _onPrestataireAvailabilityChanged,
    );
    PrestataireRealtimeService.instance.unwatch();
    NotificationBadgeService.instance.unwatch();
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    StatutUnreadService.instance.unwatch();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshHomeDataInBackground();
      unawaited(ConversationUnreadService.instance.syncAndWatchConversations());
      unawaited(NotificationBadgeService.instance.syncAndWatch());
    }
  }

  void _onUnreadChanged() {
    if (mounted) setState(() {});
  }

  void _onPrestataireAvailabilityChanged() {
    if (!mounted || _prestataires.isEmpty) return;
    setState(() {
      for (var i = 0; i < _prestataires.length; i++) {
        _prestataires[i] = PrestataireRealtimeService.instance.applyTo(
          _prestataires[i],
        );
      }
    });
    _availabilityRefreshDebounce?.cancel();
    _availabilityRefreshDebounce = Timer(Duration(milliseconds: 500), () {
      unawaited(_loadPrestataires(page: 1, silent: true));
    });
  }

  void _onAppRefreshTick() {
    final refresh = AppRefreshService.instance;
    if (_lastAppRefreshTick == refresh.tick.value) return;
    _lastAppRefreshTick = refresh.tick.value;
    if (!refresh.hasAny({
      AppRefreshTopic.auth,
      AppRefreshTopic.home,
      AppRefreshTopic.prestataires,
      AppRefreshTopic.favorites,
      AppRefreshTopic.statuts,
      AppRefreshTopic.ratings,
      AppRefreshTopic.abonnement,
      AppRefreshTopic.conversations,
    })) {
      return;
    }

    _appRefreshDebounce?.cancel();
    _appRefreshDebounce = Timer(Duration(milliseconds: 350), () {
      unawaited(ConversationUnreadService.instance.syncAndWatchConversations());
      unawaited(NotificationBadgeService.instance.syncUnreadCount());
      _refreshHomeDataInBackground();
    });
  }

  // ── Search debounce ───────────────────────────────────────────────────────
  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(Duration(milliseconds: 450), () {
      _loadPrestataires(page: 1);
    });
  }

  // ── Category tap ─────────────────────────────────────────────────────────
  void _onCategoryTap(int index) {
    setState(() {
      if (_selectedCategoryIndex == index) {
        _selectedCategoryIndex = -1;
        _filterTypeService = null;
        _filterServiceId = null;
      } else {
        _selectedCategoryIndex = index;
        _filterTypeService = _categories[index].label;
        _filterServiceId = _categories[index].id;
      }
    });
    _loadPrestataires(page: 1);
  }

  // ── Remove a single active filter chip ───────────────────────────────────
  void _removeFilter(String key) {
    setState(() {
      // Clear only the requested filter key. Using explicit branches
      // avoids accidental fall-through and ensures only the intended
      // filter is removed.
      if (key == 'commune') {
        _filterCommune = null;
      } else if (key == 'ville') {
        _filterVille = null;
      } else if (key == 'typeService') {
        _filterTypeService = null;
        _filterServiceId = null;
        _selectedCategoryIndex = -1;
      } else if (key == 'estValide') {
        _filterEstValide = null;
      } else if (key == 'disponible') {
        _filterDisponible = null;
      } else if (key == 'ordering') {
        _filterOrdering = null;
      }
    });
    _loadPrestataires(page: 1);
  }

  // ── Open filter bottom sheet ──────────────────────────────────────────────
  void _openFilterSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FilterSheet(
        categories: _categories,
        initialCommune: _filterCommune,
        initialVille: _filterVille,
        initialTypeService: _filterTypeService,
        initialEstValide: _filterEstValide,
        initialDisponible: _filterDisponible,
        initialOrdering: _filterOrdering,
        onApply:
            ({
              required String? commune,
              required String? ville,
              required String? typeService,
              required bool? estValide,
              required bool? disponible,
              required String? ordering,
            }) {
              setState(() {
                _filterCommune = commune;
                _filterVille = ville;
                _filterTypeService = typeService;
                _filterServiceId = null;
                for (final cat in _categories) {
                  if (cat.label == typeService) {
                    _filterServiceId = cat.id;
                    break;
                  }
                }
                _filterEstValide = estValide;
                _filterDisponible = disponible;
                _filterOrdering = ordering;
                _selectedCategoryIndex = typeService == null
                    ? -1
                    : _categories.indexWhere((cat) => cat.label == typeService);
              });
              _loadPrestataires(page: 1);
            },
        onReset: () {
          setState(() {
            _filterCommune = null;
            _filterVille = null;
            _filterTypeService = null;
            _filterServiceId = null;
            _selectedCategoryIndex = -1;
            _filterEstValide = null;
            _filterDisponible = null;
            _filterOrdering = null;
          });
          _loadPrestataires(page: 1);
        },
      ),
    );
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _hasNextPage) {
      _loadMorePrestataires();
    }
  }

  bool _isCurrentPrestataire(Prestataire prestataire) {
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) return false;
    return prestataire.utilisateur.id == currentUser.userId;
  }

  List<Prestataire> _excludeCurrentPrestataire(List<Prestataire> results) {
    return results
        .where((prestataire) => !_isCurrentPrestataire(prestataire))
        .toList();
  }

  Future<void> _loadPrestataires({int page = 1, bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoadingInitial = true;
        _prestataireError = null;
        if (page == 1) _prestataires.clear();
      });
    }
    debugPrint(
      '[_loadPrestataires] page=$page search="${_searchController.text.trim()}" typeService=$_filterTypeService commune=$_filterCommune ville=$_filterVille estValide=$_filterEstValide ordering=$_filterOrdering',
    );
    try {
      final result = await PrestataireService.instance.getPrestataires(
        page: page,
        pageSize: 20,
        search: _searchController.text.trim().isEmpty
            ? null
            : _searchController.text.trim(),
        typeService:
            (_filterTypeService != null && _filterTypeService!.isNotEmpty)
            ? _filterTypeService
            : null,
        serviceId: _filterServiceId,
        commune: (_filterCommune != null && _filterCommune!.isNotEmpty)
            ? _filterCommune
            : null,
        ville: (_filterVille != null && _filterVille!.isNotEmpty)
            ? _filterVille
            : null,
        estValide: _filterEstValide,
        disponible: _filterDisponible,
        ordering: (_filterOrdering != null && _filterOrdering!.isNotEmpty)
            ? _filterOrdering
            : null,
      );
      if (!mounted) return;
      final visiblePrestataires = _excludeCurrentPrestataire(result.results);
      PrestataireRealtimeService.instance.registerPrestataires(
        visiblePrestataires,
      );
      final filtered = PrestataireRealtimeService.instance.applyToList(
        visiblePrestataires,
      );
      if (!mounted) return;
      setState(() {
        if (page == 1) {
          _prestataires
            ..clear()
            ..addAll(filtered);
        } else {
          _prestataires.addAll(filtered);
        }
        _hasNextPage = result.hasNext;
        _currentPage = result.currentPage;
        _isLoadingInitial = false;
      });
      _syncRatingSummaries(filtered);
      debugPrint(
        '[loadPrestataires] loaded=${result.results.length} total=${result.totalItems} hasNext=${result.hasNext}',
      );
    } catch (e) {
      debugPrint('[loadPrestataires] error: $e');
      if (!mounted) return;
      if (!silent) {
        setState(() {
          _prestataireError = userFriendlyError(
            e,
            fallback: 'Impossible de charger les prestataires.',
          );
          _isLoadingInitial = false;
        });
      }
    }
  }

  Future<void> _loadMorePrestataires() async {
    if (_isLoadingMore || !_hasNextPage) return;
    setState(() => _isLoadingMore = true);
    debugPrint('[_loadMorePrestataires] nextPage=${_currentPage + 1}');
    try {
      final result = await PrestataireService.instance.getPrestataires(
        page: _currentPage + 1,
        pageSize: 20,
        search: _searchController.text.trim().isEmpty
            ? null
            : _searchController.text.trim(),
        typeService:
            (_filterTypeService != null && _filterTypeService!.isNotEmpty)
            ? _filterTypeService
            : null,
        serviceId: _filterServiceId,
        commune: (_filterCommune != null && _filterCommune!.isNotEmpty)
            ? _filterCommune
            : null,
        ville: (_filterVille != null && _filterVille!.isNotEmpty)
            ? _filterVille
            : null,
        estValide: _filterEstValide,
        disponible: _filterDisponible,
        ordering: (_filterOrdering != null && _filterOrdering!.isNotEmpty)
            ? _filterOrdering
            : null,
      );
      if (!mounted) return;
      final visiblePrestataires = _excludeCurrentPrestataire(result.results);
      PrestataireRealtimeService.instance.registerPrestataires(
        visiblePrestataires,
      );
      final filtered = PrestataireRealtimeService.instance.applyToList(
        visiblePrestataires,
      );
      if (!mounted) return;
      setState(() {
        _prestataires.addAll(filtered);
        _hasNextPage = result.hasNext;
        _currentPage = result.currentPage;
        _isLoadingMore = false;
      });
      _syncRatingSummaries(filtered);
      debugPrint(
        '[loadMorePrestataires] added=${result.results.length} totalNow=${_prestataires.length} hasNext=${result.hasNext}',
      );
    } catch (_) {
      debugPrint('[loadMorePrestataires] error while loading more');
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _refreshAfterAuthReturn({int navIndex = 0}) async {
    if (!mounted) return;
    setState(() => _selectedNavIndex = navIndex);
    await _loadFavoriteIds();
    await _loadPrestataires(page: 1, silent: true);
    if (!mounted) return;
    setState(() => _prestataires.removeWhere(_isCurrentPrestataire));
    _syncRatingSummaries(_prestataires);
  }

  Future<void> _refreshHomeDataInBackground() async {
    if (!mounted) return;
    await Future.wait([
      _loadFavoriteIds(silent: true),
      _loadPrestataires(page: 1, silent: true),
    ]);
    if (!mounted) return;
    _syncRatingSummaries(_prestataires);
  }

  Future<void> _syncRatingSummaries(List<Prestataire> providers) async {
    final missing = providers
        .where((provider) => !_ratingSummaries.containsKey(provider.id))
        .toList();
    if (missing.isEmpty) return;

    for (final provider in missing) {
      try {
        final summary = await PrestataireService.instance.getProviderRatings(
          provider.id,
        );
        if (!mounted) return;
        setState(() => _ratingSummaries[provider.id] = summary);
      } catch (_) {
        // Keep the API-provided fallback values if the rating summary fails.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final visiblePrestataires = _excludeCurrentPrestataire(_prestataires);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: GradientBackground(
        child: SafeArea(
          bottom: false,
          child: CustomScrollView(
            controller: _scrollController,
            physics: BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _buildHeader()),
              SliverToBoxAdapter(child: _buildSearchBar()),
              if (_categories.isNotEmpty)
                SliverToBoxAdapter(child: _buildCategories()),
              if (_activeExtraFilterCount > 0)
                SliverToBoxAdapter(child: _buildActiveFilterChips()),
              SliverToBoxAdapter(
                child: _buildSectionHeader(
                  'Prestataires',
                  trailing: _isLoadingInitial
                      ? null
                      : Text(
                          '${visiblePrestataires.length} résultat${visiblePrestataires.length > 1 ? 's' : ''}',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textHint,
                          ),
                        ),
                ),
              ),
              if (_isLoadingInitial)
                SliverToBoxAdapter(child: _LoadingProviders())
              else if (_prestataireError != null)
                SliverToBoxAdapter(
                  child: _ErrorProviders(
                    message: _prestataireError!,
                    onRetry: () => _loadPrestataires(page: 1),
                  ),
                )
              else if (visiblePrestataires.isEmpty)
                SliverToBoxAdapter(child: _EmptyProviders())
              else ...[
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: _ProviderListCard(
                          prestataire: visiblePrestataires[i],
                          ratings: _ratingSummaries[visiblePrestataires[i].id],
                          isFavorite: _favoritePrestataireIds.contains(
                            visiblePrestataires[i].id,
                          ),
                          favoriteBusy:
                              _favoriteBusyPrestataireId ==
                              visiblePrestataires[i].id,
                          favoritesLoading: _favoritesLoading,
                          onFavoriteTap: () =>
                              _toggleFavorite(visiblePrestataires[i]),
                          onReturnFromDetail: () {
                            _ratingSummaries.remove(visiblePrestataires[i].id);
                            _loadPrestataires(page: 1);
                          },
                        ),
                      ),
                      childCount: visiblePrestataires.length,
                    ),
                  ),
                ),
                if (_isLoadingMore)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: AppColors.primary,
                            strokeWidth: 2.4,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (!_hasNextPage && visiblePrestataires.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Text(
                          '— Fin des résultats —',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textHint,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
              SliverToBoxAdapter(child: SizedBox(height: 110)),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildNavBar(),
      floatingActionButton: _buildFAB(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Header
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    final user = AuthService.instance.currentUser;
    final greeting = user != null
        ? 'Bonjour, ${user.displayName} 👋'
        : 'Bonjour 👋';
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greeting,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textHint,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Trouvez votre\nprestataire idéal',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 12),
          _StatusStoryButton(onTap: _openStatuts),
          SizedBox(width: 10),
          Stack(
            clipBehavior: Clip.none,
            children: [
              GlassIconButton(
                icon: Icons.notifications_outlined,
                onPressed: _openNotifications,
              ),
              if (_notificationBadgeCount > 0)
                Positioned(
                  right: -2,
                  top: -4,
                  child: _UnreadBadge(count: _notificationBadgeCount),
                ),
            ],
          ),
          SizedBox(width: 10),
          // Avatar — tap goes to login if not connected
          GestureDetector(
            onTap: () {
              if (!AuthService.instance.isLoggedIn) {
                Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => LoginScreen()))
                    .then((_) => _refreshAfterAuthReturn());
              } else {
                Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => ProfileScreen()))
                    .then((_) => _refreshAfterAuthReturn());
              }
            },
            child: _HeaderAvatar(size: 44),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Search bar
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildSearchBar() {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.78),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.glassBorder, width: 1.3),
              boxShadow: [
                BoxShadow(
                  color: AppColors.glassShadow,
                  blurRadius: 16,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                SizedBox(width: 16),
                Icon(Icons.search_rounded, color: AppColors.primary, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    onChanged: _onSearchChanged,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) {
                      _debounce?.cancel();
                      _loadPrestataires(page: 1);
                    },
                    decoration: InputDecoration(
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      fillColor: Colors.transparent,
                      hintText: 'Rechercher un prestataire...',
                      hintStyle: TextStyle(
                        color: AppColors.textHint,
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                      ),
                      border: InputBorder.none,

                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                // Clear button
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _searchController,
                  builder: (_, v, __) => v.text.isEmpty
                      ? SizedBox.shrink()
                      : GestureDetector(
                          onTap: () {
                            _searchController.clear();
                            _debounce?.cancel();
                            _loadPrestataires(page: 1);
                          },
                          child: Padding(
                            padding: EdgeInsets.only(right: 8),
                            child: Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: AppColors.textHint,
                            ),
                          ),
                        ),
                ),
                // Filter icon with active-filter badge
                GestureDetector(
                  onTap: _openFilterSheet,
                  child: Container(
                    margin: EdgeInsets.all(7),
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      gradient: _activeExtraFilterCount > 0
                          ? AppColors.primaryGradient
                          : null,
                      color: _activeExtraFilterCount > 0
                          ? null
                          : AppColors.primarySurface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(
                          Icons.tune_rounded,
                          color: _activeExtraFilterCount > 0
                              ? Colors.white
                              : AppColors.primary,
                          size: 17,
                        ),
                        if (_activeExtraFilterCount > 0)
                          Positioned(
                            top: -6,
                            right: -8,
                            child: Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: AppColors.accent,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 1.5,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  '$_activeExtraFilterCount',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Promo banner
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildActiveFilterChips() {
    final chips = <Widget>[];
    if (_filterCommune != null && _filterCommune!.isNotEmpty)
      chips.add(
        _FilterChip(
          icon: Icons.location_on_outlined,
          label: _filterCommune!,
          onRemove: () => _removeFilter('commune'),
        ),
      );
    if (_filterVille != null && _filterVille!.isNotEmpty)
      chips.add(
        _FilterChip(
          icon: Icons.location_city_outlined,
          label: _filterVille!,
          onRemove: () => _removeFilter('ville'),
        ),
      );
    if (_filterTypeService != null && _filterTypeService!.isNotEmpty)
      chips.add(
        _FilterChip(
          icon: Icons.category_outlined,
          label: _filterTypeService!,
          onRemove: () => _removeFilter('typeService'),
        ),
      );
    if (_filterEstValide != null)
      chips.add(
        _FilterChip(
          icon: _filterEstValide!
              ? Icons.verified_outlined
              : Icons.hourglass_top_rounded,
          label: _filterEstValide! ? 'Validés' : 'Non validés',
          onRemove: () => _removeFilter('estValide'),
        ),
      );
    if (_filterDisponible != null)
      chips.add(
        _FilterChip(
          icon: _filterDisponible!
              ? Icons.check_circle_outline
              : Icons.do_not_disturb_on_outlined,
          label: _filterDisponible! ? 'Disponibles' : 'Non disponibles',
          onRemove: () => _removeFilter('disponible'),
        ),
      );
    if (_filterOrdering != null && _filterOrdering!.isNotEmpty)
      chips.add(
        _FilterChip(
          icon: Icons.swap_vert_rounded,
          label: _orderingLabel(_filterOrdering!),
          onRemove: () => _removeFilter('ordering'),
        ),
      );
    return Padding(
      padding: EdgeInsets.only(top: 10, left: 20, right: 20),
      child: Wrap(spacing: 8, runSpacing: 6, children: chips),
    );
  }

  Widget _buildSectionHeader(String title, {Widget? trailing}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 22, 20, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Categories (horizontal scroll)
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildCategories() {
    return Padding(
      padding: EdgeInsets.only(top: 14),
      child: SizedBox(
        height: 38,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: 20),
          itemCount: _categories.length + 1,
          separatorBuilder: (_, __) => SizedBox(width: 8),
          itemBuilder: (ctx, i) {
            if (i == 0) {
              final selected = _selectedCategoryIndex == -1;
              return _CategoryPill(
                label: 'Tous',
                icon: Icons.apps_rounded,
                selected: selected,
                onTap: () {
                  if (selected) return;
                  setState(() {
                    _selectedCategoryIndex = -1;
                    _filterTypeService = null;
                    _filterServiceId = null;
                  });
                  _loadPrestataires(page: 1);
                },
              );
            }
            final cat = _categories[i - 1];
            final bool sel = i - 1 == _selectedCategoryIndex;
            return _CategoryPill(
              label: cat.label,
              icon: cat.icon,
              selected: sel,
              onTap: () => _onCategoryTap(i - 1),
            );
          },
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Featured services (horizontal scroll)
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildNavBar() {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            height: 66,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.82),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: AppColors.glassBorder, width: 1.3),
              boxShadow: [
                BoxShadow(
                  color: AppColors.glassShadow,
                  blurRadius: 28,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(
                  icon: Icons.home_rounded,
                  label: 'Accueil',
                  selected: _selectedNavIndex == 0,
                  onTap: () => setState(() => _selectedNavIndex = 0),
                ),
                _NavItem(
                  icon: Icons.assignment_outlined,
                  label: 'Demandes',
                  selected: _selectedNavIndex == 1,
                  onTap: _openDemandes,
                ),
                SizedBox(width: 56), // espace FAB
                _NavItem(
                  icon: Icons.favorite_outline_rounded,
                  label: 'Favoris',
                  selected: _selectedNavIndex == 3,
                  onTap: _openFavoris,
                ),
                _ProfileNavItem(
                  selected: _selectedNavIndex == 4,
                  onTap: () {
                    setState(() => _selectedNavIndex = 4);
                    final route = MaterialPageRoute(
                      builder: (_) => AuthService.instance.isLoggedIn
                          ? ProfileScreen()
                          : LoginScreen(),
                    );
                    Navigator.of(context).push(route).then((_) {
                      _refreshAfterAuthReturn();
                    });
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFAB() {
    return Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: _focusProviderSearch,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppColors.primaryGradient,
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.40),
                blurRadius: 22,
                offset: Offset(0, 8),
              ),
            ],
            border: Border.all(color: Colors.white.withOpacity(0.5), width: 2),
          ),
          child: Icon(Icons.search_rounded, color: Colors.white, size: 25),
        ),
      ),
    );
  }

  void _openDemandes() {
    setState(() => _selectedNavIndex = 1);
    final loggedIn = AuthService.instance.isLoggedIn;
    final isPrestataire =
        AuthService.instance.currentUser?.estPrestataire == true;
    final route = MaterialPageRoute(
      builder: (_) {
        if (!loggedIn) return LoginScreen();
        return isPrestataire
            ? DemandesPrestataireScreen()
            : DemandesClientScreen();
      },
    );
    Navigator.of(context).push(route).then((_) {
      _refreshAfterAuthReturn();
    });
  }

  void _openFavoris() {
    setState(() => _selectedNavIndex = 3);
    final route = MaterialPageRoute(
      builder: (_) =>
          AuthService.instance.isLoggedIn ? FavorisScreen() : LoginScreen(),
    );
    Navigator.of(context).push(route).then((_) {
      _refreshAfterAuthReturn();
    });
  }

  void _openNotifications() {
    if (ConversationUnreadService.instance.totalUnread > 0) {
      unawaited(_openUnreadConversation());
      return;
    }
    _openNotificationsList();
  }

  int get _notificationBadgeCount {
    final notificationCount = NotificationBadgeService.instance.totalUnread;
    if (notificationCount > 0) return notificationCount;
    return ConversationUnreadService.instance.totalUnread;
  }

  void _openNotificationsList() {
    final route = MaterialPageRoute(
      builder: (_) => AuthService.instance.isLoggedIn
          ? NotificationsScreen()
          : LoginScreen(),
    );
    Navigator.of(context).push(route).then((_) {
      _refreshAfterAuthReturn();
    });
  }

  Future<void> _openUnreadConversation() async {
    final service = ConversationUnreadService.instance;
    final conversationId = service.latestUnreadConversationId;
    if (conversationId == null) {
      _openNotificationsList();
      return;
    }

    final conversation = service.conversationFor(conversationId);
    final demande = await service.demandeForConversation(conversationId);
    if (!mounted) return;
    if (conversation == null || demande == null) {
      _openNotificationsList();
      return;
    }

    service.markConversationOpen(conversationId);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConversationScreen(
          demande: demande,
          title: service.titleFor(conversation),
          allowAcceptPrestation:
              AuthService.instance.currentUser?.estPrestataire ?? false,
        ),
      ),
    );
    service.markConversationRead(conversationId);
    await service.syncAndWatchConversations();
  }

  void _openStatuts() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => StatutsPrestatairesScreen()));
  }

  void _focusProviderSearch() {
    setState(() => _selectedNavIndex = 0);
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    }
    _searchFocusNode.requestFocus();
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ────────────────────────────────────────────────────────────────────────────

/// Round avatar: shows network photo when available, initial letter otherwise.
/// Used in the header and the "Profil" nav-bar item.
class _HeaderAvatar extends StatelessWidget {
  _HeaderAvatar({this.size = 44});
  final double size;

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;
    final radius = size / 2;
    // Extract photo URL (non-null, non-empty) for type promotion
    final String? photoUrl =
        (user != null && user.photo != null && user.photo!.isNotEmpty)
        ? ApiConstants.resolveUrl(user.photo!)
        : null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: photoUrl != null
            ? Image.network(
                photoUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _AvatarFallback(
                  size: size,
                  initial: user != null && user.displayName.isNotEmpty
                      ? user.displayName[0].toUpperCase()
                      : '?',
                ),
              )
            : _AvatarFallback(
                size: size,
                initial: (user != null && user.displayName.isNotEmpty)
                    ? user.displayName[0].toUpperCase()
                    : null,
              ),
      ),
    );
  }
}

/// Gradient fallback with an optional letter or person icon.
class _AvatarFallback extends StatelessWidget {
  _AvatarFallback({required this.size, this.initial});
  final double size;
  final String? initial;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: initial != null
            ? AppColors.primaryGradient
            : LinearGradient(colors: [Color(0xFFB0BEC5), Color(0xFF90A4AE)]),
      ),
      alignment: Alignment.center,
      child: initial != null
          ? Text(
              initial!,
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.40,
                fontWeight: FontWeight.w700,
              ),
            )
          : Icon(Icons.person_rounded, color: Colors.white, size: size * 0.50),
    );
  }
}

class _StatusStoryButton extends StatelessWidget {
  _StatusStoryButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        padding: EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: AppColors.primaryGradient,
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.24),
              blurRadius: 14,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.94),
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                Icons.auto_awesome_motion_outlined,
                color: AppColors.primary,
                size: 19,
              ),
              Positioned(
                right: 4,
                bottom: 4,
                child: ValueListenableBuilder<int>(
                  valueListenable: StatutUnreadService.instance.count,
                  builder: (_, unreadCount, __) {
                    final hasUnread = unreadCount > 0;
                    return Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: hasUnread ? Color(0xFFFF8A00) : AppColors.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom-nav "Profil" item — shows the real avatar photo when logged in.
class _ProfileNavItem extends StatelessWidget {
  _ProfileNavItem({required this.selected, required this.onTap});
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final loggedIn = AuthService.instance.isLoggedIn;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: ClipRect(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: 54),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  width: selected ? 34 : 30,
                  height: selected ? 34 : 30,
                  decoration: selected
                      ? BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.primary,
                            width: 2.5,
                          ),
                        )
                      : null,
                  child: ClipOval(
                    child: loggedIn
                        ? _HeaderAvatar(size: selected ? 30 : 30)
                        : Container(
                            color: Color(0xFFB0BEC5),
                            child: Icon(
                              Icons.person_outline_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                  ),
                ),
                if (!selected) ...[
                  SizedBox(height: 1),
                  Text(
                    'Profil',
                    style: TextStyle(
                      fontSize: 9,
                      color: AppColors.textHint,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: ClipRect(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: 54),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  padding: selected ? EdgeInsets.all(4) : EdgeInsets.zero,
                  decoration: selected
                      ? BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius: BorderRadius.circular(10),
                        )
                      : null,
                  child: Icon(
                    icon,
                    color: selected ? Colors.white : AppColors.textHint,
                    size: 20,
                  ),
                ),
                if (!selected) ...[
                  SizedBox(height: 1),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.textHint,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider card
// ─────────────────────────────────────────────────────────────────────────────

class _ProviderListCard extends StatelessWidget {
  _ProviderListCard({
    required this.prestataire,
    this.ratings,
    required this.isFavorite,
    required this.favoriteBusy,
    required this.favoritesLoading,
    required this.onFavoriteTap,
    this.onReturnFromDetail,
  });

  final Prestataire prestataire;
  final NotationsResponse? ratings;
  final bool isFavorite;
  final bool favoriteBusy;
  final bool favoritesLoading;
  final VoidCallback onFavoriteTap;
  final VoidCallback? onReturnFromDetail;

  @override
  Widget build(BuildContext context) {
    final user = prestataire.utilisateur;
    final hasPhoto = user.photoProfil != null && user.photoProfil!.isNotEmpty;
    final avisCount = ratings?.totalRatings ?? prestataire.nombreCommentaires;
    final averageRating = ratings?.averageRating ?? prestataire.moyenneNotes;

    return GlassCard(
      borderRadius: 20,
      padding: EdgeInsets.all(16),
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PrestataireDetailScreen(prestataire: prestataire),
          ),
        );
        onReturnFromDetail?.call();
      },
      child: Row(
        children: [
          // ── Avatar ──────────────────────────────────────────────────────
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradientSoft,
                borderRadius: BorderRadius.circular(16),
              ),
              child: hasPhoto
                  ? Image.network(
                      ApiConstants.resolveUrl(user.photoProfil!),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Icon(
                        Icons.person_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    )
                  : Icon(Icons.person_rounded, color: Colors.white, size: 28),
            ),
          ),
          SizedBox(width: 14),

          // ── Info ────────────────────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name + badge
                Row(
                  children: [
                    Expanded(
                      child: NameWithCertification(
                        name: user.displayName,
                        estCertifie: prestataire.isCertified,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                        badgeSize: 15,
                      ),
                    ),
                    _AvailabilityDot(
                      key: ValueKey(
                        'availability-${prestataire.id}-${prestataire.isAvailable}',
                      ),
                      isAvailable: prestataire.isAvailable,
                    ),
                    SizedBox(width: 8),
                    _FavoriteButton(
                      selected: isFavorite,
                      busy: favoriteBusy,
                      disabled: favoritesLoading,
                      onTap: onFavoriteTap,
                    ),
                  ],
                ),
                SizedBox(height: 3),
                SizedBox(height: 4),
                // Service type
                Text(
                  prestataire.servicesLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                if (prestataire.niveau.isNotEmpty) ...[
                  SizedBox(height: 6),
                  Row(
                    children: [
                      _LevelBadge(
                        niveau: prestataire.niveau,
                        score: prestataire.scoreNiveau,
                      ),
                      SizedBox(width: 8),
                      Text(
                        '${prestataire.missionsReussies} missions',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textHint,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
                SizedBox(height: 4),
                // Presentation
                Text(
                  prestataire.presentation,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 8),
                // Bottom row
                Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 12,
                      color: AppColors.textHint,
                    ),
                    SizedBox(width: 3),
                    Expanded(
                      child: Text(
                        '${prestataire.commune}, ${prestataire.ville}',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textHint,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(width: 6),
                    Icon(
                      Icons.photo_library_outlined,
                      size: 12,
                      color: AppColors.textHint,
                    ),
                    SizedBox(width: 3),
                    Text(
                      '${prestataire.nombrePhotos}',
                      style: TextStyle(fontSize: 11, color: AppColors.textHint),
                    ),
                    SizedBox(width: 6),
                    Icon(
                      Icons.star_rounded,
                      size: 12,
                      color: AppColors.warning,
                    ),
                    SizedBox(width: 3),
                    Text(
                      averageRating != null && avisCount > 0
                          ? '${averageRating.toStringAsFixed(1)} • $avisCount avis'
                          : '$avisCount avis',
                      style: TextStyle(fontSize: 11, color: AppColors.textHint),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(width: 8),
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.primarySurface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.arrow_forward_ios_rounded,
              color: AppColors.primary,
              size: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _LevelBadge extends StatelessWidget {
  _LevelBadge({required this.niveau, required this.score});

  final String niveau;
  final int score;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primarySurface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.workspace_premium_rounded,
            size: 12,
            color: AppColors.primary,
          ),
          SizedBox(width: 4),
          Text(
            '${niveau[0].toUpperCase()}${niveau.substring(1)} • $score',
            style: TextStyle(
              fontSize: 10,
              color: AppColors.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    return Container(
      constraints: BoxConstraints(minWidth: 18, minHeight: 18),
      padding: EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: AppColors.error,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }
}

class _FavoriteButton extends StatelessWidget {
  _FavoriteButton({
    required this.selected,
    required this.busy,
    required this.disabled,
    required this.onTap,
  });

  final bool selected;
  final bool busy;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.error : AppColors.textHint;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: disabled || busy ? null : onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: selected
              ? AppColors.error.withValues(alpha: 0.10)
              : AppColors.primarySurface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: busy
            ? Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(color: color, strokeWidth: 2),
              )
            : Icon(
                selected
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                color: color,
                size: 17,
              ),
      ),
    );
  }
}

class _AvailabilityDot extends StatefulWidget {
  _AvailabilityDot({super.key, required this.isAvailable});
  final bool isAvailable;

  @override
  State<_AvailabilityDot> createState() => _AvailabilityDotState();
}

class _AvailabilityDotState extends State<_AvailabilityDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(
      begin: 0.9,
      end: 1.15,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isAvailable ? AppColors.success : AppColors.error;
    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, _) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: AnimatedContainer(
            duration: Duration(milliseconds: 220),
            curve: Curves.easeOut,
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.25),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Loading / Error / Empty states
// ─────────────────────────────────────────────────────────────────────────────

class _LoadingProviders extends StatelessWidget {
  _LoadingProviders();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        children: List.generate(4, (i) => _SkeletonCard(key: ValueKey(i))),
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  _SkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: GlassCard(
        borderRadius: 20,
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 13,
                    width: 130,
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  SizedBox(height: 8),
                  Container(
                    height: 10,
                    width: 80,
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  SizedBox(height: 8),
                  Container(
                    height: 10,
                    width: 170,
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorProviders extends StatelessWidget {
  _ErrorProviders({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: GlassCard(
        borderRadius: 20,
        padding: EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.wifi_off_rounded, size: 36, color: AppColors.textHint),
            SizedBox(height: 10),
            Text(
              message,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 14),
            GestureDetector(
              onTap: onRetry,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Réessayer',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyProviders extends StatelessWidget {
  _EmptyProviders();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: GlassCard(
        borderRadius: 20,
        padding: EdgeInsets.all(32),
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.primarySurface,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.search_off_rounded,
                size: 36,
                color: AppColors.primary,
              ),
            ),
            SizedBox(height: 14),
            Text(
              'Aucun prestataire trouvé',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Essayez de modifier vos filtres\nou votre recherche.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Filter bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

typedef _FilterApplyCallback =
    void Function({
      required String? commune,
      required String? ville,
      required String? typeService,
      required bool? estValide,
      required bool? disponible,
      required String? ordering,
    });

class _FilterSheet extends StatefulWidget {
  _FilterSheet({
    required this.categories,
    required this.initialCommune,
    required this.initialVille,
    required this.initialTypeService,
    required this.initialEstValide,
    required this.initialDisponible,
    required this.initialOrdering,
    required this.onApply,
    required this.onReset,
  });

  final List<_Category> categories;
  final String? initialCommune;
  final String? initialVille;
  final String? initialTypeService;
  final bool? initialEstValide;
  final bool? initialDisponible;
  final String? initialOrdering;
  final _FilterApplyCallback onApply;
  final VoidCallback onReset;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  String? _selectedCommune;
  String? _selectedVille;
  String? _selectedTypeService;
  bool? _estValide;
  bool? _disponible;
  String? _ordering;

  Future<void> _openTypeServiceSheet() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ServiceTypePickerSheet(
        categories: widget.categories,
        initial: _selectedTypeService,
      ),
    );
    if (selected != null) {
      setState(() {
        _selectedTypeService = selected.isEmpty ? null : selected;
      });
    }
  }

  static List<_OrderingOption> _options = [
    _OrderingOption(value: '', label: 'Défaut'),
    _OrderingOption(value: 'utilisateur__last_name', label: 'Nom A→Z'),
    _OrderingOption(value: '-utilisateur__last_name', label: 'Nom Z→A'),
    _OrderingOption(value: '-date_joined', label: 'Plus récents'),
    _OrderingOption(value: 'date_joined', label: 'Plus anciens'),
    _OrderingOption(value: '-nombre_commentaires', label: 'Mieux notés'),
  ];

  @override
  void initState() {
    super.initState();
    _selectedCommune = widget.initialCommune;
    // Une ville saisie hors liste reste affichée telle quelle : on ne perd
    // jamais une localisation déjà enregistrée.
    _selectedVille = widget.initialVille;
    _selectedTypeService = widget.initialTypeService;
    _estValide = widget.initialEstValide;
    _disponible = widget.initialDisponible;
    _ordering = widget.initialOrdering ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            height: MediaQuery.of(context).size.height * 0.74,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.92),
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              border: Border.all(color: AppColors.glassBorder, width: 1.3),
            ),
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(24, 16, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.divider,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    SizedBox(height: 16),
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: AppColors.primarySurface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppColors.glassBorder,
                                width: 1.2,
                              ),
                            ),
                            child: Icon(
                              Icons.arrow_back_rounded,
                              color: AppColors.primary,
                              size: 20,
                            ),
                          ),
                        ),
                        SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            'Filtres & Tri',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 18),
                    Expanded(
                      child: SingleChildScrollView(
                        physics: BouncingScrollPhysics(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Type de service
                            _SheetLabel('Type de service'),
                            SizedBox(height: 8),
                            GestureDetector(
                              onTap: _openTypeServiceSheet,
                              child: Container(
                                height: 48,
                                decoration: BoxDecoration(
                                  color: AppColors.primarySurface,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: AppColors.glassBorder,
                                    width: 1.2,
                                  ),
                                ),
                                padding: EdgeInsets.symmetric(horizontal: 14),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.search_rounded,
                                      size: 18,
                                      color: AppColors.primary,
                                    ),
                                    SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        _selectedTypeService ??
                                            'Sélectionner un type de service',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: _selectedTypeService != null
                                              ? AppColors.textPrimary
                                              : AppColors.textHint,
                                        ),
                                      ),
                                    ),
                                    Icon(
                                      Icons.keyboard_arrow_right_rounded,
                                      size: 20,
                                      color: AppColors.textSecondary,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (_selectedTypeService != null) ...[
                              SizedBox(height: 12),
                              _StatusChip(
                                label: _selectedTypeService!,
                                selected: true,
                                onTap: _openTypeServiceSheet,
                              ),
                            ],
                            SizedBox(height: 18),
                            // Ville
                            _SheetLabel('Ville'),
                            SizedBox(height: 8),
                            _VilleSelector(
                              value: _selectedVille,
                              allowPartout: true,
                              onChanged: (v) => setState(() {
                                _selectedVille = v;
                                // La commune dépend de la ville : on
                                // réinitialise si elle n'y appartient plus.
                                if (!Locations.communeAppartientA(
                                  commune: _selectedCommune,
                                  ville: v,
                                )) {
                                  _selectedCommune = null;
                                }
                              }),
                            ),
                            SizedBox(height: 18),
                            // Commune
                            _SheetLabel('Commune'),
                            SizedBox(height: 8),
                            _CommuneSelector(
                              value: _selectedCommune,
                              ville: _selectedVille,
                              onChanged: (v) =>
                                  setState(() => _selectedCommune = v),
                            ),
                            SizedBox(height: 18),
                            _SheetLabel('Disponibilité'),
                            SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _StatusChip(
                                  label: 'Disponibles',
                                  selected: _disponible == true,
                                  onTap: () => setState(
                                    () => _disponible = _disponible == true
                                        ? null
                                        : true,
                                  ),
                                ),
                                _StatusChip(
                                  label: 'Non disponibles',
                                  selected: _disponible == false,
                                  onTap: () => setState(
                                    () => _disponible = _disponible == false
                                        ? null
                                        : false,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 18),
                            // Ordering
                            _SheetLabel('Trier par'),
                            SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _options.map((opt) {
                                final sel = (_ordering ?? '') == opt.value;
                                return _StatusChip(
                                  label: opt.label,
                                  selected: sel,
                                  onTap: () =>
                                      setState(() => _ordering = opt.value),
                                );
                              }).toList(),
                            ),
                            SizedBox(height: 12),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 14),
                    // Buttons
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              Navigator.pop(context);
                              widget.onReset();
                            },
                            child: Container(
                              height: 48,
                              decoration: BoxDecoration(
                                color: AppColors.primarySurface,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Center(
                                child: Text(
                                  'Réinitialiser',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: GestureDetector(
                            onTap: () {
                              Navigator.pop(context);
                              widget.onApply(
                                commune: _selectedCommune,
                                ville: _selectedVille,
                                typeService: _selectedTypeService,
                                estValide: _estValide,
                                disponible: _disponible,
                                ordering:
                                    (_ordering == null || _ordering!.isEmpty)
                                    ? null
                                    : _ordering,
                              );
                            },
                            child: Container(
                              height: 48,
                              decoration: BoxDecoration(
                                gradient: AppColors.primaryGradient,
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary.withOpacity(0.28),
                                    blurRadius: 16,
                                    offset: Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Text(
                                  'Appliquer',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Filter sheet helpers
// ─────────────────────────────────────────────────────────────────────────────

class _SheetLabel extends StatelessWidget {
  _SheetLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: AppColors.textSecondary,
    ),
  );
}

class _ServiceTypePickerSheet extends StatefulWidget {
  _ServiceTypePickerSheet({required this.categories, this.initial});

  final List<_Category> categories;
  final String? initial;

  @override
  State<_ServiceTypePickerSheet> createState() =>
      _ServiceTypePickerSheetState();
}

class _ServiceTypePickerSheetState extends State<_ServiceTypePickerSheet> {
  late TextEditingController _searchCtrl;
  String? _selectedType;

  List<_Category> get _filteredCategories {
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isEmpty) return widget.categories;
    return widget.categories
        .where((cat) => cat.label.toLowerCase().contains(query))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _selectedType = widget.initial;
    _searchCtrl = TextEditingController(text: widget.initial ?? '');
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredCategories = _filteredCategories;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.74,
            ),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.92),
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              border: Border.all(color: AppColors.glassBorder, width: 1.3),
            ),
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(24, 16, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.divider,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    SizedBox(height: 16),
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: AppColors.primarySurface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppColors.glassBorder,
                                width: 1.2,
                              ),
                            ),
                            child: Icon(
                              Icons.arrow_back_rounded,
                              color: AppColors.primary,
                              size: 20,
                            ),
                          ),
                        ),
                        SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            'Type de service',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 18),
                    _SheetTextField(
                      controller: _searchCtrl,
                      hint: 'Rechercher un type de service...',
                      icon: Icons.search_rounded,
                      onChanged: (_) => setState(() {}),
                    ),
                    SizedBox(height: 16),
                    Expanded(
                      child: filteredCategories.isEmpty
                          ? Padding(
                              padding: EdgeInsets.symmetric(vertical: 28),
                              child: Center(
                                child: Text(
                                  'Aucun type correspondant.',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            )
                          : ListView.builder(
                              itemCount: filteredCategories.length + 1,
                              padding: EdgeInsets.only(bottom: 10),
                              itemBuilder: (_, index) {
                                if (index == 0) {
                                  final selected = _selectedType == null;
                                  return _ServiceTypeListTile(
                                    label: 'Tous les services',
                                    icon: Icons.apps_rounded,
                                    selected: selected,
                                    onTap: () => Navigator.pop(context, ''),
                                  );
                                }
                                final cat = filteredCategories[index - 1];
                                final selected = _selectedType == cat.label;
                                return _ServiceTypeListTile(
                                  label: cat.label,
                                  icon: cat.icon,
                                  selected: selected,
                                  onTap: () =>
                                      Navigator.pop(context, cat.label),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ServiceTypeListTile extends StatelessWidget {
  _ServiceTypeListTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        color: selected ? AppColors.primarySurface : Colors.transparent,
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primary.withValues(alpha: 0.12)
                    : AppColors.primarySurface,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: AppColors.primary, size: 18),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? AppColors.primary : AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ),
            if (selected)
              Icon(Icons.check_rounded, color: AppColors.primary, size: 18),
          ],
        ),
      ),
    );
  }
}

class _SheetTextField extends StatelessWidget {
  _SheetTextField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.onChanged,
  });
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: AppColors.primarySurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.glassBorder, width: 1.2),
      ),
      child: Row(
        children: [
          SizedBox(width: 14),
          Icon(icon, size: 18, color: AppColors.primary),
          SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              decoration: InputDecoration(
                hintText: hint,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                fillColor: Colors.transparent,
                hintStyle: TextStyle(color: AppColors.textHint, fontSize: 13),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  _StatusChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: selected ? AppColors.primaryGradient : null,
          color: selected ? null : AppColors.primarySurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? Colors.transparent : AppColors.glassBorder,
            width: 1.2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

@immutable
class _OrderingOption {
  final String value;
  final String label;
  _OrderingOption({required this.value, required this.label});
}

// ─────────────────────────────────────────────────────────────────────────────
// Category pill
// ─────────────────────────────────────────────────────────────────────────────

class _CategoryPill extends StatelessWidget {
  _CategoryPill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: selected ? AppColors.primaryGradient : null,
          color: selected ? null : Colors.white.withOpacity(0.75),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? Colors.transparent : AppColors.glassBorder,
            width: 1.3,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.28),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: selected ? Colors.white : AppColors.textSecondary,
            ),
            SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Active filter chip (removable)
// ─────────────────────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  _FilterChip({
    required this.icon,
    required this.label,
    required this.onRemove,
  });
  final IconData icon;
  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(left: 12, right: 6, top: 6, bottom: 6),
      decoration: BoxDecoration(
        color: AppColors.primarySurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.primary.withOpacity(0.25),
          width: 1.2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.primary),
          SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryDark,
            ),
          ),
          SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.close_rounded,
                size: 11,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Data models
// ─────────────────────────────────────────────────────────────────────────────

@immutable
class _Category {
  final int? id;
  final String label;
  final IconData icon;
  _Category({this.id, required this.label, required this.icon});
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

String _orderingLabel(String value) {
  switch (value) {
    case 'utilisateur__last_name':
      return 'Nom A→Z';
    case '-utilisateur__last_name':
      return 'Nom Z→A';
    case '-date_joined':
      return 'Plus récents';
    case 'date_joined':
      return 'Plus anciens';
    case '-nombre_commentaires':
      return 'Mieux notés';
    default:
      return value;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Selecteur de ville (avec option « Partout » pour les filtres)

/// Champ de sélection d'une ville, avec l'option « Partout » (aucun filtre).
class _VilleSelector extends StatelessWidget {
  _VilleSelector({
    required this.value,
    required this.onChanged,
    this.allowPartout = false,
  });

  final String? value;
  final void Function(String?) onChanged;
  final bool allowPartout;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final result = await showModalBottomSheet<String>(
          context: context,
          backgroundColor: Colors.transparent,
          isScrollControlled: true,
          builder: (_) =>
              _VillePickerSheet(initial: value, allowPartout: allowPartout),
        );
        if (result != null) onChanged(result.isEmpty ? null : result);
      },
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.primarySurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.glassBorder, width: 1.2),
        ),
        padding: EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Icon(
              Icons.location_city_outlined,
              size: 18,
              color: AppColors.primary,
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                value ?? (allowPartout ? 'Partout' : 'Sélectionner une ville'),
                style: TextStyle(
                  fontSize: 13,
                  color: value != null
                      ? AppColors.textPrimary
                      : AppColors.textHint,
                ),
              ),
            ),
            if (value != null)
              GestureDetector(
                onTap: () => onChanged(null),
                child: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
              )
            else
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 20,
                color: AppColors.textSecondary,
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Commune selector (tappable field → picker sheet)

class _CommuneSelector extends StatelessWidget {
  _CommuneSelector({
    required this.value,
    required this.onChanged,
    required this.ville,
  });

  final String? value;
  final void Function(String?) onChanged;
  final String? ville;

  @override
  Widget build(BuildContext context) {
    final communes = Locations.communesDe(ville);
    final desactive = communes.isEmpty;

    return Opacity(
      opacity: desactive ? 0.55 : 1,
      child: GestureDetector(
        onTap: desactive
            ? null
            : () async {
                final result = await showModalBottomSheet<String>(
                  context: context,
                  backgroundColor: Colors.transparent,
                  isScrollControlled: true,
                  builder: (_) =>
                      _CommunePickerSheet(initial: value, communes: communes),
                );
                if (result != null) {
                  onChanged(result.isEmpty ? null : result);
                }
              },
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.primarySurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.glassBorder, width: 1.2),
          ),
          padding: EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Icon(
                Icons.location_on_outlined,
                size: 18,
                color: AppColors.primary,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  desactive
                      ? 'Sélectionnez d’abord une ville'
                      : value ?? 'Sélectionner une commune',
                  style: TextStyle(
                    fontSize: 13,
                    color: value != null && !desactive
                        ? AppColors.textPrimary
                        : AppColors.textHint,
                  ),
                ),
              ),
              if (value != null && !desactive)
                GestureDetector(
                  onTap: () => onChanged(null),
                  child: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                )
              else
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Ville picker bottom sheet

class _VillePickerSheet extends StatefulWidget {
  _VillePickerSheet({this.initial, this.allowPartout = false});
  final String? initial;
  final bool allowPartout;

  @override
  State<_VillePickerSheet> createState() => _VillePickerSheetState();
}

class _VillePickerSheetState extends State<_VillePickerSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<Ville> _filtered = Locations.villes;

  void _onSearch(String q) {
    setState(() {
      final query = q.trim().toLowerCase();
      _filtered = query.isEmpty
          ? Locations.villes
          : Locations.villes
                .where(
                  (v) =>
                      v.nom.toLowerCase().contains(query) ||
                      v.communes.any((c) => c.toLowerCase().contains(query)),
                )
                .toList();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.92),
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              border: Border.all(color: AppColors.glassBorder, width: 1.3),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(height: 12),
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(20, 16, 20, 10),
                  child: Container(
                    height: 46,
                    decoration: BoxDecoration(
                      color: AppColors.primarySurface,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        Icon(
                          Icons.search_rounded,
                          size: 18,
                          color: AppColors.primary,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _searchCtrl,
                            onChanged: _onSearch,
                            style: const TextStyle(fontSize: 14),
                            decoration: const InputDecoration(
                              hintText: 'Rechercher une ville…',
                              border: InputBorder.none,
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 20),
                    children: [
                      if (widget.allowPartout)
                        _VilleTile(
                          nom: 'Partout',
                          communes: const [],
                          selected: widget.initial == null,
                          onTap: () => Navigator.pop(context, ''),
                        ),
                      ..._filtered.map(
                        (v) => _VilleTile(
                          nom: v.nom,
                          communes: v.communes,
                          selected: v.nom.toLowerCase() ==
                              (widget.initial ?? '').toLowerCase(),
                          onTap: () => Navigator.pop(context, v.nom),
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
}

// ─────────────────────────────────────────────────────────────────────────────
// Commune picker bottom sheet

class _VilleTile extends StatelessWidget {
  _VilleTile({
    required this.nom,
    required this.communes,
    required this.selected,
    required this.onTap,
  });

  final String nom;
  final List<String> communes;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nom,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? AppColors.primary
                          : AppColors.textPrimary,
                    ),
                  ),
                  if (communes.isNotEmpty) ...[
                    SizedBox(height: 2),
                    Text(
                      '${communes.length} commune'
                      '${communes.length > 1 ? 's' : ''}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textHint,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (selected)
              const Icon(
                Icons.check_rounded,
                color: AppColors.primary,
                size: 18,
              ),
          ],
        ),
      ),
    );
  }
}

class _CommunePickerSheet extends StatefulWidget {
  _CommunePickerSheet({this.initial, required this.communes});
  final String? initial;
  final List<String> communes;

  @override
  State<_CommunePickerSheet> createState() => _CommunePickerSheetState();
}

class _CommunePickerSheetState extends State<_CommunePickerSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  late List<String> _filtered = widget.communes;

  void _onSearch(String q) {
    setState(() {
      final query = q.trim().toLowerCase();
      _filtered = query.isEmpty
          ? widget.communes
          : widget.communes
                .where((c) => c.toLowerCase().contains(query))
                .toList();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.92),
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              border: Border.all(color: AppColors.glassBorder, width: 1.3),
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle
                  Padding(
                    padding: EdgeInsets.only(top: 12, bottom: 4),
                    child: Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.divider,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(24, 12, 24, 16),
                    child: Text(
                      'Commune',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  // Search field
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: _SheetTextField(
                      controller: _searchCtrl,
                      hint: 'Rechercher une commune…',
                      icon: Icons.search_rounded,
                      onChanged: _onSearch,
                    ),
                  ),
                  SizedBox(height: 10),
                  // List
                  SizedBox(
                    height: 300,
                    child: _filtered.isEmpty
                        ? Center(
                            child: Text(
                              'Aucune commune trouvée',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 4,
                            ),
                            itemCount: _filtered.length,
                            itemBuilder: (_, i) {
                              final c = _filtered[i];
                              final selected = c == widget.initial;
                              return InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () => Navigator.pop(context, c),
                                child: AnimatedContainer(
                                  duration: Duration(milliseconds: 150),
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 13,
                                  ),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? AppColors.primarySurface
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          c,
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: selected
                                                ? AppColors.primary
                                                : AppColors.textPrimary,
                                            fontWeight: selected
                                                ? FontWeight.w600
                                                : FontWeight.w400,
                                          ),
                                        ),
                                      ),
                                      if (selected)
                                        Icon(
                                          Icons.check_rounded,
                                          size: 16,
                                          color: AppColors.primary,
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
