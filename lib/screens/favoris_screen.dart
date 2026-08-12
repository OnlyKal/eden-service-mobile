import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/models/favori_models.dart';
import '../core/services/app_refresh_service.dart';
import '../core/services/auth_service.dart';
import '../core/services/favori_service.dart';
import '../core/services/prestataire_service.dart';
import '../core/utils/user_friendly_error.dart';
import '../theme/app_colors.dart';
import '../widgets/gradient_background.dart';
import 'login_screen.dart';
import 'prestataire_detail_screen.dart';

class FavorisScreen extends StatefulWidget {
  FavorisScreen({super.key});

  @override
  State<FavorisScreen> createState() => _FavorisScreenState();
}

class _FavorisScreenState extends State<FavorisScreen> {
  bool _loading = true;
  int? _busyId;
  int? _openingPrestataireId;
  int _lastRefreshTick = 0;
  List<Favori> _favoris = [];

  @override
  void initState() {
    super.initState();
    AppRefreshService.instance.tick.addListener(_onAppRefresh);
    _loadFavoris();
  }

  @override
  void dispose() {
    AppRefreshService.instance.tick.removeListener(_onAppRefresh);
    super.dispose();
  }

  void _onAppRefresh() {
    final refresh = AppRefreshService.instance;
    if (_lastRefreshTick == refresh.tick.value) return;
    _lastRefreshTick = refresh.tick.value;
    if (refresh.hasAny({
      AppRefreshTopic.auth,
      AppRefreshTopic.favorites,
      AppRefreshTopic.prestataires,
    })) {
      _loadFavoris(silent: true);
    }
  }

