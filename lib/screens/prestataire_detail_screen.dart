import 'dart:ui';
import 'package:flutter/material.dart';
import '../core/constants/api_constants.dart';
import '../core/models/prestataire_models.dart';
import '../core/services/auth_service.dart';
import '../core/services/prestataire_service.dart';
import '../theme/app_colors.dart';
import '../widgets/gradient_background.dart';
import 'demandes_client_screen.dart';
import 'login_screen.dart';

class PrestataireDetailScreen extends StatefulWidget {
  PrestataireDetailScreen({super.key, required this.prestataire});
  final Prestataire prestataire;

  @override
  State<PrestataireDetailScreen> createState() =>
      _PrestataireDetailScreenState();
}

class _PrestataireDetailScreenState extends State<PrestataireDetailScreen> {
  List<PrestatairePhoto> _photos = [];
  bool _loadingPhotos = true;
  String? _photoError;

  NotationsResponse? _notations;
  bool _loadingRatings = true;
  String? _ratingsError;

  @override
  void initState() {
    super.initState();
    _loadPhotos();
    _loadRatings();
  }

  Future<void> _loadPhotos() async {
    try {
      final photos = await PrestataireService.instance.getPhotos(
        widget.prestataire.id,
      );
      if (!mounted) return;
      setState(() {
        _photos = photos;
        _loadingPhotos = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _photoError = 'Impossible de charger les photos.';
        _loadingPhotos = false;
      });
    }
  }

