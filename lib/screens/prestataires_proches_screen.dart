import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/constants/api_constants.dart';
import '../core/models/prestataire_models.dart';
import '../core/services/location_service.dart';
import '../core/services/prestataire_service.dart';
import '../core/utils/user_friendly_error.dart';
import '../theme/app_colors.dart';
import '../widgets/glass_button.dart';
import '../widgets/gradient_background.dart';
import 'prestataire_detail_screen.dart';

/// Prestataires autour du client, placés sur des cercles de distance.
///
/// Le serveur ne communique jamais la position des prestataires, seulement
/// leur distance : le rayon est réel, l'angle autour du centre est indicatif.
class PrestatairesProchesScreen extends StatefulWidget {
  PrestatairesProchesScreen({super.key});

  @override
  State<PrestatairesProchesScreen> createState() =>
      _PrestatairesProchesScreenState();
}

class _PrestatairesProchesScreenState extends State<PrestatairesProchesScreen>
    with SingleTickerProviderStateMixin {
  static const _rayonsKm = [1.0, 5.0, 10.0, 25.0];

  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: Duration(seconds: 4),
  )..repeat();

  List<Prestataire> _prestataires = [];
  double _rayonKm = 5;
  bool _loading = true;
  bool _positionIndisponible = false;
  String? _error;
  Prestataire? _selection;

  List<Prestataire> get _dansLeRayon => _prestataires
      .where((p) => p.distanceKm! <= _rayonKm)
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _positionIndisponible = false;
    });
    final position = await LocationService.instance.currentPosition();
    if (!mounted) return;
    if (position == null) {
      setState(() {
        _loading = false;
        _positionIndisponible = true;
      });
      return;
    }
    try {
      final page = await PrestataireService.instance.getPrestataires(
        pageSize: 100,
      );
      if (!mounted) return;
      final proches = page.results.where((p) => p.distanceKm != null).toList()
        ..sort((a, b) => a.distanceKm!.compareTo(b.distanceKm!));
      setState(() {
        _prestataires = proches;
        _loading = false;
        // Ouvre sur le plus petit rayon qui contient au moins un prestataire.
        _rayonKm = _rayonsKm.firstWhere(
          (r) => proches.any((p) => p.distanceKm! <= r),
          orElse: () => _rayonsKm.last,
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = userFriendlyError(
          e,
          fallback: 'Impossible de charger les prestataires proches.',
        );
      });
    }
  }

  void _open(Prestataire prestataire) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PrestataireDetailScreen(prestataire: prestataire),
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
              Padding(
                padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Row(
                  children: [
                    GlassIconButton(
                      icon: Icons.arrow_back_rounded,
                      onPressed: () => Navigator.maybePop(context),
                    ),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Autour de moi',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            _loading
                                ? 'Recherche des prestataires…'
                                : '${_dansLeRayon.length} prestataire${_dansLeRayon.length > 1 ? 's' : ''} à moins de ${_formatRayon(_rayonKm)}',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    GlassIconButton(
                      icon: Icons.refresh_rounded,
                      onPressed: _loading ? null : _load,
                    ),
                  ],
                ),
              ),
              Expanded(child: _buildBody()),
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
    if (_positionIndisponible) {
      return _Message(
        icon: Icons.location_off_rounded,
        title: 'Localisation indisponible',
        text:
            'Activez la localisation de votre téléphone et autorisez Zwacop à y accéder pour voir les prestataires autour de vous.',
        actionLabel: 'Réessayer',
        onAction: _load,
      );
    }
    if (_error != null) {
      return _Message(
        icon: Icons.wifi_off_rounded,
        title: 'Chargement impossible',
        text: _error!,
        actionLabel: 'Réessayer',
        onAction: _load,
      );
    }
    if (_prestataires.isEmpty) {
      return _Message(
        icon: Icons.radar_rounded,
        title: 'Aucun prestataire localisé',
        text:
            'Aucun prestataire n’a encore partagé sa position près de vous. Revenez un peu plus tard.',
      );
    }

    final visibles = _dansLeRayon;
    return ListView(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 40),
      children: [
        _RayonSelector(
          rayons: _rayonsKm,
          selected: _rayonKm,
          onSelected: (r) => setState(() {
            _rayonKm = r;
            if (_selection != null && _selection!.distanceKm! > r) {
              _selection = null;
            }
          }),
        ),
        SizedBox(height: 14),
        AspectRatio(
          aspectRatio: 1,
          child: LayoutBuilder(
            builder: (context, constraints) => _Radar(
              size: constraints.maxWidth,
              rayonKm: _rayonKm,
              prestataires: visibles,
              selection: _selection,
              sweep: _sweep,
              onTap: (p) => setState(
                () => _selection = _selection?.id == p.id ? null : p,
              ),
            ),
          ),
        ),
        SizedBox(height: 8),
        Text(
          'La distance est réelle ; la position autour du cercle est indicative pour protéger l’adresse des prestataires.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textHint, fontSize: 11),
        ),
        if (_selection != null) ...[
          SizedBox(height: 14),
          _PrestataireTile(
            prestataire: _selection!,
            highlighted: true,
            onTap: () => _open(_selection!),
          ),
        ],
        SizedBox(height: 20),
        Text(
          'Du plus proche au plus loin',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: 10),
        if (visibles.isEmpty)
          Text(
            'Aucun prestataire dans ce rayon. Élargissez la zone.',
            style: TextStyle(color: AppColors.textSecondary),
          )
        else
          for (final p in visibles) ...[
            _PrestataireTile(prestataire: p, onTap: () => _open(p)),
            SizedBox(height: 10),
          ],
      ],
    );
  }
}