  Future<void> _loadFavoris({bool silent = false}) async {
    if (!AuthService.instance.isLoggedIn) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (!silent) setState(() => _loading = true);
    try {
      final response = await FavoriService.instance.getFavoris();
      if (!mounted) return;
      setState(() {
        _favoris = response.results;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (!silent) {
        setState(() => _loading = false);
        _showSnack('Impossible de charger les favoris. Réessayez.');
      }
    }
  }

  Future<void> _remove(Favori favori) async {
    setState(() => _busyId = favori.id);
    try {
      await FavoriService.instance.removeFavori(favori.id);
      if (!mounted) return;
      setState(() {
        _favoris.removeWhere((item) => item.id == favori.id);
      });
      _showSnack('Favori retiré');
    } catch (e) {
      _showSnack(userFriendlyError(e));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _openPrestataire(Favori favori) async {
    if (_openingPrestataireId != null) return;
    setState(() => _openingPrestataireId = favori.prestataire);
    try {
      final prestataire = await PrestataireService.instance.getPrestataire(
        favori.prestataire,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PrestataireDetailScreen(prestataire: prestataire),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showSnack(userFriendlyError(e));
    } finally {
      if (mounted) setState(() => _openingPrestataireId = null);
    }
  }

  void _showSnack(String message) {
    debugPrint('[Favoris] $message');
  }

  @override
  Widget build(BuildContext context) {
    if (!AuthService.instance.isLoggedIn) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: GradientBackground(
          child: SafeArea(
            child: _AccessState(
              onBack: () => Navigator.maybePop(context),
              onLogin: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => LoginScreen())),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GradientBackground(
        child: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () => _loadFavoris(),
            child: CustomScrollView(
              physics: AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                SliverToBoxAdapter(
                  child: _Header(
                    count: _favoris.length,
                    onBack: () => Navigator.maybePop(context),
                  ),
                ),
                if (_loading)
                  SliverToBoxAdapter(child: _FavorisLoading())
                else if (_favoris.isEmpty)
                  SliverToBoxAdapter(child: _EmptyFavoris())
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(20, 10, 20, 110),
                    sliver: SliverList.separated(
                      itemCount: _favoris.length,
                      separatorBuilder: (_, __) => SizedBox(height: 12),
                      itemBuilder: (_, index) {
                        final favori = _favoris[index];
                        return _FavoriCard(
                          favori: favori,
                          busy: _busyId == favori.id,
                          opening: _openingPrestataireId == favori.prestataire,
                          onTap: () => _openPrestataire(favori),
                          onRemove: () => _remove(favori),
                        );
                      },
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

class _Header extends StatelessWidget {
  _Header({required this.count, required this.onBack});
  final int count;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Row(
        children: [
          _IconBubble(icon: Icons.arrow_back_rounded, onTap: onBack),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Favoris',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  '$count prestataire${count > 1 ? 's' : ''} sauvegardé${count > 1 ? 's' : ''}',
                  style: TextStyle(color: AppColors.textHint, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FavoriCard extends StatelessWidget {
  _FavoriCard({
    required this.favori,
    required this.busy,
    required this.opening,
    required this.onTap,
    required this.onRemove,
  });

  final Favori favori;
  final bool busy;
  final bool opening;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final detail = favori.prestataireDetail;
    final title = detail?.typeService.isNotEmpty == true
        ? detail!.typeService
        : 'Prestataire #${favori.prestataire}';
    final location = [
      detail?.commune,
      detail?.ville,
    ].where((value) => value != null && value.isNotEmpty).join(', ');
    final available = detail?.isAvailable == true;

    return GestureDetector(
      onTap: opening ? null : onTap,
      child: _GlassPanel(
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradientSoft,
                borderRadius: BorderRadius.circular(17),
              ),
              child: Icon(
                Icons.design_services_outlined,
                color: Colors.white,
                size: 26,
              ),
            ),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 5),
                  if (location.isNotEmpty)
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          color: AppColors.textHint,
                          size: 14,
                        ),
                        SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.textHint,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  SizedBox(height: 8),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      color: (available ? AppColors.success : AppColors.warning)
                          .withValues(alpha: 0.11),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      available ? 'Disponible' : 'Indisponible',
                      style: TextStyle(
                        color: available
                            ? AppColors.success
                            : AppColors.warning,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: 10),
            if (opening)
              SizedBox(
                width: 40,
                height: 40,
                child: Padding(
                  padding: EdgeInsets.all(10),
                  child: CircularProgressIndicator(
                    color: AppColors.primary,
                    strokeWidth: 2.2,
                  ),
                ),
              )
            else
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: busy ? null : onRemove,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: busy
                      ? Padding(
                          padding: EdgeInsets.all(11),
                          child: CircularProgressIndicator(
                            color: AppColors.error,
                            strokeWidth: 2,
                          ),
                        )
                      : Icon(
                          Icons.favorite_rounded,
                          color: AppColors.error,
                          size: 21,
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AccessState extends StatelessWidget {
  _AccessState({required this.onBack, required this.onLogin});

  final VoidCallback onBack;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: _IconBubble(icon: Icons.arrow_back_rounded, onTap: onBack),
          ),
        ),
        Expanded(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: _GlassPanel(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.favorite_border_rounded,
                      color: AppColors.primary,
                      size: 42,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Connectez-vous',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Vos favoris sont sauvegardés dans votre compte.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    SizedBox(height: 18),
                    _PrimaryButton(
                      label: 'Connexion',
                      icon: Icons.login_rounded,
                      onTap: onLogin,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyFavoris extends StatelessWidget {
  _EmptyFavoris();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 44, 20, 110),
      child: _GlassPanel(
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
                Icons.favorite_border_rounded,
                color: AppColors.primary,
                size: 36,
              ),
            ),
            SizedBox(height: 14),
            Text(
              'Aucun favori',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 8),
            Text(
              'Ajoutez des prestataires depuis la page d’accueil.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _FavorisLoading extends StatelessWidget {
  _FavorisLoading();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Column(
        children: List.generate(
          4,
          (_) => Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: _GlassPanel(
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(17),
                    ),
                  ),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 12,
                          width: 150,
                          decoration: BoxDecoration(
                            color: AppColors.divider,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        SizedBox(height: 8),
                        Container(
                          height: 10,
                          width: 210,
                          decoration: BoxDecoration(
                            color: AppColors.divider,
                            borderRadius: BorderRadius.circular(8),
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
      ),
    );
  }
}

class _GlassPanel extends StatelessWidget {
  _GlassPanel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.glassBorder, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: AppColors.glassShadow,
                blurRadius: 18,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _IconBubble extends StatelessWidget {
  _IconBubble({required this.icon, required this.onTap});
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
          color: Colors.white.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.glassBorder, width: 1.1),
        ),
        child: Icon(icon, color: AppColors.primary, size: 20),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  _PrimaryButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