  Future<void> _loadRatings() async {
    setState(() {
      _loadingRatings = true;
      _ratingsError = null;
    });
    try {
      final notations = await PrestataireService.instance.getProviderRatings(
        widget.prestataire.id,
      );
      if (!mounted) return;
      setState(() {
        _notations = notations;
        _loadingRatings = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _ratingsError = 'Impossible de charger les avis.';
        _loadingRatings = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.prestataire;
    final user = p.utilisateur;
    final hasPhoto = user.photoProfil != null && user.photoProfil!.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GradientBackground(
        child: SizedBox.expand(
          child: CustomScrollView(
            physics: BouncingScrollPhysics(),
            slivers: [
              // ── Hero ─────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: _HeroSection(prestataire: p, hasPhoto: hasPhoto),
              ),

              // ── Stats + À propos + Informations + contact ────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _StatsRow(prestataire: p, notations: _notations),
                      if (p.presentation.isNotEmpty) ...[
                        SizedBox(height: 20),
                        _SectionTitle('À propos'),
                        SizedBox(height: 10),
                        _GlassBlock(
                          child: Text(
                            p.presentation,
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.textSecondary,
                              height: 1.6,
                            ),
                          ),
                        ),
                      ],
                      SizedBox(height: 16),
                      _RequestServiceButton(prestataire: p),
                      SizedBox(height: 10),
                      _RateButton(prestataireId: p.id, onRated: _loadRatings),
                      SizedBox(height: 20),
                      _SectionTitle('Informations'),
                      SizedBox(height: 10),
                      _GlassBlock(
                        child: Column(
                          children: [
                            _InfoRow(
                              icon: Icons.design_services_outlined,
                              label: p.serviceNames.length > 1
                                  ? 'Services'
                                  : 'Service',
                              value: p.servicesLabel,
                            ),
                            _Divider(),
                            _InfoRow(
                              icon: Icons.location_on_outlined,
                              label: 'Localisation',
                              value: '${p.commune}, ${p.ville}',
                            ),
                            _Divider(),
                            _InfoRow(
                              icon: Icons.verified_outlined,
                              label: 'Statut',
                              value: p.estValide
                                  ? 'Validé'
                                  : 'En attente de validation',
                              valueColor: p.estValide
                                  ? AppColors.primary
                                  : AppColors.warning,
                            ),
                            _Divider(),
                            _InfoRow(
                              icon: Icons.event_available_outlined,
                              label: 'Disponibilité',
                              value: p.isAvailable
                                  ? 'Disponible'
                                  : 'Indisponible',
                              valueColor: p.isAvailable
                                  ? AppColors.success
                                  : AppColors.warning,
                            ),
                            if (user.telephone != null &&
                                user.telephone!.isNotEmpty) ...[
                              _Divider(),
                              _InfoRow(
                                icon: Icons.phone_outlined,
                                label: 'Téléphone',
                                value: user.telephone!,
                              ),
                            ],
                            if (user.email.isNotEmpty) ...[
                              _Divider(),
                              _InfoRow(
                                icon: Icons.mail_outline_rounded,
                                label: 'Email',
                                value: user.email,
                              ),
                            ],
                            if (user.dateJoined.isNotEmpty) ...[
                              _Divider(),
                              _InfoRow(
                                icon: Icons.calendar_today_outlined,
                                label: 'Membre depuis',
                                value: _formatDate(user.dateJoined),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (p.niveau.isNotEmpty ||
                          p.scoreNiveau > 0 ||
                          p.missionsReussies > 0) ...[
                        SizedBox(height: 20),
                        _SectionTitle('Performance'),
                        SizedBox(height: 10),
                        _PerformanceBlock(
                          niveau: p.niveau,
                          scoreNiveau: p.scoreNiveau,
                          noteMoyenne: p.noteMoyenne,
                          missionsReussies: p.missionsReussies,
                          tauxReponse: p.tauxReponse,
                          tauxSatisfaction: p.tauxSatisfaction,
                          tauxRespectEngagements: p.tauxRespectEngagements,
                          dateDernierCalculNiveau: p.dateDernierCalculNiveau,
                        ),
                      ],
                      SizedBox(height: 28),

                      // ── Avis section ─────────────────────────────────
                      Row(
                        children: [
                          _SectionTitle('Avis'),
                          SizedBox(width: 8),
                          if (!_loadingRatings &&
                              _ratingsError == null &&
                              _notations != null)
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primarySurface,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${_notations!.totalRatings}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                        ],
                      ),
                      SizedBox(height: 10),
                      if (_loadingRatings)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            height: 80,
                            color: Colors.white.withValues(alpha: 0.55),
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
                        )
                      else if (_ratingsError != null)
                        GestureDetector(
                          onTap: _loadRatings,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              height: 52,
                              color: Colors.white.withValues(alpha: 0.55),
                              child: Center(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.refresh_rounded,
                                      size: 16,
                                      color: AppColors.textHint,
                                    ),
                                    SizedBox(width: 6),
                                    Text(
                                      _ratingsError!,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: AppColors.textHint,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        )
                      else if (_notations == null ||
                          _notations!.ratings.isEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            height: 52,
                            color: Colors.white.withValues(alpha: 0.55),
                            child: Center(
                              child: Text(
                                'Aucun avis pour le moment.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textHint,
                                ),
                              ),
                            ),
                          ),
                        )
                      else
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _RatingBanner(notations: _notations!),
                            SizedBox(height: 10),
                            ..._notations!.ratings.map(
                              (r) => Padding(
                                padding: EdgeInsets.only(bottom: 10),
                                child: _RatingCard(notation: r),
                              ),
                            ),
                          ],
                        ),
                      SizedBox(height: 28),
                      // Photos section header
                      Row(
                        children: [
                          _SectionTitle('Photos'),
                          SizedBox(width: 8),
                          if (!_loadingPhotos && _photoError == null)
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primarySurface,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${_photos.length}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                        ],
                      ),
                      SizedBox(height: 10),
                    ],
                  ),
                ),
              ),

              // ── Photo grid (lazy, handles 200+) ──────────────────────
              if (_loadingPhotos)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        height: 120,
                        color: Colors.white.withValues(alpha: 0.55),
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
                  ),
                )
              else if (_photoError != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        height: 64,
                        color: Colors.white.withValues(alpha: 0.55),
                        child: Center(
                          child: Text(
                            _photoError!,
                            style: TextStyle(
                              color: AppColors.textHint,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              else if (_photos.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        height: 64,
                        color: Colors.white.withValues(alpha: 0.55),
                        child: Center(
                          child: Text(
                            'Aucune photo disponible',
                            style: TextStyle(
                              color: AppColors.textHint,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverGrid(
                    delegate: SliverChildBuilderDelegate((ctx, i) {
                      final photo = _photos[i];
                      return GestureDetector(
                        onTap: () => _openGallery(ctx, i),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.primarySurface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: AppColors.glassBorder,
                                width: 1,
                              ),
                            ),
                            child: Image.network(
                              ApiConstants.resolveUrl(photo.image),
                              fit: BoxFit.cover,
                              loadingBuilder: (_, child, prog) => prog == null
                                  ? child
                                  : Container(
                                      color: AppColors.primarySurface,
                                      child: Center(
                                        child: SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            color: AppColors.primary,
                                            strokeWidth: 1.8,
                                          ),
                                        ),
                                      ),
                                    ),
                              errorBuilder: (_, __, ___) => Center(
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  color: AppColors.textHint,
                                  size: 26,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }, childCount: _photos.length),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: 1,
                    ),
                  ),
                ),

              // ── Bottom spacing ────────────────────────────────────────
              SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          ),
        ),
      ),
    );
  }

  void _openGallery(BuildContext context, int initialIndex) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (_, __, ___) =>
            _FullScreenGallery(photos: _photos, initialIndex: initialIndex),
      ),
    );
  }

  static String _formatDate(String raw) {
    try {
      final dt = DateTime.parse(raw);
      final months = [
        '',
        'jan.',
        'fév.',
        'mar.',
        'avr.',
        'mai',
        'juin',
        'juil.',
        'août',
        'sep.',
        'oct.',
        'nov.',
        'déc.',
      ];
      return '${dt.day} ${months[dt.month]} ${dt.year}';
    } catch (_) {
      return raw;
    }
  }
}