String _formatRayon(double km) => '${km.round()} km';

class _RayonSelector extends StatelessWidget {
  _RayonSelector({
    required this.rayons,
    required this.selected,
    required this.onSelected,
  });

  final List<double> rayons;
  final double selected;
  final ValueChanged<double> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final r in rayons) ...[
          Expanded(
            child: GestureDetector(
              onTap: () => onSelected(r),
              child: AnimatedContainer(
                duration: Duration(milliseconds: 200),
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: r == selected ? AppColors.primaryGradient : null,
                  color: r == selected
                      ? null
                      : Colors.white.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _formatRayon(r),
                  style: TextStyle(
                    color: r == selected ? Colors.white : AppColors.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
          if (r != rayons.last) SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _Radar extends StatelessWidget {
  _Radar({
    required this.size,
    required this.rayonKm,
    required this.prestataires,
    required this.selection,
    required this.sweep,
    required this.onTap,
  });

  final double size;
  final double rayonKm;
  final List<Prestataire> prestataires;
  final Prestataire? selection;
  final Animation<double> sweep;
  final ValueChanged<Prestataire> onTap;

  static const _avatar = 38.0;

  /// Angle stable par prestataire (dérivé de son id), pour qu'il ne saute
  /// pas d'un rechargement à l'autre.
  double _angle(Prestataire p) => ((p.id * 137.508) % 360) * math.pi / 180;

  @override
  Widget build(BuildContext context) {
    final center = size / 2;
    final rMax = center - _avatar / 2 - 4;
    return Stack(
      children: [
        Positioned.fill(
          child: AnimatedBuilder(
            animation: sweep,
            builder: (_, __) => CustomPaint(
              painter: _RadarPainter(
                rayonKm: rayonKm,
                sweep: sweep.value,
                labelStyle: TextStyle(
                  color: AppColors.textHint,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
        // Le client, au centre.
        Positioned(
          left: center - 9,
          top: center - 9,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.4),
                  blurRadius: 10,
                ),
              ],
            ),
          ),
        ),
        for (final p in prestataires) _positioned(p, center, rMax),
      ],
    );
  }

  Widget _positioned(Prestataire p, double center, double rMax) {
    // Rayon minimal pour ne pas recouvrir le point central.
    final r = math.max(24.0, (p.distanceKm! / rayonKm).clamp(0.0, 1.0) * rMax);
    final a = _angle(p);
    final selected = selection?.id == p.id;
    final photo = p.utilisateur.photoProfil;
    return Positioned(
      left: center + r * math.cos(a) - _avatar / 2,
      top: center + r * math.sin(a) - _avatar / 2,
      child: GestureDetector(
        onTap: () => onTap(p),
        child: AnimatedScale(
          scale: selected ? 1.25 : 1,
          duration: Duration(milliseconds: 200),
          child: Container(
            width: _avatar,
            height: _avatar,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primarySurface,
              border: Border.all(
                color: selected
                    ? AppColors.accent
                    : p.isAvailable
                    ? AppColors.primary
                    : AppColors.textHint,
                width: selected ? 3 : 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
              image: photo != null && photo.isNotEmpty
                  ? DecorationImage(
                      image: NetworkImage(ApiConstants.resolveUrl(photo)),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: photo != null && photo.isNotEmpty
                ? null
                : Icon(
                    Icons.person_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
          ),
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.rayonKm,
    required this.sweep,
    required this.labelStyle,
  });

  final double rayonKm;
  final double sweep;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final rMax = size.width / 2 - 23;

    canvas.drawCircle(
      center,
      rMax,
      Paint()..color = Colors.white.withValues(alpha: 0.55),
    );

    // Balayage rotatif.
    final start = sweep * 2 * math.pi;
    canvas.drawCircle(
      center,
      rMax,
      Paint()
        ..shader = SweepGradient(
          startAngle: 0,
          endAngle: math.pi / 2,
          colors: [
            AppColors.primary.withValues(alpha: 0),
            AppColors.primary.withValues(alpha: 0.18),
          ],
          transform: GradientRotation(start),
        ).createShader(Rect.fromCircle(center: center, radius: rMax)),
    );

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = AppColors.primary.withValues(alpha: 0.22);
    for (var i = 1; i <= 4; i++) {
      final r = rMax * i / 4;
      canvas.drawCircle(center, r, ring);
      final km = rayonKm * i / 4;
      final label = TextPainter(
        text: TextSpan(
          text: km < 1
              ? '${(km * 1000).round()} m'
              : '${km % 1 == 0 ? km.round() : km.toStringAsFixed(1).replaceAll('.', ',')} km',
          style: labelStyle,
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(
        canvas,
        Offset(center.dx + 4, center.dy - r - label.height - 1),
      );
    }
  }

  @override
  bool shouldRepaint(_RadarPainter old) =>
      old.sweep != sweep || old.rayonKm != rayonKm;
}

class _PrestataireTile extends StatelessWidget {
  _PrestataireTile({
    required this.prestataire,
    required this.onTap,
    this.highlighted = false,
  });

  final Prestataire prestataire;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final p = prestataire;
    final photo = p.utilisateur.photoProfil;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: highlighted ? AppColors.accent : AppColors.glassBorder,
            width: highlighted ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: AppColors.primarySurface,
              backgroundImage: photo != null && photo.isNotEmpty
                  ? NetworkImage(ApiConstants.resolveUrl(photo))
                  : null,
              child: photo != null && photo.isNotEmpty
                  ? null
                  : Icon(Icons.person_rounded, color: AppColors.primary),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.utilisateur.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    p.servicesLabel.isEmpty ? p.typeService : p.servicesLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.near_me_rounded,
                      size: 12,
                      color: AppColors.textHint,
                    ),
                    SizedBox(width: 3),
                    Text(
                      formatDistance(p.distanceKm!),
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 4),
                Text(
                  p.isAvailable ? 'Disponible' : 'Indisponible',
                  style: TextStyle(
                    color: p.isAvailable
                        ? AppColors.primary
                        : AppColors.textHint,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  _Message({
    required this.icon,
    required this.title,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppColors.primary),
            SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 6),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, height: 1.45),
            ),
            if (actionLabel != null && onAction != null) ...[
              SizedBox(height: 18),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