/// Full-screen swipeable gallery.
class _FullScreenGallery extends StatefulWidget {
  _FullScreenGallery({required this.photos, required this.initialIndex});
  final List<PrestatairePhoto> photos;
  final int initialIndex;

  @override
  State<_FullScreenGallery> createState() => _FullScreenGalleryState();
}

class _FullScreenGalleryState extends State<_FullScreenGallery> {
  late final PageController _pageCtrl;
  late final ScrollController _thumbCtrl;
  late int _current;

  static double _thumbSize = 52;
  static double _thumbSpacing = 6;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _pageCtrl = PageController(initialPage: widget.initialIndex);
    _thumbCtrl = ScrollController(
      initialScrollOffset: _thumbOffset(widget.initialIndex),
    );
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _thumbCtrl.dispose();
    super.dispose();
  }

  double _thumbOffset(int index) {
    return (index * (_thumbSize + _thumbSpacing)) - 80;
  }

  void _goTo(int index) {
    _pageCtrl.jumpToPage(index);
    setState(() => _current = index);
    // Scroll thumbnail strip so the selected thumb is centred
    final offset = _thumbOffset(index).clamp(
      0.0,
      _thumbCtrl.hasClients
          ? _thumbCtrl.position.maxScrollExtent
          : double.infinity,
    );
    _thumbCtrl.animateTo(
      offset,
      duration: Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.photos;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Main swipeable viewer ───────────────────────────────────
          PageView.builder(
            controller: _pageCtrl,
            itemCount: photos.length,
            onPageChanged: (i) {
              setState(() => _current = i);
              final offset = _thumbOffset(i).clamp(
                0.0,
                _thumbCtrl.hasClients
                    ? _thumbCtrl.position.maxScrollExtent
                    : double.infinity,
              );
              if (_thumbCtrl.hasClients) {
                _thumbCtrl.animateTo(
                  offset,
                  duration: Duration(milliseconds: 280),
                  curve: Curves.easeOut,
                );
              }
            },
            itemBuilder: (_, i) => InteractiveViewer(
              minScale: 0.8,
              maxScale: 4,
              child: Center(
                child: Image.network(
                  ApiConstants.resolveUrl(photos[i].image),
                  fit: BoxFit.contain,
                  loadingBuilder: (_, child, prog) => prog == null
                      ? child
                      : Center(
                          child: SizedBox(
                            width: 26,
                            height: 26,
                            child: CircularProgressIndicator(
                              color: Colors.white54,
                              strokeWidth: 2,
                            ),
                          ),
                        ),
                  errorBuilder: (_, __, ___) => Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white38,
                      size: 60,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Top bar (close + counter) ───────────────────────────────
          SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  // Close
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.3),
                              width: 1.2,
                            ),
                          ),
                          child: Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Spacer(),
                  // Counter pill
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.3),
                            width: 1.2,
                          ),
                        ),
                        child: Text(
                          '${_current + 1} / ${photos.length}',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Bottom: description + thumbnail strip ──────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.80),
                    Colors.transparent,
                  ],
                  stops: [0.0, 1.0],
                ),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Description
                    if (photos[_current].description.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.fromLTRB(20, 12, 20, 8),
                        child: Text(
                          photos[_current].description,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            height: 1.4,
                          ),
                        ),
                      ),
                    SizedBox(height: 8),
                    // Thumbnail strip
                    SizedBox(
                      height: _thumbSize,
                      child: ListView.builder(
                        controller: _thumbCtrl,
                        scrollDirection: Axis.horizontal,
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        itemCount: photos.length,
                        itemBuilder: (_, i) {
                          final selected = i == _current;
                          return GestureDetector(
                            onTap: () => _goTo(i),
                            child: AnimatedContainer(
                              duration: Duration(milliseconds: 200),
                              width: _thumbSize,
                              height: _thumbSize,
                              margin: EdgeInsets.only(
                                right: i < photos.length - 1
                                    ? _thumbSpacing
                                    : 0,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: selected
                                      ? AppColors.primary
                                      : Colors.white.withValues(alpha: 0.25),
                                  width: selected ? 2.5 : 1.2,
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  ApiConstants.resolveUrl(photos[i].image),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    color: Colors.white12,
                                    child: Icon(
                                      Icons.broken_image_outlined,
                                      color: Colors.white38,
                                      size: 18,
                                    ),
                                  ),
                                ),
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
        ],
      ),
    );
  }
}

// ── Hero section ──────────────────────────────────────────────────────────────

class _HeroSection extends StatelessWidget {
  _HeroSection({required this.prestataire, required this.hasPhoto});
  final Prestataire prestataire;
  final bool hasPhoto;

  @override
  Widget build(BuildContext context) {
    final user = prestataire.utilisateur;
    return Stack(
      children: [
        // Background photo / gradient
        Container(
          height: 260,
          decoration: BoxDecoration(gradient: AppColors.primaryGradient),
          child: hasPhoto
              ? ClipRect(
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                    child: Image.network(
                      ApiConstants.resolveUrl(user.photoProfil!),
                      width: double.infinity,
                      height: 260,
                      fit: BoxFit.cover,
                      color: Colors.black.withValues(alpha: 0.15),
                      colorBlendMode: BlendMode.darken,
                      errorBuilder: (_, __, ___) => SizedBox.shrink(),
                    ),
                  ),
                )
              : null,
        ),

        // Frosted gradient overlay at bottom
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            height: 100,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  AppColors.background.withValues(alpha: 0.95),
                ],
              ),
            ),
          ),
        ),

        // Safe area + back
        SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.28),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.45),
                            width: 1.2,
                          ),
                        ),
                        child: Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Avatar + name card pinned at bottom of hero
        Positioned(
          left: 20,
          right: 20,
          bottom: 0,
          child: Row(
            children: [
              // Avatar circle
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppColors.primaryGradient,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: hasPhoto
                      ? Image.network(
                          ApiConstants.resolveUrl(user.photoProfil!),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              _InitialAvatar(name: user.displayName),
                        )
                      : _InitialAvatar(name: user.displayName),
                ),
              ),
              SizedBox(width: 14),

              // Name + type
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.30),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.15),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  user.displayName,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (prestataire.estValide) ...[
                                SizedBox(width: 6),
                                Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: AppColors.primaryGradient,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.verified_rounded,
                                        color: Colors.white,
                                        size: 11,
                                      ),
                                      SizedBox(width: 3),
                                      Text(
                                        'Validé',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              if (prestataire.isAvailable) ...[
                                SizedBox(width: 6),
                                Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.success.withValues(
                                      alpha: 0.18,
                                    ),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.circle,
                                        color: AppColors.success,
                                        size: 8,
                                      ),
                                      SizedBox(width: 5),
                                      Text(
                                        'Disponible',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.success,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                          SizedBox(height: 3),
                          Text(
                            prestataire.servicesLabel,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                          SizedBox(height: 3),
                          Row(
                            children: [
                              Icon(
                                Icons.location_on_outlined,
                                size: 12,
                                color: Colors.white.withValues(alpha: 0.75),
                              ),
                              SizedBox(width: 3),
                              Flexible(
                                child: Text(
                                  '${prestataire.commune}, ${prestataire.ville}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white.withValues(alpha: 0.75),
                                  ),
                                  overflow: TextOverflow.ellipsis,
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
            ],
          ),
        ),
      ],
    );
  }
}

// ── Stats row ─────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  _StatsRow({required this.prestataire, this.notations});
  final Prestataire prestataire;
  final NotationsResponse? notations;

  @override
  Widget build(BuildContext context) {
    final averageRating = notations?.averageRating ?? prestataire.moyenneNotes;
    final totalRatings =
        notations?.totalRatings ?? prestataire.nombreCommentaires;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.glassBorder, width: 1.3),
            boxShadow: [
              BoxShadow(
                color: AppColors.glassShadow,
                blurRadius: 16,
                offset: Offset(0, 4),
              ),
            ],
          ),
          padding: EdgeInsets.symmetric(vertical: 18),
          child: Row(
            children: [
              _StatItem(
                icon: Icons.photo_library_outlined,
                value: '${prestataire.nombrePhotos}',
                label: 'Photos',
              ),
              _StatDivider(),
              _StatItem(
                icon: Icons.star_rounded,
                value: averageRating != null && totalRatings > 0
                    ? averageRating.toStringAsFixed(1)
                    : '—',
                label: 'Note',
                valueColor: AppColors.warning,
              ),
              _StatDivider(),
              _StatItem(
                icon: Icons.chat_bubble_outline_rounded,
                value: '$totalRatings',
                label: 'Avis',
              ),
              _StatDivider(),
              _StatItem(
                icon: prestataire.estValide
                    ? Icons.verified_rounded
                    : Icons.hourglass_top_rounded,
                value: prestataire.estValide ? 'Oui' : 'Non',
                label: 'Validé',
                valueColor: prestataire.estValide
                    ? AppColors.primary
                    : AppColors.warning,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  _StatItem({
    required this.icon,
    required this.value,
    required this.label,
    this.valueColor,
  });
  final IconData icon;
  final String value;
  final String label;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: valueColor ?? AppColors.primary, size: 22),
          SizedBox(height: 5),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: valueColor ?? AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textHint,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _PerformanceBlock extends StatelessWidget {
  _PerformanceBlock({
    required this.niveau,
    required this.scoreNiveau,
    required this.noteMoyenne,
    required this.missionsReussies,
    required this.tauxReponse,
    required this.tauxSatisfaction,
    required this.tauxRespectEngagements,
    required this.dateDernierCalculNiveau,
  });

  final String niveau;
  final int scoreNiveau;
  final double? noteMoyenne;
  final int missionsReussies;
  final int tauxReponse;
  final int tauxSatisfaction;
  final int tauxRespectEngagements;
  final String? dateDernierCalculNiveau;

  @override
  Widget build(BuildContext context) {
    final level = niveau.isEmpty
        ? 'Non calculé'
        : '${niveau[0].toUpperCase()}${niveau.substring(1)}';
    return _GlassBlock(
      child: Column(
        children: [
          _InfoRow(
            icon: Icons.workspace_premium_rounded,
            label: 'Niveau',
            value: '$level • $scoreNiveau pts',
            valueColor: AppColors.primary,
          ),
          _Divider(),
          _InfoRow(
            icon: Icons.star_rounded,
            label: 'Note moyenne',
            value: noteMoyenne == null ? '—' : noteMoyenne!.toStringAsFixed(1),
            valueColor: AppColors.warning,
          ),
          _Divider(),
          _InfoRow(
            icon: Icons.task_alt_rounded,
            label: 'Missions réussies',
            value: '$missionsReussies',
          ),
          _Divider(),
          _InfoRow(
            icon: Icons.reply_all_rounded,
            label: 'Taux de réponse',
            value: '$tauxReponse%',
          ),
          _Divider(),
          _InfoRow(
            icon: Icons.sentiment_satisfied_alt_rounded,
            label: 'Satisfaction',
            value: '$tauxSatisfaction%',
          ),
          _Divider(),
          _InfoRow(
            icon: Icons.handshake_rounded,
            label: 'Respect engagements',
            value: '$tauxRespectEngagements%',
          ),
          if (dateDernierCalculNiveau != null &&
              dateDernierCalculNiveau!.isNotEmpty) ...[
            _Divider(),
            _InfoRow(
              icon: Icons.update_rounded,
              label: 'Dernier calcul',
              value: _formatPerformanceDate(dateDernierCalculNiveau!),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 42, color: AppColors.divider);
  }
}

// ── Reusable layout widgets ───────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  _SectionTitle(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w800,
        color: AppColors.textPrimary,
        letterSpacing: 0.2,
      ),
    );
  }
}

class _GlassBlock extends StatelessWidget {
  _GlassBlock({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.glassBorder, width: 1.3),
            boxShadow: [
              BoxShadow(
                color: AppColors.glassShadow,
                blurRadius: 16,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primarySurface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.primary, size: 17),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textHint,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: valueColor ?? AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  _Divider();
  @override
  Widget build(BuildContext context) =>
      Divider(color: AppColors.divider, height: 1);
}

class _RequestServiceButton extends StatelessWidget {
  _RequestServiceButton({required this.prestataire});
  final Prestataire prestataire;

  void _open(BuildContext context) {
    if (!AuthService.instance.isLoggedIn) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => LoginScreen()));
      return;
    }
    final currentUserId = AuthService.instance.currentUser?.userId;
    if (currentUserId == prestataire.utilisateur.id) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DemandesClientScreen(
          initialPrestataire: prestataire,
          openCreateOnStart: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabled = prestataire.isAvailable && prestataire.estValide;
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        gradient: enabled
            ? AppColors.primaryGradient
            : LinearGradient(
                colors: [
                  AppColors.textHint.withValues(alpha: 0.55),
                  AppColors.textHint.withValues(alpha: 0.35),
                ],
              ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.35),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: enabled ? 0.36 : 0.08),
            blurRadius: 20,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: enabled ? () => _open(context) : null,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.assignment_add, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Text(
                enabled ? 'Demander ce service' : 'Demande indisponible',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Rating widgets ────────────────────────────────────────────────────────────

class _RatingBanner extends StatelessWidget {
  _RatingBanner({required this.notations});
  final NotationsResponse notations;

  @override
  Widget build(BuildContext context) {
    final avg = notations.averageRating;
    final filled = avg.floor();
    final half = (avg - filled) >= 0.5;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.glassBorder, width: 1.2),
          ),
          child: Row(
            children: [
              Text(
                avg.toStringAsFixed(1),
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  color: AppColors.warning,
                  height: 1,
                ),
              ),
              SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: List.generate(5, (i) {
                      IconData ic;
                      if (i < filled) {
                        ic = Icons.star_rounded;
                      } else if (i == filled && half) {
                        ic = Icons.star_half_rounded;
                      } else {
                        ic = Icons.star_border_rounded;
                      }
                      return Icon(ic, color: AppColors.warning, size: 20);
                    }),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '${notations.totalRatings} avis',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textHint,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RatingCard extends StatelessWidget {
  _RatingCard({required this.notation});
  final Notation notation;

  static String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/'
          '${dt.month.toString().padLeft(2, '0')}/'
          '${dt.year}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = notation.utilisateur;
    final hasPhoto = u.photoProfil != null && u.photoProfil!.isNotEmpty;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.glassBorder, width: 1.2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row: avatar + name + date
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.primarySurface,
                    backgroundImage: hasPhoto
                        ? NetworkImage(ApiConstants.resolveUrl(u.photoProfil!))
                        : null,
                    child: hasPhoto
                        ? null
                        : Text(
                            u.displayName.isNotEmpty
                                ? u.displayName[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          u.displayName,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          _formatDate(notation.dateCreation),
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textHint,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Stars
                  Row(
                    children: List.generate(
                      5,
                      (i) => Icon(
                        i < notation.note
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        color: AppColors.warning,
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ),
              // Avis text
              if (notation.avis.isNotEmpty) ...[
                SizedBox(height: 10),
                Text(
                  notation.avis,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Rate button ───────────────────────────────────────────────────────────────

class _RateButton extends StatelessWidget {
  _RateButton({required this.prestataireId, this.onRated});
  final int prestataireId;
  final VoidCallback? onRated;

  void _open(BuildContext ctx) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _RatingSheet(prestataireId: prestataireId, onRated: onRated),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 54,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.4),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.glassShadow,
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _open(context),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.star_rounded, color: AppColors.warning, size: 20),
              SizedBox(width: 10),
              Text(
                'Laisser un avis',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Rating bottom sheet ───────────────────────────────────────────────────────

class _RatingSheet extends StatefulWidget {
  _RatingSheet({required this.prestataireId, this.onRated});
  final int prestataireId;
  final VoidCallback? onRated;

  @override
  State<_RatingSheet> createState() => _RatingSheetState();
}

class _RatingSheetState extends State<_RatingSheet> {
  int _note = 0;
  bool _submitting = false;
  final _avisCtrl = TextEditingController();

  static final _labels = [
    '',
    'Mauvais',
    'Insuffisant',
    'Correct',
    'Bien',
    'Excellent',
  ];

  @override
  void dispose() {
    _avisCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_note == 0) {
      return;
    }
    if (AuthService.instance.currentUser == null) {
      return;
    }
    setState(() => _submitting = true);
    try {
      await PrestataireService.instance.rateProvider(
        prestataireId: widget.prestataireId,
        note: _note,
        avis: _avisCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onRated?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      debugPrint('[Rating] error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
      decoration: BoxDecoration(
        color: Color(0xFFF6F8FA),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textHint.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          SizedBox(height: 18),

          // Title
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  Icons.star_rounded,
                  color: AppColors.warning,
                  size: 20,
                ),
              ),
              SizedBox(width: 10),
              Text(
                'Évaluer le prestataire',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          SizedBox(height: 24),

          // Star selector
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final star = i + 1;
              return GestureDetector(
                onTap: _submitting ? null : () => setState(() => _note = star),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(
                    star <= _note
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    color: star <= _note
                        ? AppColors.warning
                        : AppColors.textHint.withValues(alpha: 0.5),
                    size: 42,
                  ),
                ),
              );
            }),
          ),

          // Label for selected note
          SizedBox(height: 8),
          AnimatedSwitcher(
            duration: Duration(milliseconds: 180),
            child: _note > 0
                ? Text(
                    _labels[_note],
                    key: ValueKey(_note),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.warning,
                    ),
                  )
                : Text(
                    'Touchez une étoile',
                    key: ValueKey(0),
                    style: TextStyle(fontSize: 13, color: AppColors.textHint),
                  ),
          ),

          SizedBox(height: 20),

          // Avis text field
          TextField(
            controller: _avisCtrl,
            enabled: !_submitting,
            maxLines: 3,
            minLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Partagez votre expérience (optionnel)',
              hintStyle: TextStyle(color: AppColors.textHint, fontSize: 13),
              filled: true,
              fillColor: Colors.white,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: AppColors.glassBorder,
                  width: 1.2,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: AppColors.glassBorder,
                  width: 1.2,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: AppColors.primary, width: 1.6),
              ),
            ),
            style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
          ),

          SizedBox(height: 20),

          // Submit
          SizedBox(
            width: double.infinity,
            height: 52,
            child: GestureDetector(
              onTap: _submitting ? null : _submit,
              child: Container(
                decoration: BoxDecoration(
                  gradient: _submitting ? null : AppColors.primaryGradient,
                  color: _submitting
                      ? AppColors.textHint.withValues(alpha: 0.2)
                      : null,
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: _submitting
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.4,
                        ),
                      )
                    : Text(
                        'Envoyer mon avis',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
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

// ── Initial avatar fallback ───────────────────────────────────────────────────

class _InitialAvatar extends StatelessWidget {
  _InitialAvatar({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final letter = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    return Center(
      child: Text(
        letter,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 28,
        ),
      ),
    );
  }
}

String _formatPerformanceDate(String raw) {
  final dt = DateTime.tryParse(raw);
  if (dt == null) return raw;
  final local = dt.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}/'
      '${local.year}';
}
