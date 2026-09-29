import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../core/models/abonnement_models.dart';
import '../core/models/prestataire_models.dart';
import '../core/services/app_refresh_service.dart';
import '../core/services/auth_service.dart';
import '../core/services/prestataire_service.dart';
import '../core/services/user_realtime_service.dart';
import '../core/utils/user_friendly_error.dart';
import '../core/constants/api_constants.dart';
import '../core/constants/locations.dart';
import '../theme/app_colors.dart';
import '../widgets/gradient_background.dart';

class ProfileScreen extends StatefulWidget {
  ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with WidgetsBindingObserver {
  MonProfilPrestataire? _monProfil;
  bool _loadingProfil = false;
  String? _profilError;
  bool _uploadingProfilePhoto = false;

  AbonnementStatut? _abonnement;
  bool _loadingAbonnement = false;
  String? _abonnementError;
  int _abonnementRequestId = 0;
  int _lastRefreshTick = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppRefreshService.instance.tick.addListener(_onAppRefresh);
    if (AuthService.instance.currentUser?.estPrestataire == true) {
      _loadMonProfil();
      _loadAbonnement();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        AuthService.instance.currentUser?.estPrestataire == true) {
      _loadAbonnement();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppRefreshService.instance.tick.removeListener(_onAppRefresh);
    super.dispose();
  }

  void _onAppRefresh() {
    final refresh = AppRefreshService.instance;
    if (_lastRefreshTick == refresh.tick.value) return;
    _lastRefreshTick = refresh.tick.value;
    if (!mounted) return;

    if (refresh.hasAny({
      AppRefreshTopic.auth,
      AppRefreshTopic.profile,
      AppRefreshTopic.prestataires,
      AppRefreshTopic.ratings,
    })) {
      if (AuthService.instance.currentUser?.estPrestataire == true) {
        _loadMonProfil(silent: true);
      }
    }
    if (refresh.hasAny({
      AppRefreshTopic.auth,
      AppRefreshTopic.abonnement,
      AppRefreshTopic.profile,
    })) {
      if (AuthService.instance.currentUser?.estPrestataire == true) {
        _loadAbonnement(silent: true);
      }
    }
  }

  Future<void> _loadMonProfil({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loadingProfil = true;
        _profilError = null;
      });
    }
    try {
      final profil = await PrestataireService.instance.getMonProfil();
      if (!mounted) return;
      setState(() {
        _monProfil = profil;
        _loadingProfil = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _profilError = 'Impossible de charger votre profil prestataire.';
        _loadingProfil = false;
      });
    }
  }

  Future<void> _loadAbonnement({bool silent = false}) async {
    final requestId = ++_abonnementRequestId;
    if (!silent) {
      setState(() {
        _loadingAbonnement = true;
        _abonnementError = null;
      });
    }
    try {
      final ab = await AuthService.instance.getMonAbonnement();
      if (!mounted || requestId != _abonnementRequestId) return;
      setState(() {
        _abonnement = ab;
        _loadingAbonnement = false;
      });
    } catch (_) {
      if (!mounted || requestId != _abonnementRequestId) return;
      setState(() {
        _abonnementError = 'Impossible de charger l’abonnement.';
        _loadingAbonnement = false;
      });
    }
  }

  Future<void> _pickProfilePhoto() async {
    if (_uploadingProfilePhoto) return;
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 82,
        maxWidth: 1200,
      );
      if (picked == null) return;

      setState(() => _uploadingProfilePhoto = true);
      final bytes = await picked.readAsBytes();
      final result = await AuthService.instance.uploadProfilePhoto(
        bytes: bytes,
        filename: picked.name.isNotEmpty ? picked.name : 'photo_profil.jpg',
      );
      if (!mounted) return;
      setState(() => _uploadingProfilePhoto = false);
      debugPrint(
        '[Profile] ${result['message'] as String? ?? 'Photo de profil mise à jour.'}',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploadingProfilePhoto = false);
      debugPrint('[Profile] upload profile photo error: $e');
    }
  }

  void _showSouscriptionSheet(BuildContext ctx) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PaiementAbonnementSheet(
        abonnement: _abonnement,
        onSuccess: () {
          if (mounted) _loadAbonnement();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;
    if (user == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pop();
      });
      return SizedBox.shrink();
    }

    final initials = _initial(user.username);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GradientBackground(
        child: SizedBox.expand(
          child: SafeArea(
            child: SingleChildScrollView(
              physics: BouncingScrollPhysics(),
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // back button
                  Align(
                    alignment: Alignment.centerLeft,
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.glassBorder,
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.glassShadow,
                              blurRadius: 12,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: AppColors.textPrimary,
                          size: 16,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 28),

                  // ── Avatar ──────────────────────────────────────────────
                  GestureDetector(
                    onTap: _uploadingProfilePhoto ? null : _pickProfilePhoto,
                    child: SizedBox(
                      width: 104,
                      height: 104,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 90,
                            height: 90,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: AppColors.primaryGradient,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.38,
                                  ),
                                  blurRadius: 32,
                                  spreadRadius: 4,
                                  offset: Offset(0, 8),
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child:
                                  user.photo != null && user.photo!.isNotEmpty
                                  ? Image.network(
                                      ApiConstants.resolveUrl(user.photo!),
                                      fit: BoxFit.cover,
                                      width: 90,
                                      height: 90,
                                      errorBuilder: (_, __, ___) =>
                                          _AvatarInitial(initial: initials),
                                      loadingBuilder: (_, child, progress) =>
                                          progress == null
                                          ? child
                                          : Center(
                                              child: SizedBox(
                                                width: 28,
                                                height: 28,
                                                child:
                                                    CircularProgressIndicator(
                                                      color: Colors.white,
                                                      strokeWidth: 2,
                                                    ),
                                              ),
                                            ),
                                    )
                                  : _AvatarInitial(initial: initials),
                            ),
                          ),
                          Positioned(
                            right: 8,
                            bottom: 10,
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                gradient: AppColors.primaryGradient,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 3,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.28,
                                    ),
                                    blurRadius: 12,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: _uploadingProfilePhoto
                                  ? Padding(
                                      padding: EdgeInsets.all(8),
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Icon(
                                      Icons.photo_camera_rounded,
                                      color: Colors.white,
                                      size: 17,
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: 20),

                  // ── Username ─────────────────────────────────────────────
                  Text(
                    user.username,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.4,
                    ),
                  ),

                  SizedBox(height: 5),

                  // ── Email ────────────────────────────────────────────────
                  Text(
                    user.email,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w400,
                    ),
                  ),

                  SizedBox(height: 12),

                  // ── Role badge ───────────────────────────────────────────
                  if (user.estPrestataire)
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.28),
                            blurRadius: 12,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.verified_rounded,
                            color: Colors.white,
                            size: 14,
                          ),
                          SizedBox(width: 5),
                          Text(
                            'Prestataire',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primarySurface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppColors.divider,
                          width: 1.2,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.person_outline_rounded,
                            color: AppColors.textSecondary,
                            size: 14,
                          ),
                          SizedBox(width: 5),
                          Text(
                            'Client',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),

                  SizedBox(height: 30),

                  // ── Info card ───────────────────────────────────────────
                  ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.78),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: AppColors.glassBorder,
                            width: 1.4,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.glassShadow,
                              blurRadius: 32,
                              offset: Offset(0, 10),
                            ),
                            BoxShadow(
                              color: Colors.white.withValues(alpha: 0.55),
                              blurRadius: 8,
                              spreadRadius: -2,
                              offset: Offset(0, -2),
                            ),
                          ],
                        ),
                        padding: EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 8,
                        ),
                        child: Column(
                          children: [
                            _InfoRow(
                              icon: Icons.alternate_email_rounded,
                              label: "Nom d'utilisateur",
                              value: user.username,
                            ),
                            if ((user.firstName ?? '').isNotEmpty ||
                                (user.lastName ?? '').isNotEmpty) ...[
                              _RowDivider(),
                              _InfoRow(
                                icon: Icons.person_outline_rounded,
                                label: 'Prénom & Nom',
                                value:
                                    '${user.firstName ?? ''} ${user.lastName ?? ''}'
                                        .trim(),
                              ),
                            ],
                            _RowDivider(),
                            _InfoRow(
                              icon: Icons.mail_outline_rounded,
                              label: 'Adresse e-mail',
                              value: user.email,
                            ),
                            if ((user.telephone ?? '').isNotEmpty) ...[
                              _RowDivider(),
                              _InfoRow(
                                icon: Icons.phone_outlined,
                                label: 'Téléphone',
                                value: user.telephone!,
                              ),
                            ],
                            _RowDivider(),
                            _InfoRow(
                              icon: Icons.badge_outlined,
                              label: 'Type de compte',
                              value: user.estPrestataire
                                  ? 'Prestataire'
                                  : 'Client',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  SizedBox(height: 28),

                  // ── Become provider CTA ──────────────────────────────────
                  if (!user.estPrestataire) ...[
                    GestureDetector(
                      onTap: () => _showBecomeProviderSheet(context),
                      child: Container(
                        width: double.infinity,
                        padding: EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.28),
                              blurRadius: 16,
                              offset: Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.work_outline_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                            SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Devenir prestataire',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                    ),
                                  ),
                                  SizedBox(height: 3),
                                  Text(
                                    'Proposez vos services et développez votre activité',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward_ios_rounded,
                              color: Colors.white70,
                              size: 14,
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 28),
                  ],

                  // ── Prestataire section ──────────────────────────────────
                  if (user.estPrestataire) ...[
                    _PrestataireProfileSection(
                      loading: _loadingProfil,
                      error: _profilError,
                      profil: _monProfil,
                      onRetry: _loadMonProfil,
                      onEdit: () => _showEditPrestataireSheet(context),
                      onViewPhotos: () => _openPhotoGallery(context),
                      onAddPhoto: () => _showAddPhotosSheet(context),
                    ),
                    SizedBox(height: 20),
                    _MesAvisPrestataireCard(
                      enabled: _monProfil != null,
                      onTap: _monProfil == null
                          ? null
                          : () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => MesAvisClientsScreen(
                                  prestataireId: _monProfil!.id,
                                ),
                              ),
                            ),
                    ),
                    SizedBox(height: 20),
                    _AbonnementCard(
                      loading: _loadingAbonnement,
                      error: _abonnementError,
                      abonnement: _abonnement,
                      onRetry: _loadAbonnement,
                      onSouscrire: () => _showSouscriptionSheet(context),
                    ),
                    SizedBox(height: 28),
                  ],

                  // ── Edit profile button ───────────────────────────────────
                  GestureDetector(
                    onTap: () => _showEditProfileSheet(context),
                    child: Container(
                      width: double.infinity,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.78),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.45),
                          width: 1.4,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.glassShadow,
                            blurRadius: 14,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: AppColors.primarySurface,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.edit_outlined,
                              color: AppColors.primary,
                              size: 16,
                            ),
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Modifier le profil',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: 14),

                  // ── Change password button ───────────────────────────────
                  GestureDetector(
                    onTap: () => _showChangePasswordSheet(context),
                    child: Container(
                      width: double.infinity,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.78),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.45),
                          width: 1.4,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.glassShadow,
                            blurRadius: 14,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: AppColors.primarySurface,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.lock_reset_rounded,
                              color: AppColors.primary,
                              size: 16,
                            ),
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Changer le mot de passe',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: 14),

                  // ── Logout button ────────────────────────────────────────
                  GestureDetector(
                    onTap: () async {
                      await AuthService.instance.logout();
                      if (context.mounted) Navigator.of(context).pop();
                    },
                    child: Container(
                      width: double.infinity,
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFE53935), Color(0xFFC62828)],
                        ),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.35),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.error.withValues(alpha: 0.32),
                            blurRadius: 18,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.logout_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Se déconnecter',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openPhotoGallery(BuildContext ctx) async {
    final id = _monProfil?.id;
    if (id == null) return;
    final navigator = Navigator.of(ctx, rootNavigator: true);
    final pageNavigator = Navigator.of(ctx);
    // Show loader
    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => Center(
        child: SizedBox(
          width: 48,
          height: 48,
          child: CircularProgressIndicator(
            color: AppColors.primary,
            strokeWidth: 3,
          ),
        ),
      ),
    );
    try {
      final photos = await PrestataireService.instance.getPhotos(id);
      if (!mounted) return;
      navigator.pop(); // close loader
      if (photos.isEmpty) {
        return;
      }
      pageNavigator.push(
        PageRouteBuilder(
          opaque: false,
          barrierColor: Colors.black87,
          pageBuilder: (_, __, ___) => _ProfileGallery(
            photos: photos,
            initialIndex: 0,
            onPhotoDeleted: () {
              if (mounted) _loadMonProfil();
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      navigator.pop();
      debugPrint('[Profile] load photos error: $e');
    }
  }

  void _showAddPhotosSheet(BuildContext ctx) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddPhotosSheetBody(
        onUploaded: () {
          if (mounted) _loadMonProfil();
        },
      ),
    );
  }

  void _showEditPrestataireSheet(BuildContext ctx) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditPrestataireSheetBody(
        profil: _monProfil,
        onUpdated: () {
          if (mounted) _loadMonProfil();
        },
      ),
    );
  }

  void _showEditProfileSheet(BuildContext ctx) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditProfileSheetBody(
        onProfileUpdated: () {
          if (mounted) setState(() {});
        },
      ),
    );
  }

  void _showChangePasswordSheet(BuildContext ctx) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ChangePasswordSheetBody(),
    );
  }

  Future<void> _showBecomeProviderSheet(BuildContext ctx) async {
    final becameProvider = await showModalBottomSheet<bool>(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BecomeProviderSheet(),
    );
    if (!mounted || becameProvider != true) return;
    setState(() {
      _profilError = null;
      _abonnementError = null;
    });
    await Future.wait([_loadMonProfil(), _loadAbonnement()]);
  }

  String _initial(String username) {
    final trimmed = username.trim();
    return trimmed.isNotEmpty ? trimmed[0].toUpperCase() : '?';
  }
}

class MesAvisClientsScreen extends StatefulWidget {
  MesAvisClientsScreen({super.key, required this.prestataireId});

  final int prestataireId;

  @override
  State<MesAvisClientsScreen> createState() => _MesAvisClientsScreenState();
}

class _MesAvisClientsScreenState extends State<MesAvisClientsScreen> {
  NotationsResponse? _avis;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAvis();
  }

  Future<void> _loadAvis() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final avis = await PrestataireService.instance.getProviderRatings(
        widget.prestataireId,
      );
      if (!mounted) return;
      setState(() {
        _avis = avis;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Impossible de charger vos avis clients.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _avis;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(18, 14, 18, 8),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.maybePop(context),
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppColors.glassBorder,
                            width: 1.1,
                          ),
                        ),
                        child: Icon(
                          Icons.arrow_back_rounded,
                          color: AppColors.primary,
                          size: 20,
                        ),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Mes avis clients',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _loading ? null : _loadAvis,
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppColors.primarySurface,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: _loading
                            ? Padding(
                                padding: EdgeInsets.all(11),
                                child: CircularProgressIndicator(
                                  color: AppColors.primary,
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                Icons.refresh_rounded,
                                color: AppColors.primary,
                                size: 20,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                          strokeWidth: 2.4,
                        ),
                      )
                    : _error != null
                    ? Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: _AvisError(
                            message: _error!,
                            onRetry: _loadAvis,
                          ),
                        ),
                      )
                    : data == null || data.ratings.isEmpty
                    ? Center(child: _AvisEmpty())
                    : ListView(
                        physics: BouncingScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(18, 12, 18, 24),
                        children: [
                          _AvisSummaryCard(avis: data),
                          SizedBox(height: 16),
                          ...data.ratings.map(
                            (rating) => Padding(
                              padding: EdgeInsets.only(bottom: 12),
                              child: _AvisClientTile(rating: rating),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Sheet body widgets (proper StatefulWidgets so controllers are lifecycle-managed) ──

class _EditProfileSheetBody extends StatefulWidget {
  _EditProfileSheetBody({required this.onProfileUpdated});
  final VoidCallback onProfileUpdated;

  @override
  State<_EditProfileSheetBody> createState() => _EditProfileSheetBodyState();
}

class _EditProfileSheetBodyState extends State<_EditProfileSheetBody> {
  late final TextEditingController _firstNameCtrl;
  late final TextEditingController _lastNameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  String? _errorMsg;
  String? _successMsg;

  @override
  void initState() {
    super.initState();
    final user = AuthService.instance.currentUser!;
    _firstNameCtrl = TextEditingController(text: user.firstName ?? '');
    _lastNameCtrl = TextEditingController(text: user.lastName ?? '');
    _emailCtrl = TextEditingController(text: user.email);
    _phoneCtrl = TextEditingController(text: user.telephone ?? '');
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _loading = true;
      _errorMsg = null;
      _successMsg = null;
    });
    try {
      final res = await AuthService.instance.updateProfile(
        firstName: _firstNameCtrl.text.trim(),
        lastName: _lastNameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        telephone: _phoneCtrl.text.trim().isEmpty
            ? null
            : _phoneCtrl.text.trim(),
      );
      if (!mounted) return;
      final ok = res['success'] == true;
      setState(() {
        _loading = false;
        if (ok) {
          _successMsg =
              res['message'] as String? ?? 'Profil mis à jour avec succès';
          widget.onProfileUpdated();
        } else {
          final err = res['error'] as Map<String, dynamic>?;
          _errorMsg = err?['message'] as String? ?? 'Une erreur est survenue';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMsg = 'Erreur réseau. Veuillez réessayer.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: AppColors.glassShadow,
              blurRadius: 32,
              offset: Offset(0, -4),
            ),
          ],
        ),
        padding: EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              SizedBox(height: 20),
              Text(
                'Modifier le profil',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Mettez à jour vos informations personnelles.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              SizedBox(height: 20),
              if (_errorMsg != null) ...[
                _SheetErrorBanner(message: _errorMsg!),
                SizedBox(height: 14),
              ],
              if (_successMsg != null) ...[
                _SheetSuccessBanner(message: _successMsg!),
                SizedBox(height: 14),
              ],
              _SheetLabel('Prénom'),
              SizedBox(height: 8),
              _SheetField(
                controller: _firstNameCtrl,
                hint: 'Jean',
                icon: Icons.badge_outlined,
                obscure: false,
                textInputAction: TextInputAction.next,
                onToggleObscure: () {},
                showToggle: false,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Champ obligatoire'
                    : null,
              ),
              SizedBox(height: 14),
              _SheetLabel('Nom de famille'),
              SizedBox(height: 8),
              _SheetField(
                controller: _lastNameCtrl,
                hint: 'Dupont',
                icon: Icons.person_outline_rounded,
                obscure: false,
                textInputAction: TextInputAction.next,
                onToggleObscure: () {},
                showToggle: false,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Champ obligatoire'
                    : null,
              ),
              SizedBox(height: 14),
              _SheetLabel('Adresse e-mail'),
              SizedBox(height: 8),
              _SheetField(
                controller: _emailCtrl,
                hint: 'jean@eden.local',
                icon: Icons.mail_outline_rounded,
                obscure: false,
                textInputAction: TextInputAction.next,
                onToggleObscure: () {},
                showToggle: false,
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Champ obligatoire';
                  if (!v.contains('@')) return 'E-mail invalide';
                  return null;
                },
              ),
              SizedBox(height: 14),
              _SheetLabel('Téléphone'),
              SizedBox(height: 8),
              _SheetField(
                controller: _phoneCtrl,
                hint: '+243 81 234 5678',
                icon: Icons.phone_outlined,
                obscure: false,
                textInputAction: TextInputAction.done,
                onToggleObscure: () {},
                showToggle: false,
                keyboardType: TextInputType.phone,
              ),
              SizedBox(height: 24),
              _SubmitButton(loading: _loading, onTap: _submit),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChangePasswordSheetBody extends StatefulWidget {
  _ChangePasswordSheetBody();

  @override
  State<_ChangePasswordSheetBody> createState() =>
      _ChangePasswordSheetBodyState();
}

class _ChangePasswordSheetBodyState extends State<_ChangePasswordSheetBody> {
  late final TextEditingController _currentCtrl;
  late final TextEditingController _newCtrl;
  late final TextEditingController _confirmCtrl;
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  bool _obscureCur = true;
  bool _obscureNew = true;
  bool _obscureCfm = true;
  String? _errorMsg;
  String? _successMsg;

  @override
  void initState() {
    super.initState();
    _currentCtrl = TextEditingController();
    _newCtrl = TextEditingController();
    _confirmCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _loading = true;
      _errorMsg = null;
      _successMsg = null;
    });
    try {
      final res = await AuthService.instance.changePassword(
        currentPassword: _currentCtrl.text,
        newPassword: _newCtrl.text,
      );
      if (!mounted) return;
      final ok = res['success'] == true;
      setState(() {
        _loading = false;
        if (ok) {
          _successMsg =
              res['message'] as String? ?? 'Mot de passe modifié avec succès';
          _currentCtrl.clear();
          _newCtrl.clear();
          _confirmCtrl.clear();
        } else {
          final err = res['error'] as Map<String, dynamic>?;
          _errorMsg = err?['message'] as String? ?? 'Une erreur est survenue';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMsg = 'Erreur réseau. Veuillez réessayer.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: AppColors.glassShadow,
              blurRadius: 32,
              offset: Offset(0, -4),
            ),
          ],
        ),
        padding: EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              SizedBox(height: 20),
              Text(
                'Changer le mot de passe',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Saisissez votre mot de passe actuel puis le nouveau.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              SizedBox(height: 20),
              if (_errorMsg != null) ...[
                _SheetErrorBanner(message: _errorMsg!),
                SizedBox(height: 14),
              ],
              if (_successMsg != null) ...[
                _SheetSuccessBanner(message: _successMsg!),
                SizedBox(height: 14),
              ],
              _SheetLabel('Mot de passe actuel'),
              SizedBox(height: 8),
              _SheetField(
                controller: _currentCtrl,
                hint: '••••••••',
                icon: Icons.lock_outline_rounded,
                obscure: _obscureCur,
                textInputAction: TextInputAction.next,
                onToggleObscure: () =>
                    setState(() => _obscureCur = !_obscureCur),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Champ obligatoire' : null,
              ),
              SizedBox(height: 14),
              _SheetLabel('Nouveau mot de passe'),
              SizedBox(height: 8),
              _SheetField(
                controller: _newCtrl,
                hint: '••••••••',
                icon: Icons.lock_reset_rounded,
                obscure: _obscureNew,
                textInputAction: TextInputAction.next,
                onToggleObscure: () =>
                    setState(() => _obscureNew = !_obscureNew),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Champ obligatoire';
                  if (v.length < 4) return 'Minimum 4 caractères';
                  return null;
                },
              ),
              SizedBox(height: 14),
              _SheetLabel('Confirmer le nouveau mot de passe'),
              SizedBox(height: 8),
              _SheetField(
                controller: _confirmCtrl,
                hint: '••••••••',
                icon: Icons.check_circle_outline_rounded,
                obscure: _obscureCfm,
                textInputAction: TextInputAction.done,
                onToggleObscure: () =>
                    setState(() => _obscureCfm = !_obscureCfm),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Champ obligatoire';
                  if (v != _newCtrl.text) {
                    return 'Les mots de passe ne correspondent pas';
                  }
                  return null;
                },
              ),
              SizedBox(height: 24),
              _SubmitButton(loading: _loading, onTap: _submit),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Edit prestataire sheet ────────────────────────────────────────────────────

class _EditPrestataireSheetBody extends StatefulWidget {
  _EditPrestataireSheetBody({required this.profil, required this.onUpdated});
  final MonProfilPrestataire? profil;
  final VoidCallback onUpdated;

  @override
  State<_EditPrestataireSheetBody> createState() =>
      _EditPrestataireSheetBodyState();
}

class _EditPrestataireSheetBodyState extends State<_EditPrestataireSheetBody> {
  late final TextEditingController _presentationCtrl;
  late final TextEditingController _adresseRueCtrl;
  late final TextEditingController _villeCtrl;
  late final TextEditingController _codePostalCtrl;
  late final TextEditingController _communeSearchCtrl;
  late final TextEditingController _serviceSearchCtrl;

  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  String? _errorMsg;
  String? _successMsg;

  // ── type de service dropdown ────────────────────────────────────────────
  String? _selectedTypeService;
  final Set<int> _selectedServiceIds = {};
  List<ServiceDisponible> _servicesList = [];
  List<ServiceDisponible> _filteredServices = [];
  bool _showServiceList = false;

  // ── commune dropdown ─────────────────────────────────────────────────────
  String? _selectedVille;
  String? _selectedCommune;
  bool _showCommuneList = false;
  List<String> _filteredCommunes = Locations.communesDe('Kinshasa');

  @override
  void initState() {
    super.initState();
    final p = widget.profil;
    _presentationCtrl = TextEditingController(text: p?.presentation ?? '');
    _adresseRueCtrl = TextEditingController(text: p?.adresseRue ?? '');
    _villeCtrl = TextEditingController(
      text: p?.ville.isNotEmpty == true ? p!.ville : 'Kinshasa',
    );
    _codePostalCtrl = TextEditingController(text: p?.codePostal ?? '');
    _communeSearchCtrl = TextEditingController(text: p?.commune ?? '');
    _serviceSearchCtrl = TextEditingController();
    // Ville d'origine conservée telle quelle (données existantes), mais
    // présentée sous son nom de référence quand elle est connue.
    _selectedVille = Locations.villeValide(p?.ville);
    _villeCtrl.text = _selectedVille ?? '';
    _selectedCommune = (p?.commune.isNotEmpty == true) ? p!.commune : null;
    _filteredCommunes = Locations.communesDe(_selectedVille);
    _selectedTypeService = (p?.typeService.isNotEmpty == true)
        ? p!.typeService
        : null;
    _selectedServiceIds.addAll(p?.serviceIds ?? const []);
    _loadServices();
  }

  Future<void> _loadServices() async {
    try {
      final list = await _loadAvailableServices();
      if (!mounted) return;
      setState(() {
        _servicesList = list;
        _filteredServices = list;
        if (_selectedTypeService != null && _selectedServiceIds.isEmpty) {
          final match = list.where(
            (service) => service.nom == _selectedTypeService,
          );
          if (match.isNotEmpty) _selectedServiceIds.add(match.first.id);
        }
        if (_selectedTypeService != null &&
            list.every((service) => service.nom != _selectedTypeService)) {
          _servicesList = [
            ServiceDisponible(
              id: -1,
              nom: _selectedTypeService!,
              actif: true,
              dateCreation: '',
            ),
            ...list,
          ];
          _filteredServices = _servicesList;
        }
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _presentationCtrl.dispose();
    _adresseRueCtrl.dispose();
    _villeCtrl.dispose();
    _codePostalCtrl.dispose();
    _communeSearchCtrl.dispose();
    _serviceSearchCtrl.dispose();
    super.dispose();
  }

  void _filterServices(String q) {
    final lower = q.toLowerCase();
    setState(() {
      _filteredServices = _servicesList
          .where((s) => s.nom.toLowerCase().contains(lower))
          .toList();
    });
  }

  List<ServiceDisponible> get _selectedServices => _servicesList
      .where((service) => _selectedServiceIds.contains(service.id))
      .toList();

  String get _selectedServicesLabel {
    final selected = _selectedServices.map((service) => service.nom).toList();
    if (selected.isEmpty && _selectedTypeService?.isNotEmpty == true) {
      selected.add(_selectedTypeService!);
    }
    if (selected.isEmpty) return 'Sélectionner un ou plusieurs services';
    if (selected.length <= 2) return selected.join(', ');
    return '${selected.take(2).join(', ')} +${selected.length - 2}';
  }

  void _filterCommunes(String q) {
    final lower = q.toLowerCase();
    setState(() {
      _filteredCommunes = Locations.communesDe(_villeCtrl.text.trim())
          .where((c) => c.toLowerCase().contains(lower))
          .toList();
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _loading = true;
      _errorMsg = null;
      _successMsg = null;
    });
    try {
      final res = await PrestataireService.instance.updateMonProfil(
        typeService: _selectedTypeService,
        serviceIds: _selectedServiceIds.where((id) => id > 0).toList(),
        presentation: _presentationCtrl.text.trim(),
        adresseRue: _adresseRueCtrl.text.trim().isEmpty
            ? null
            : _adresseRueCtrl.text.trim(),
        commune: _selectedCommune,
        ville: (_selectedVille == null || _selectedVille!.trim().isEmpty)
            ? null
            : _selectedVille!.trim(),
        codePostal: _codePostalCtrl.text.trim().isEmpty
            ? null
            : _codePostalCtrl.text.trim(),
      );
      if (!mounted) return;
      final ok = res['success'] == true;
      if (ok) {
        final navigator = Navigator.of(context);
        widget.onUpdated();
        navigator.pop();
        debugPrint(
          '[Profile] ${res['message'] as String? ?? 'Profil mis à jour.'}',
        );
        return;
      }
      setState(() {
        _loading = false;
        final err = res['error'] as Map<String, dynamic>?;
        _errorMsg = err?['message'] as String? ?? 'Une erreur est survenue';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMsg = 'Erreur réseau. Veuillez réessayer.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: AppColors.glassShadow,
              blurRadius: 32,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            SizedBox(height: 12),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            SizedBox(height: 16),
            // Title
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Modifier mon profil prestataire',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Mettez à jour les informations de votre activité.',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
            Divider(height: 1, color: AppColors.divider),
            // Scrollable form
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_errorMsg != null) ...[
                        _SheetErrorBanner(message: _errorMsg!),
                        SizedBox(height: 14),
                      ],
                      if (_successMsg != null) ...[
                        _SheetSuccessBanner(message: _successMsg!),
                        SizedBox(height: 14),
                      ],
                      _SheetLabel('Services proposés'),
                      SizedBox(height: 8),
                      // ── Service dropdown-search ───────────────────────
                      FormField<String>(
                        initialValue: _selectedTypeService,
                        validator: (_) =>
                            _selectedServiceIds.isEmpty &&
                                (_selectedTypeService == null ||
                                    _selectedTypeService!.isEmpty)
                            ? 'Champ obligatoire'
                            : null,
                        builder: (field) => Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            GestureDetector(
                              onTap: () async {
                                final selectedServices =
                                    await _showServiceTypePicker(
                                      context: context,
                                      services: _servicesList,
                                      selectedIds: _selectedServiceIds,
                                    );
                                if (!mounted || selectedServices == null) {
                                  return;
                                }
                                setState(() {
                                  _selectedServiceIds
                                    ..clear()
                                    ..addAll(
                                      selectedServices
                                          .where((service) => service.id > 0)
                                          .map((service) => service.id),
                                    );
                                  _selectedTypeService =
                                      selectedServices.isNotEmpty
                                      ? selectedServices.first.nom
                                      : null;
                                  _showServiceList = false;
                                });
                                field.didChange(_selectedTypeService);
                              },
                              child: Container(
                                height: 52,
                                padding: EdgeInsets.symmetric(horizontal: 16),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.65),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: field.hasError
                                        ? AppColors.error
                                        : _showServiceList
                                        ? AppColors.primary
                                        : AppColors.divider,
                                    width: (_showServiceList || field.hasError)
                                        ? 1.8
                                        : 1.2,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.design_services_outlined,
                                      color: AppColors.primary,
                                      size: 19,
                                    ),
                                    SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        _selectedServicesLabel,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color:
                                              _selectedServiceIds.isNotEmpty ||
                                                  _selectedTypeService != null
                                              ? AppColors.textPrimary
                                              : AppColors.textHint,
                                        ),
                                      ),
                                    ),
                                    Icon(
                                      _showServiceList
                                          ? Icons.keyboard_arrow_up_rounded
                                          : Icons.keyboard_arrow_down_rounded,
                                      color: AppColors.textHint,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (field.hasError)
                              Padding(
                                padding: EdgeInsets.only(top: 6, left: 14),
                                child: Text(
                                  field.errorText!,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.error,
                                  ),
                                ),
                              ),
                            if (_showServiceList) ...[
                              SizedBox(height: 6),
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.95),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: AppColors.divider,
                                    width: 1.2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.glassShadow,
                                      blurRadius: 14,
                                      offset: Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  children: [
                                    Padding(
                                      padding: EdgeInsets.fromLTRB(
                                        12,
                                        10,
                                        12,
                                        4,
                                      ),
                                      child: TextField(
                                        controller: _serviceSearchCtrl,
                                        autofocus: true,
                                        onChanged: _filterServices,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: AppColors.textPrimary,
                                        ),
                                        decoration: InputDecoration(
                                          hintText: 'Rechercher...',
                                          hintStyle: TextStyle(
                                            color: AppColors.textHint,
                                            fontSize: 13,
                                          ),
                                          prefixIcon: Icon(
                                            Icons.search_rounded,
                                            color: AppColors.primary,
                                            size: 18,
                                          ),
                                          isDense: true,
                                          contentPadding: EdgeInsets.symmetric(
                                            vertical: 10,
                                          ),
                                          filled: true,
                                          fillColor: AppColors.primarySurface,
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            borderSide: BorderSide.none,
                                          ),
                                        ),
                                      ),
                                    ),
                                    ConstrainedBox(
                                      constraints: BoxConstraints(
                                        maxHeight: 200,
                                      ),
                                      child: _servicesList.isEmpty
                                          ? Padding(
                                              padding: EdgeInsets.symmetric(
                                                vertical: 16,
                                              ),
                                              child: Center(
                                                child: SizedBox(
                                                  width: 20,
                                                  height: 20,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color:
                                                            AppColors.primary,
                                                      ),
                                                ),
                                              ),
                                            )
                                          : ListView.builder(
                                              padding: EdgeInsets.only(
                                                bottom: 8,
                                              ),
                                              shrinkWrap: true,
                                              itemCount:
                                                  _filteredServices.length,
                                              itemBuilder: (_, i) {
                                                final s = _filteredServices[i];
                                                final selected =
                                                    _selectedServiceIds
                                                        .contains(s.id);
                                                return GestureDetector(
                                                  onTap: () {
                                                    setState(() {
                                                      if (selected) {
                                                        _selectedServiceIds
                                                            .remove(s.id);
                                                      } else {
                                                        _selectedServiceIds.add(
                                                          s.id,
                                                        );
                                                      }
                                                      _selectedTypeService =
                                                          _selectedServices
                                                              .isNotEmpty
                                                          ? _selectedServices
                                                                .first
                                                                .nom
                                                          : null;
                                                    });
                                                    field.didChange(
                                                      _selectedTypeService,
                                                    );
                                                  },
                                                  child: Container(
                                                    padding:
                                                        EdgeInsets.symmetric(
                                                          horizontal: 16,
                                                          vertical: 12,
                                                        ),
                                                    color: selected
                                                        ? AppColors
                                                              .primarySurface
                                                        : Colors.transparent,
                                                    child: Row(
                                                      children: [
                                                        Expanded(
                                                          child: Text(
                                                            s.nom,
                                                            style: TextStyle(
                                                              fontSize: 14,
                                                              fontWeight:
                                                                  selected
                                                                  ? FontWeight
                                                                        .w600
                                                                  : FontWeight
                                                                        .w400,
                                                              color: selected
                                                                  ? AppColors
                                                                        .primary
                                                                  : AppColors
                                                                        .textPrimary,
                                                            ),
                                                          ),
                                                        ),
                                                        if (selected)
                                                          Icon(
                                                            Icons.check_rounded,
                                                            color: AppColors
                                                                .primary,
                                                            size: 16,
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      SizedBox(height: 14),
                      _SheetLabel('Présentation'),
                      SizedBox(height: 8),
                      TextFormField(
                        controller: _presentationCtrl,
                        maxLines: 3,
                        textInputAction: TextInputAction.newline,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Décrivez votre expérience et expertise...',
                          hintStyle: TextStyle(
                            color: AppColors.textHint,
                            fontSize: 14,
                          ),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.65),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: AppColors.divider,
                              width: 1.2,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: AppColors.divider,
                              width: 1.2,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: AppColors.primary,
                              width: 1.8,
                            ),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: AppColors.error,
                              width: 1.4,
                            ),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: AppColors.error,
                              width: 1.8,
                            ),
                          ),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Champ obligatoire'
                            : null,
                      ),
                      SizedBox(height: 14),
                      _SheetLabel('Adresse (rue / avenue)'),
                      SizedBox(height: 8),
                      _SheetField(
                        controller: _adresseRueCtrl,
                        hint: 'Ex : 123 Avenue de la Paix',
                        icon: Icons.home_outlined,
                        obscure: false,
                        textInputAction: TextInputAction.next,
                        onToggleObscure: () {},
                        showToggle: false,
                      ),
                      SizedBox(height: 14),
                      _SheetLabel('Commune'),
                      SizedBox(height: 8),
                      // Commune dropdown-search
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          GestureDetector(
                            onTap: () => setState(() {
                              _showCommuneList = !_showCommuneList;
                              if (_showCommuneList) {
                                _communeSearchCtrl.clear();
                                _filteredCommunes = Locations.communesDe(_villeCtrl.text.trim());
                              }
                            }),
                            child: Container(
                              height: 52,
                              padding: EdgeInsets.symmetric(horizontal: 16),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.65),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: _showCommuneList
                                      ? AppColors.primary
                                      : AppColors.divider,
                                  width: _showCommuneList ? 1.8 : 1.2,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.location_city_outlined,
                                    color: AppColors.primary,
                                    size: 19,
                                  ),
                                  SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _selectedCommune ??
                                          'Sélectionner une commune',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: _selectedCommune != null
                                            ? AppColors.textPrimary
                                            : AppColors.textHint,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    _showCommuneList
                                        ? Icons.keyboard_arrow_up_rounded
                                        : Icons.keyboard_arrow_down_rounded,
                                    color: AppColors.textHint,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (_showCommuneList) ...[
                            SizedBox(height: 6),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.95),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: AppColors.divider,
                                  width: 1.2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.glassShadow,
                                    blurRadius: 14,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Column(
                                children: [
                                  Padding(
                                    padding: EdgeInsets.fromLTRB(12, 10, 12, 4),
                                    child: TextField(
                                      controller: _communeSearchCtrl,
                                      autofocus: true,
                                      onChanged: _filterCommunes,
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: AppColors.textPrimary,
                                      ),
                                      decoration: InputDecoration(
                                        hintText: 'Rechercher...',
                                        hintStyle: TextStyle(
                                          color: AppColors.textHint,
                                          fontSize: 13,
                                        ),
                                        prefixIcon: Icon(
                                          Icons.search_rounded,
                                          color: AppColors.primary,
                                          size: 18,
                                        ),
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(
                                          vertical: 10,
                                        ),
                                        filled: true,
                                        fillColor: AppColors.primarySurface,
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: BorderSide.none,
                                        ),
                                      ),
                                    ),
                                  ),
                                  ConstrainedBox(
                                    constraints: BoxConstraints(maxHeight: 200),
                                    child: ListView.builder(
                                      padding: EdgeInsets.only(bottom: 8),
                                      shrinkWrap: true,
                                      itemCount: _filteredCommunes.length,
                                      itemBuilder: (_, i) {
                                        final c = _filteredCommunes[i];
                                        final selected = c == _selectedCommune;
                                        return GestureDetector(
                                          onTap: () => setState(() {
                                            _selectedCommune = c;
                                            _showCommuneList = false;
                                          }),
                                          child: Container(
                                            padding: EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 12,
                                            ),
                                            color: selected
                                                ? AppColors.primarySurface
                                                : Colors.transparent,
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    c,
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      fontWeight: selected
                                                          ? FontWeight.w600
                                                          : FontWeight.w400,
                                                      color: selected
                                                          ? AppColors.primary
                                                          : AppColors
                                                                .textPrimary,
                                                    ),
                                                  ),
                                                ),
                                                if (selected)
                                                  Icon(
                                                    Icons.check_rounded,
                                                    color: AppColors.primary,
                                                    size: 16,
                                                  ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      SizedBox(height: 14),
                      // ── Ville (liste déroulante) ──────────────────────
                      _SheetLabel('Ville'),
                      SizedBox(height: 8),
                      _ProviderInlineDropdown<String>(
                        value: _selectedVille,
                        placeholder: 'Sélectionner une ville',
                        icon: Icons.location_city_outlined,
                        options: Locations.nomsVilles,
                        onChanged: (v) => setState(() {
                          _selectedVille = v;
                          _villeCtrl.text = v ?? '';
                          // La commune dépend de la ville : on
                          // réinitialise si elle n'y appartient plus.
                          if (!Locations.communeAppartientA(
                            commune: _selectedCommune,
                            ville: v,
                          )) {
                            _selectedCommune = null;
                            _communeSearchCtrl.clear();
                          }
                          _showCommuneList = false;
                        }),
                      ),
                      SizedBox(height: 14),
                      _SheetLabel('Code postal (optionnel)'),
                      SizedBox(height: 8),
                      _SheetField(
                        controller: _codePostalCtrl,
                        hint: 'Ex : 00243',
                        icon: Icons.markunread_mailbox_outlined,
                        obscure: false,
                        textInputAction: TextInputAction.done,
                        onToggleObscure: () {},
                        showToggle: false,
                        keyboardType: TextInputType.number,
                      ),
                      SizedBox(height: 24),
                      _SubmitButton(loading: _loading, onTap: _submit),
                      SizedBox(height: 32),
                    ],
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

/// Liste déroulante en ligne, alignée sur le style des champs du profil
/// (même hauteur, mêmes rayons et mêmes couleurs que [_SheetField]).
class _ProviderInlineDropdown<T> extends StatelessWidget {
  _ProviderInlineDropdown({
    required this.value,
    required this.placeholder,
    required this.icon,
    required this.options,
    required this.onChanged,
    this.searchable = false,
  });

  final T? value;
  final String placeholder;
  final IconData icon;
  final List<T> options;
  final void Function(T?) onChanged;
  final bool searchable;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final result = await showModalBottomSheet<T>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => _InlineDropdownSheet<T>(
            title: placeholder,
            options: options,
            selected: value,
            searchable: searchable,
          ),
        );
        onChanged(result);
      },
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider, width: 1.2),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary, size: 19),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                value?.toString() ?? placeholder,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: value == null
                      ? AppColors.textHint
                      : AppColors.textPrimary,
                ),
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: AppColors.textSecondary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

/// Feuille de sélection pour [_ProviderInlineDropdown], alignée sur le style
/// des feuilles glass déjà utilisées dans l'application.
class _InlineDropdownSheet<T> extends StatefulWidget {
  _InlineDropdownSheet({
    required this.title,
    required this.options,
    required this.selected,
    this.searchable = false,
  });

  final String title;
  final List<T> options;
  final T? selected;
  final bool searchable;

  @override
  State<_InlineDropdownSheet<T>> createState() =>
      _InlineDropdownSheetState<T>();
}

class _InlineDropdownSheetState<T> extends State<_InlineDropdownSheet<T>> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<T> _filtered = const [];

  @override
  void initState() {
    super.initState();
    _filtered = widget.options;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearch(String q) {
    setState(() {
      final query = q.trim().toLowerCase();
      _filtered = query.isEmpty
          ? widget.options
          : widget.options
                .where((o) => o.toString().toLowerCase().contains(query))
                .toList();
    });
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
                const SizedBox(height: 12),
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
                if (widget.searchable)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
                    child: Container(
                      height: 46,
                      decoration: BoxDecoration(
                        color: AppColors.primarySurface,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.search_rounded,
                            size: 18,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _searchCtrl,
                              onChanged: _onSearch,
                              style: const TextStyle(fontSize: 14),
                              decoration: const InputDecoration(
                                hintText: 'Rechercher…',
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
                    padding: const EdgeInsets.only(bottom: 24),
                    children: _filtered.map((o) {
                      final isSelected = o == widget.selected;
                      return InkWell(
                        onTap: () => Navigator.pop(context, o),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 14,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  o.toString(),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: isSelected
                                        ? AppColors.primary
                                        : AppColors.textPrimary,
                                  ),
                                ),
                              ),
                              if (isSelected)
                                const Icon(
                                  Icons.check_rounded,
                                  color: AppColors.primary,
                                  size: 18,
                                ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
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

/// Shared submit button used by both sheet bodies.
class _SubmitButton extends StatelessWidget {
  _SubmitButton({required this.loading, required this.onTap});
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          gradient: loading
              ? LinearGradient(
                  colors: [
                    AppColors.textHint.withValues(alpha: 0.2),
                    AppColors.textHint.withValues(alpha: 0.1),
                  ],
                )
              : AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.35),
            width: 1.2,
          ),
          boxShadow: [
            if (!loading)
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.32),
                blurRadius: 18,
                offset: Offset(0, 6),
              ),
          ],
        ),
        child: loading
            ? Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.4,
                  ),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_rounded, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Enregistrer',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ── Abonnement card ───────────────────────────────────────────────────────────

class _AbonnementCard extends StatelessWidget {
  _AbonnementCard({
    required this.loading,
    required this.error,
    required this.abonnement,
    required this.onRetry,
    required this.onSouscrire,
  });

  final bool loading;
  final String? error;
  final AbonnementStatut? abonnement;
  final VoidCallback onRetry;
  final VoidCallback onSouscrire;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.glassBorder, width: 1.4),
        boxShadow: [
          BoxShadow(
            color: AppColors.glassShadow,
            blurRadius: 18,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.workspace_premium_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Mon abonnement',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: loading ? null : onRetry,
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: loading
                        ? Padding(
                            padding: EdgeInsets.all(7),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            Icons.refresh_rounded,
                            color: Colors.white,
                            size: 17,
                          ),
                  ),
                ),
              ],
            ),
          ),

          // ── Body ────────────────────────────────────────────────────────
          Padding(padding: EdgeInsets.all(18), child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (loading) {
      return Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: AppColors.primary,
          ),
        ),
      );
    }

    if (error != null) {
      return Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              error!,
              style: TextStyle(color: AppColors.error, fontSize: 13),
            ),
          ),
          GestureDetector(
            onTap: onRetry,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primarySurface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Réessayer',
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (abonnement == null) {
      return Text(
        'Aucune donnée disponible.',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
      );
    }

    return _AbonnementBody(abonnement: abonnement!, onSouscrire: onSouscrire);
  }
}

class _AbonnementBody extends StatelessWidget {
  _AbonnementBody({required this.abonnement, required this.onSouscrire});
  final AbonnementStatut abonnement;
  final VoidCallback onSouscrire;

  @override
  Widget build(BuildContext context) {
    // ── Status badge ──────────────────────────────────────────────────────
    final bool actif = abonnement.estAbonnementCourantActif;
    final bool essai = abonnement.estEnEssai;
    final DateTime? finAbonnement = abonnement.dateFinAbonnementEffective;
    final DateTime? finDernierAbonnement = abonnement.dateFinDernierAbonnement;
    final int? joursAbonnementRestants = abonnement.joursAbonnementRestants;
    final String statutPrestataire = abonnement.statutPrestataire.trim();

    Color badgeColor;
    Color badgeBg;
    IconData badgeIcon;
    String badgeLabel;

    if (actif) {
      badgeColor = AppColors.primary;
      badgeBg = AppColors.primarySurface;
      badgeIcon = Icons.verified_rounded;
      badgeLabel = 'Abonnement actif';
    } else if (essai) {
      badgeColor = Color(0xFFF59E0B); // amber
      badgeBg = Color(0xFFFFFBEB);
      badgeIcon = Icons.hourglass_top_rounded;
      badgeLabel = 'Période d\'essai';
    } else {
      badgeColor = AppColors.error;
      badgeBg = Color(0xFFFEF2F2);
      badgeIcon = Icons.block_rounded;
      badgeLabel = 'Inactif';
    }

    final bool essaiTermine = abonnement.essaiTermine;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Status badge
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: badgeBg,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: badgeColor.withValues(alpha: 0.35),
              width: 1.2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(badgeIcon, color: badgeColor, size: 15),
              SizedBox(width: 6),
              Text(
                badgeLabel,
                style: TextStyle(
                  color: badgeColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),

        // ── Trial details ──────────────────────────────────────────────
        if (essai) ...[
          SizedBox(height: 16),
          _AbInfoRow(
            icon: Icons.timer_outlined,
            label: 'Jours restants',
            value:
                '${abonnement.joursEssaiRestants} jour${abonnement.joursEssaiRestants != 1 ? 's' : ''}',
            valueColor: abonnement.joursEssaiRestants <= 3
                ? AppColors.error
                : AppColors.textPrimary,
          ),
          if (abonnement.dateFinEssai != null) ...[
            SizedBox(height: 10),
            _AbInfoRow(
              icon: Icons.calendar_today_outlined,
              label: 'Fin de l\'essai',
              value: _formatDate(abonnement.dateFinEssai!),
            ),
          ],
        ],

        // ── Active subscription details ────────────────────────────────
        if (actif) ...[
          if (joursAbonnementRestants != null) ...[
            SizedBox(height: 10),
            _AbInfoRow(
              icon: Icons.timer_outlined,
              label: 'Il vous reste',
              value: _formatRemainingDays(joursAbonnementRestants),
              valueColor: joursAbonnementRestants <= 3
                  ? AppColors.error
                  : AppColors.textPrimary,
            ),
          ],
        ],

        // ── Provider business status ───────────────────────────────────
        if (statutPrestataire.isNotEmpty ||
            abonnement.estValide != null ||
            abonnement.isAvailable != null)
          ...[],

        if (!actif && abonnement.dernierAbonnement != null) ...[
          SizedBox(height: 16),
          _AbInfoRow(
            icon: Icons.history_rounded,
            label: 'Dernier abonnement',
            value: _formatDernierAbonnement(
              abonnement.statutDernierAbonnement,
              finDernierAbonnement,
            ),
            valueColor: AppColors.textSecondary,
          ),
        ],

        if (abonnement.abonnementDateExpiree && finAbonnement != null) ...[
          SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Color(0xFFFECACA)),
            ),
            child: Text(
              'Votre abonnement a expiré le ${_formatDate(finAbonnement)}.',
              style: TextStyle(
                color: AppColors.error,
                fontSize: 12.5,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],

        // ── CTA réabonnement ───────────────────────────────────────────
        if (abonnement.estInactif) ...[
          SizedBox(height: 14),
          Text(
            essaiTermine
                ? 'Votre période d\'essai est terminée. Souscrivez un abonnement pour continuer à profiter du service.'
                : 'Souscrivez à un abonnement pour accéder à toutes les fonctionnalités.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12.5,
              height: 1.5,
            ),
          ),
          SizedBox(height: 14),
          GestureDetector(
            onTap: onSouscrire,
            child: Container(
              width: double.infinity,
              height: 48,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.workspace_premium_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Se réabonner',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  static String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/'
        '${dt.year}';
  }

  static String _formatStatus(String value) {
    final clean = value.replaceAll('_', ' ').trim();
    if (clean.isEmpty) return '-';
    return clean[0].toUpperCase() + clean.substring(1);
  }

  static String _formatRemainingDays(int days) {
    if (days <= 0) return 'Moins d’un jour';
    return '$days jour${days > 1 ? 's' : ''}';
  }

  static String _formatDernierAbonnement(String statut, DateTime? fin) {
    final statusLabel = statut.isEmpty ? 'Terminé' : _formatStatus(statut);
    if (fin == null) return statusLabel;
    return '$statusLabel le ${_formatDate(fin)}';
  }
}

class _AbInfoRow extends StatelessWidget {
  _AbInfoRow({
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
    return Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 16),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? AppColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _PaiementAbonnementSheet extends StatefulWidget {
  _PaiementAbonnementSheet({required this.abonnement, required this.onSuccess});

  final AbonnementStatut? abonnement;
  final VoidCallback onSuccess;

  @override
  State<_PaiementAbonnementSheet> createState() =>
      _PaiementAbonnementSheetState();
}

class _PaiementAbonnementSheetState extends State<_PaiementAbonnementSheet> {
  final _phoneCtrl = TextEditingController();
  PaiementConfig? _config;
  PaiementPlan? _selectedPlan;
  String _currency = 'CDF';
  PaiementTransaction? _transaction;
  StreamSubscription<UserRealtimeEvent>? _userRealtimeSub;
  Timer? _pollTimer;
  int _pollCount = 0;
  bool _loading = true;
  bool _submitting = false;
  bool _checkingStatus = false;
  String? _error;

  bool get _pending => _transaction?.statut.toUpperCase() == 'PENDING';

  @override
  void initState() {
    super.initState();
    final phone = AuthService.instance.currentUser?.telephone ?? '';
    _phoneCtrl.text = _normalizePhone(phone);
    UserRealtimeService.instance.watch();
    _userRealtimeSub = UserRealtimeService.instance.events.listen(
      _handleUserRealtimeEvent,
    );
    _loadConfig();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _userRealtimeSub?.cancel();
    UserRealtimeService.instance.unwatch();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    try {
      final config = await AuthService.instance.getPaiementConfig();
      if (!mounted) return;
      setState(() {
        _config = config;
        _selectedPlan = config.plans.isNotEmpty ? config.plans.first : null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Impossible de charger les plans de paiement.';
      });
    }
  }

  String _normalizePhone(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('0') && digits.length == 10) {
      return '243${digits.substring(1)}';
    }
    if (digits.startsWith('243')) return digits;
    return digits;
  }

  bool _isFinalStatus(String status) =>
      status.toLowerCase() == 'success' ||
      status.toLowerCase() == 'complete' ||
      status.toLowerCase() == 'failed' ||
      status.toLowerCase() == 'echoue' ||
      status.toLowerCase() == 'cancelled' ||
      status.toLowerCase() == 'refunded' ||
      status.toLowerCase() == 'rembourse';

  void _handleUserRealtimeEvent(UserRealtimeEvent event) {
    final paiementEvent = PaiementStatusRealtimeEvent.fromUserEvent(event);
    final current = _transaction;
    if (paiementEvent == null || current == null || !mounted) return;
    if (paiementEvent.id != current.id) return;

    setState(() {
      _transaction = current.copyWith(statut: paiementEvent.statut);
      _error = null;
    });

    if (_isFinalStatus(paiementEvent.statut)) {
      _pollTimer?.cancel();
      if (paiementEvent.isSuccess) {
        AppRefreshService.instance.notify(const {
          AppRefreshTopic.abonnement,
          AppRefreshTopic.profile,
          AppRefreshTopic.home,
        });
        widget.onSuccess();
      }
    }
  }

  Future<void> _createPayment() async {
    final plan = _selectedPlan;
    final phone = _normalizePhone(_phoneCtrl.text);
    if (plan == null) {
      setState(() => _error = 'Veuillez choisir une durée.');
      return;
    }
    if (!RegExp(r'^243\d{9}$').hasMatch(phone)) {
      setState(
        () => _error = 'Entrez un numéro Mobile Money au format 243XXXXXXXXX.',
      );
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final transaction = await AuthService.instance.createPaiement(
        phone: phone,
        currency: _currency,
        dureeMois: plan.dureeMois,
      );
      if (!mounted) return;
      setState(() {
        _transaction = transaction;
        _submitting = false;
      });
      _startPolling(transaction.id);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = userFriendlyError(e, fallback: 'Paiement impossible.');
      });
    }
  }

  void _startPolling(int transactionId) {
    _pollTimer?.cancel();
    _pollCount = 0;
    _pollTimer = Timer.periodic(Duration(seconds: 5), (timer) async {
      _pollCount++;
      if (_pollCount > 36) {
        timer.cancel();
        if (mounted) {
          setState(
            () => _error =
                'Confirmation encore en attente. Utilisez “Vérifier maintenant” ou revenez dans un instant.',
          );
        }
        return;
      }
      await _checkPaymentStatus();
    });
  }

  Future<void> _checkPaymentStatus() async {
    final current = _transaction;
    if (current == null || _checkingStatus) return;
    setState(() {
      _checkingStatus = true;
      _error = null;
    });
    try {
      final tx = await AuthService.instance.getPaiementStatus(current.id);
      if (!mounted) return;
      final status = tx.statut.toUpperCase();
      setState(() => _transaction = tx);
      if (_isFinalStatus(status)) {
        _pollTimer?.cancel();
        if (status == 'SUCCESS') widget.onSuccess();
        return;
      }

      final abonnement = await AuthService.instance.getMonAbonnement();
      if (!mounted) return;
      if (abonnement?.estAbonnementCourantActif == true) {
        _pollTimer?.cancel();
        setState(() => _transaction = tx.copyWith(statut: 'SUCCESS'));
        widget.onSuccess();
      }
    } catch (_) {
      // if (mounted) {
      //   setState(
      //     () => _error = 'Impossible de vérifier le paiement pour le moment.',
      //   );
      // }
    } finally {
      if (mounted) setState(() => _checkingStatus = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.86,
      minChildSize: 0.62,
      maxChildSize: 0.96,
      expand: false,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: Color(0xFFF5FDF9),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            SizedBox(height: 12),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.payments_rounded, color: Colors.white),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Paiement abonnement',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Activez votre compte prestataire par Mobile Money',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(
                      Icons.close_rounded,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: controller,
                padding: EdgeInsets.fromLTRB(20, 8, 20, 26),
                children: [
                  if (_loading)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 60),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                        ),
                      ),
                    )
                  else if (_config?.flexpayActif == false)
                    _PaymentNotice(
                      icon: Icons.warning_amber_rounded,
                      title: 'Paiement indisponible',
                      text: 'Le paiement en ligne est momentanément désactivé.',
                      color: AppColors.warning,
                    )
                  else ...[
                    if (_transaction == null) ...[
                      _SheetLabel('Durée'),
                      SizedBox(height: 10),
                      ...(_config?.plans ?? <PaiementPlan>[]).map(
                        (plan) => _PaymentPlanCard(
                          plan: plan,
                          currency: _currency,
                          selected: _selectedPlan?.dureeMois == plan.dureeMois,
                          onTap: () => setState(() => _selectedPlan = plan),
                        ),
                      ),
                      SizedBox(height: 16),
                      _SheetLabel('Devise'),
                      SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _CurrencyButton(
                              label: 'CDF',
                              selected: _currency == 'CDF',
                              onTap: () => setState(() => _currency = 'CDF'),
                            ),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: _CurrencyButton(
                              label: 'USD',
                              selected: _currency == 'USD',
                              onTap: () => setState(() => _currency = 'USD'),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 16),
                      _SheetLabel('Téléphone Mobile Money'),
                      SizedBox(height: 8),
                      TextField(
                        controller: _phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          hintText: '243812000000',
                          prefixIcon: Icon(
                            Icons.phone_iphone_rounded,
                            color: AppColors.primary,
                          ),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.88),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      if (_error != null) ...[
                        SizedBox(height: 12),
                        _PaymentInlineError(message: _error!),
                      ],
                      SizedBox(height: 20),
                      GestureDetector(
                        onTap: _submitting ? null : _createPayment,
                        child: Container(
                          height: 54,
                          decoration: BoxDecoration(
                            gradient: AppColors.primaryGradient,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          alignment: Alignment.center,
                          child: _submitting
                              ? CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                )
                              : Text(
                                  'Initier le paiement',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                        ),
                      ),
                    ] else
                      _PaymentStatusView(
                        transaction: _transaction!,
                        pending: _pending,
                        checking: _checkingStatus,
                        error: _error,
                        onRefresh: _checkPaymentStatus,
                        onClose: () => Navigator.pop(context),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentPlanCard extends StatelessWidget {
  _PaymentPlanCard({
    required this.plan,
    required this.currency,
    required this.selected,
    required this.onTap,
  });

  final PaiementPlan plan;
  final String currency;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final amount = plan.amountFor(currency);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.only(bottom: 10),
        padding: EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primarySurface
              : Colors.white.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.divider,
            width: selected ? 2 : 1.2,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(
                  alpha: selected ? 0.14 : 0.08,
                ),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                plan.dureeMois >= 12
                    ? Icons.workspace_premium_rounded
                    : Icons.calendar_month_rounded,
                color: AppColors.primary,
              ),
            ),
            SizedBox(width: 13),
            Expanded(
              child: Text(
                '${plan.dureeMois} mois',
                style: TextStyle(
                  color: selected ? AppColors.primary : AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              '$amount $currency',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (selected) ...[
              SizedBox(width: 8),
              Icon(
                Icons.check_circle_rounded,
                color: AppColors.primary,
                size: 19,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CurrencyButton extends StatelessWidget {
  _CurrencyButton({
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
      child: Container(
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primarySurface
              : Colors.white.withValues(alpha: 0.86),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.divider,
            width: selected ? 1.8 : 1.1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.primary : AppColors.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _PaymentInlineError extends StatelessWidget {
  _PaymentInlineError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: AppColors.error, size: 17),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: AppColors.error, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentNotice extends StatelessWidget {
  _PaymentNotice({
    required this.icon,
    required this.title,
    required this.text,
    required this.color,
  });
  final IconData icon;
  final String title;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 42),
          SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 6),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _PaymentStatusView extends StatelessWidget {
  _PaymentStatusView({
    required this.transaction,
    required this.pending,
    required this.checking,
    required this.error,
    required this.onRefresh,
    required this.onClose,
  });
  final PaiementTransaction transaction;
  final bool pending;
  final bool checking;
  final String? error;
  final VoidCallback onRefresh;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final rawStatus = transaction.statut;
    final status = rawStatus.toLowerCase();
    final label = rawStatus.toUpperCase();
    final success = status == 'success' || status == 'complete';
    final failed =
        status == 'failed' ||
        status == 'echoue' ||
        status == 'cancelled' ||
        status == 'refunded' ||
        status == 'rembourse';
    final color = success
        ? AppColors.primary
        : failed
        ? AppColors.error
        : AppColors.warning;
    return Column(
      children: [
        _PaymentNotice(
          icon: success
              ? Icons.check_circle_rounded
              : failed
              ? Icons.cancel_rounded
              : Icons.hourglass_top_rounded,
          title: success
              ? 'Paiement réussi'
              : failed
              ? 'Paiement non confirmé'
              : 'Paiement en attente',
          text: success
              ? 'Votre abonnement est activé. Vous pouvez continuer à recevoir des demandes.'
              : failed
              ? 'La transaction est $label. Vous pouvez réessayer.'
              : 'Confirmez la transaction sur votre téléphone. Le statut se met à jour automatiquement.',
          color: color,
        ),
        SizedBox(height: 14),
        _AbInfoRow(
          icon: Icons.receipt_long_rounded,
          label: 'Référence',
          value: transaction.referenceTransaction.isEmpty
              ? '-'
              : transaction.referenceTransaction,
        ),
        SizedBox(height: 10),
        _AbInfoRow(
          icon: Icons.payments_rounded,
          label: 'Montant',
          value: '${transaction.montant} ${transaction.devise}',
        ),
        SizedBox(height: 10),
        _AbInfoRow(
          icon: Icons.info_outline_rounded,
          label: 'Statut',
          value: status,
          valueColor: color,
        ),
        if (pending) ...[
          SizedBox(height: 18),
          GestureDetector(
            onTap: checking ? null : onRefresh,
            child: Container(
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primarySurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.24),
                ),
              ),
              child: checking
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                        strokeWidth: 2.2,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.refresh_rounded,
                          color: AppColors.primary,
                          size: 18,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Vérifier maintenant',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
        if (error != null) ...[
          SizedBox(height: 12),
          _PaymentInlineError(message: error!),
        ],
        if (success || failed) ...[
          SizedBox(height: 18),
          GestureDetector(
            onTap: onClose,
            child: Container(
              height: 50,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Text(
                'Fermer',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ── Souscription sheet ────────────────────────────────────────────────────────

class _SouscriptionSheet extends StatefulWidget {
  _SouscriptionSheet({required this.abonnement, required this.onSuccess});

  final AbonnementStatut? abonnement;
  final VoidCallback onSuccess;

  @override
  State<_SouscriptionSheet> createState() => _SouscriptionSheetState();
}

class _SouscriptionSheetState extends State<_SouscriptionSheet> {
  bool _loadingTarifs = true;
  List<TarifAbonnement> _tarifs = [];
  String? _selectedType;
  String? _selectedMethod;
  bool _submitting = false;
  String? _error;
  String? _successMsg;

  bool get _isRenouvellement => widget.abonnement?.abonnementActifId != null;

  @override
  void initState() {
    super.initState();
    if (_isRenouvellement) {
      final existing = widget.abonnement?.abonnementActif;
      _selectedType = existing?['type_abonnement'] as String?;
    }
    _loadTarifs();
  }

  Future<void> _loadTarifs() async {
    try {
      final list = await AuthService.instance.getTarifsAbonnement();
      if (!mounted) return;
      setState(() {
        _tarifs = list;
        _loadingTarifs = false;
        if (!_isRenouvellement && list.length == 1) {
          _selectedType = list.first.typeAbonnement;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingTarifs = false;
      });
    }
  }

  Future<void> _submit() async {
    if (!_isRenouvellement && _selectedType == null) {
      setState(() {
        _error = 'Veuillez choisir un plan.';
      });
      return;
    }
    if (_selectedMethod == null) {
      setState(() {
        _error = 'Veuillez choisir un mode de paiement.';
      });
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> res;
      if (_isRenouvellement) {
        res = await AuthService.instance.renouvelerAbonnement(
          abonnementId: widget.abonnement!.abonnementActifId!,
          methodePaiement: _selectedMethod!,
        );
      } else {
        res = await AuthService.instance.souscrireAbonnement(
          typeAbonnement: _selectedType!,
          methodePaiement: _selectedMethod!,
        );
      }
      if (!mounted) return;
      if (res['success'] == true) {
        setState(() {
          _submitting = false;
          _successMsg =
              res['message'] as String? ?? 'Abonnement souscrit avec succès !';
        });
        await Future.delayed(Duration(seconds: 2));
        if (!mounted) return;
        Navigator.pop(context);
        widget.onSuccess();
      } else {
        setState(() {
          _submitting = false;
          _error = res['message'] as String? ?? 'Une erreur est survenue.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = userFriendlyError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: Color(0xFFF5FDF9),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            SizedBox(height: 12),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            // ── Header ──────────────────────────────────────────────────
            Container(
              margin: EdgeInsets.fromLTRB(20, 16, 20, 0),
              padding: EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.workspace_premium_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isRenouvellement
                              ? 'Renouveler mon abonnement'
                              : 'Choisir un abonnement',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          _isRenouvellement
                              ? 'Continuez à profiter de toutes les fonctionnalités.'
                              : 'Activez votre compte prestataire.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // ── Body ────────────────────────────────────────────────────
            Expanded(
              child: ListView(
                controller: controller,
                padding: EdgeInsets.fromLTRB(20, 16, 20, 32),
                children: [
                  if (_successMsg != null) ...[
                    SizedBox(height: 24),
                    Container(
                      padding: EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppColors.primarySurface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.check_circle_rounded,
                            color: AppColors.primary,
                            size: 52,
                          ),
                          SizedBox(height: 14),
                          Text(
                            _successMsg!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    // ── Plan selection ─────────────────────────────────
                    if (!_isRenouvellement) ...[
                      _SheetLabel('Choisir un plan'),
                      SizedBox(height: 10),
                      if (_loadingTarifs)
                        Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary,
                            ),
                          ),
                        )
                      else
                        ..._tarifs.map(
                          (t) => _PlanCard(
                            tarif: t,
                            selected: _selectedType == t.typeAbonnement,
                            onTap: () => setState(
                              () => _selectedType = t.typeAbonnement,
                            ),
                          ),
                        ),
                      SizedBox(height: 20),
                    ] else ...[
                      _SheetLabel('Plan sélectionné'),
                      SizedBox(height: 10),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primarySurface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.workspace_premium_rounded,
                              color: AppColors.primary,
                              size: 22,
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _selectedType == 'mensuel'
                                    ? 'Mensuel'
                                    : _selectedType == 'annuel'
                                    ? 'Annuel'
                                    : 'Plan actuel',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.verified_rounded,
                              color: AppColors.primary,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 20),
                    ],
                    // ── Payment method ─────────────────────────────────
                    _SheetLabel('Mode de paiement'),
                    SizedBox(height: 10),
                    _PaymentMethodGrid(
                      selected: _selectedMethod,
                      onChanged: (v) => setState(() => _selectedMethod = v),
                    ),
                    // ── Error ──────────────────────────────────────────
                    if (_error != null) ...[
                      SizedBox(height: 12),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.error.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline_rounded,
                              color: AppColors.error,
                              size: 16,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  color: AppColors.error,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    SizedBox(height: 24),
                    // ── Submit ─────────────────────────────────────────
                    GestureDetector(
                      onTap: _submitting ? null : _submit,
                      child: Container(
                        width: double.infinity,
                        height: 54,
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.38),
                              blurRadius: 14,
                              offset: Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Center(
                          child: _submitting
                              ? SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  _isRenouvellement
                                      ? 'Renouveler mon abonnement'
                                      : 'Souscrire maintenant',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Plan card ─────────────────────────────────────────────────────────────────

class _PlanCard extends StatelessWidget {
  _PlanCard({required this.tarif, required this.selected, required this.onTap});

  final TarifAbonnement tarif;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isAnnuel = tarif.typeAbonnement == 'annuel';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.only(bottom: 10),
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primarySurface
              : Colors.white.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.divider,
            width: selected ? 2.0 : 1.2,
          ),
          boxShadow: [
            if (selected)
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.18),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primary.withValues(alpha: 0.15)
                    : AppColors.primarySurface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isAnnuel ? Icons.star_rounded : Icons.calendar_month_rounded,
                color: selected ? AppColors.primary : AppColors.primaryLight,
                size: 22,
              ),
            ),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tarif.typeDisplay,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? AppColors.primary
                          : AppColors.textPrimary,
                    ),
                  ),
                  if (tarif.description.isNotEmpty) ...[
                    SizedBox(height: 2),
                    Text(
                      tarif.description.length > 70
                          ? '${tarif.description.substring(0, 70)}…'
                          : tarif.description,
                      maxLines: 2,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '\$${tarif.prix}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: selected ? AppColors.primary : AppColors.textPrimary,
                  ),
                ),
                Text(
                  isAnnuel ? '/ an' : '/ mois',
                  style: TextStyle(fontSize: 11, color: AppColors.textHint),
                ),
              ],
            ),
            if (selected) ...[
              SizedBox(width: 8),
              Icon(
                Icons.check_circle_rounded,
                color: AppColors.primary,
                size: 20,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Payment method grid ───────────────────────────────────────────────────────

class _PaymentMethodGrid extends StatelessWidget {
  _PaymentMethodGrid({required this.selected, required this.onChanged});

  final String? selected;
  final ValueChanged<String> onChanged;

  static final _methods = [
    (value: 'mobile', label: 'Mobile', icon: Icons.smartphone_rounded),
    (value: 'carte', label: 'Carte', icon: Icons.credit_card_rounded),
    (value: 'transfert', label: 'Transfert', icon: Icons.swap_horiz_rounded),
    (value: 'especes', label: 'Espèces', icon: Icons.payments_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 2.9,
      children: _methods.map((m) {
        final sel = selected == m.value;
        return GestureDetector(
          onTap: () => onChanged(m.value),
          child: Container(
            decoration: BoxDecoration(
              color: sel
                  ? AppColors.primarySurface
                  : Colors.white.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: sel ? AppColors.primary : AppColors.divider,
                width: sel ? 2.0 : 1.2,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  m.icon,
                  color: sel ? AppColors.primary : AppColors.textSecondary,
                  size: 18,
                ),
                SizedBox(width: 7),
                Text(
                  m.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                    color: sel ? AppColors.primary : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Prestataire profile section ───────────────────────────────────────────────

class _PrestataireProfileSection extends StatelessWidget {
  _PrestataireProfileSection({
    required this.loading,
    required this.error,
    required this.profil,
    required this.onRetry,
    required this.onEdit,
    required this.onViewPhotos,
    required this.onAddPhoto,
  });

  final bool loading;
  final String? error;
  final MonProfilPrestataire? profil;
  final VoidCallback onRetry;
  final VoidCallback onEdit;
  final VoidCallback onViewPhotos;
  final VoidCallback onAddPhoto;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                Icons.work_outline_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Mon activité prestataire',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            if (!loading && error == null && profil != null)
              GestureDetector(
                onTap: onEdit,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.primarySurface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.edit_outlined,
                        color: AppColors.primary,
                        size: 14,
                      ),
                      SizedBox(width: 5),
                      Text(
                        'Modifier',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        SizedBox(height: 14),

        // Card content
        ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.78),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.glassBorder, width: 1.4),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.glassShadow,
                    blurRadius: 28,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: loading
                  ? Padding(
                      padding: EdgeInsets.symmetric(vertical: 28),
                      child: Center(
                        child: SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(
                            color: AppColors.primary,
                            strokeWidth: 2.4,
                          ),
                        ),
                      ),
                    )
                  : error != null
                  ? Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Column(
                        children: [
                          Icon(
                            Icons.cloud_off_outlined,
                            color: AppColors.textHint,
                            size: 32,
                          ),
                          SizedBox(height: 10),
                          Text(
                            error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          SizedBox(height: 14),
                          GestureDetector(
                            onTap: onRetry,
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                gradient: AppColors.primaryGradient,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'Réessayer',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : profil == null
                  ? SizedBox.shrink()
                  : _PrestataireDetails(
                      profil: profil!,
                      onViewPhotos: onViewPhotos,
                      onAddPhoto: onAddPhoto,
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PrestataireDetails extends StatelessWidget {
  _PrestataireDetails({
    required this.profil,
    required this.onViewPhotos,
    required this.onAddPhoto,
  });
  final MonProfilPrestataire profil;
  final VoidCallback onViewPhotos;
  final VoidCallback onAddPhoto;

  @override
  Widget build(BuildContext context) {
    final adresse = [
      if (profil.adresseRue != null && profil.adresseRue!.isNotEmpty)
        profil.adresseRue!,
      if (profil.commune.isNotEmpty) profil.commune,
      if (profil.ville.isNotEmpty) profil.ville,
    ].join(', ');

    return Column(
      children: [
        // Statut validé / en attente
        Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: profil.estValide
                      ? AppColors.primarySurface
                      : Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  profil.estValide
                      ? Icons.verified_rounded
                      : Icons.schedule_rounded,
                  color: profil.estValide
                      ? AppColors.primary
                      : AppColors.warning,
                  size: 18,
                ),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Statut',
                      style: TextStyle(
                        color: AppColors.textHint,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      profil.estValide
                          ? 'Compte validé ✓'
                          : 'En attente de validation',
                      style: TextStyle(
                        color: profil.estValide
                            ? AppColors.primary
                            : AppColors.warning,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Divider(color: AppColors.divider, height: 1),
        _InfoRow(
          icon: Icons.design_services_outlined,
          label: profil.serviceNames.length > 1
              ? 'Services proposés'
              : 'Service proposé',
          value: profil.servicesLabel,
        ),
        if (adresse.isNotEmpty) ...[
          Divider(color: AppColors.divider, height: 1),
          _InfoRow(
            icon: Icons.location_on_outlined,
            label: 'Adresse',
            value: adresse,
          ),
        ],
        if (profil.presentation.isNotEmpty) ...[
          Divider(color: AppColors.divider, height: 1),
          _InfoRow(
            icon: Icons.info_outline_rounded,
            label: 'Présentation',
            value: profil.presentation,
          ),
        ],
        if (profil.niveau.isNotEmpty ||
            profil.scoreNiveau > 0 ||
            profil.missionsReussies > 0) ...[
          Divider(color: AppColors.divider, height: 1),
          _InfoRow(
            icon: Icons.workspace_premium_rounded,
            label: 'Niveau',
            value:
                '${_capitalize(profil.niveau.isEmpty ? 'Non calculé' : profil.niveau)} • ${profil.scoreNiveau} pts',
          ),
          Divider(color: AppColors.divider, height: 1),
          _InfoRow(
            icon: Icons.star_rounded,
            label: 'Note moyenne',
            value: profil.noteMoyenne == null
                ? '—'
                : profil.noteMoyenne!.toStringAsFixed(1),
          ),
          Divider(color: AppColors.divider, height: 1),
          _InfoRow(
            icon: Icons.task_alt_rounded,
            label: 'Missions réussies',
            value: '${profil.missionsReussies}',
          ),
          Divider(color: AppColors.divider, height: 1),
          _InfoRow(
            icon: Icons.reply_all_rounded,
            label: 'Taux réponse',
            value: '${profil.tauxReponse}%',
          ),
          Divider(color: AppColors.divider, height: 1),
          _InfoRow(
            icon: Icons.sentiment_satisfied_alt_rounded,
            label: 'Satisfaction',
            value: '${profil.tauxSatisfaction}%',
          ),
          Divider(color: AppColors.divider, height: 1),
          _InfoRow(
            icon: Icons.handshake_rounded,
            label: 'Respect engagements',
            value: '${profil.tauxRespectEngagements}%',
          ),
          if (profil.dateDernierCalculNiveau != null &&
              profil.dateDernierCalculNiveau!.isNotEmpty) ...[
            Divider(color: AppColors.divider, height: 1),
            _InfoRow(
              icon: Icons.update_rounded,
              label: 'Dernier calcul',
              value: _formatDate(profil.dateDernierCalculNiveau!),
            ),
          ],
        ],
        Divider(color: AppColors.divider, height: 1),
        // ── Photos row ──────────────────────────────────────────────
        if (profil.photos.isEmpty)
          _InfoRow(
            icon: Icons.photo_library_outlined,
            label: 'Photos de portfolio',
            value: 'Aucune photo',
          )
        else
          GestureDetector(
            onTap: onViewPhotos,
            child: _InfoRow(
              icon: Icons.photo_library_outlined,
              label: 'Photos de portfolio',
              value:
                  '${profil.photos.length} photo${profil.photos.length > 1 ? 's' : ''} • voir',
              tappable: true,
            ),
          ),
        Divider(color: AppColors.divider, height: 1),
        // ── Add photos row ───────────────────────────────────────────
        GestureDetector(
          onTap: onAddPhoto,
          child: _InfoRow(
            icon: Icons.add_photo_alternate_outlined,
            label: 'Ajouter des photos',
            value: 'Enrichir votre portfolio',
            tappable: true,
          ),
        ),
        if (profil.dateDebutAbonnement != null ||
            profil.dateFinAbonnement != null) ...[
          Divider(color: AppColors.divider, height: 1),
          _InfoRow(
            icon: Icons.card_membership_rounded,
            label: 'Abonnement',
            value: profil.dateFinAbonnement != null
                ? 'Valide jusqu\'au ${_formatDate(profil.dateFinAbonnement!)}'
                : 'Actif',
          ),
        ],
      ],
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return '${dt.day.toString().padLeft(2, '0')}/'
          '${dt.month.toString().padLeft(2, '0')}/'
          '${dt.year}';
    } catch (_) {
      return iso;
    }
  }

  String _capitalize(String value) {
    if (value.isEmpty) return value;
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }
}

class _MesAvisPrestataireCard extends StatelessWidget {
  _MesAvisPrestataireCard({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: enabled ? 0.78 : 0.55),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppColors.glassBorder, width: 1.4),
              boxShadow: [
                BoxShadow(
                  color: AppColors.glassShadow,
                  blurRadius: 24,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.star_rounded,
                    color: AppColors.warning,
                    size: 22,
                  ),
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mes avis clients',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Consulter les notes, commentaires et retours',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: enabled ? AppColors.primary : AppColors.textHint,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AvisClientTile extends StatelessWidget {
  _AvisClientTile({required this.rating});
  final Notation rating;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primarySurface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  rating.utilisateur.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              Row(
                children: List.generate(
                  5,
                  (i) => Icon(
                    i < rating.note
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    color: AppColors.warning,
                    size: 15,
                  ),
                ),
              ),
            ],
          ),
          if (rating.avis.isNotEmpty) ...[
            SizedBox(height: 8),
            Text(
              rating.avis,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AvisSummaryCard extends StatelessWidget {
  _AvisSummaryCard({required this.avis});

  final NotationsResponse avis;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.glassBorder, width: 1.4),
            boxShadow: [
              BoxShadow(
                color: AppColors.glassShadow,
                blurRadius: 28,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Text(
                avis.averageRating.toStringAsFixed(1),
                style: TextStyle(
                  color: AppColors.warning,
                  fontSize: 42,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: List.generate(
                        5,
                        (i) => Icon(
                          i < avis.averageRating.round()
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          color: AppColors.warning,
                          size: 20,
                        ),
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      '${avis.totalRatings} retour${avis.totalRatings > 1 ? 's' : ''} client${avis.totalRatings > 1 ? 's' : ''}',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AvisEmpty extends StatelessWidget {
  _AvisEmpty();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 10),
      child: Text(
        'Aucun avis client pour le moment.',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
      ),
    );
  }
}

class _AvisError extends StatelessWidget {
  _AvisError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        SizedBox(height: 12),
        GestureDetector(
          onTap: onRetry,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 18, vertical: 9),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Réessayer',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Add-photos sheet ─────────────────────────────────────────────────────────

class _AddPhotosSheetBody extends StatefulWidget {
  _AddPhotosSheetBody({required this.onUploaded});
  final VoidCallback onUploaded;

  @override
  State<_AddPhotosSheetBody> createState() => _AddPhotosSheetBodyState();
}

class _AddPhotosSheetBodyState extends State<_AddPhotosSheetBody> {
  final _picker = ImagePicker();

  // Each entry: {file: File, desc: TextEditingController}
  final List<Map<String, dynamic>> _items = [];
  bool _uploading = false;
  int _uploadedCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _pickImages();
    });
  }

  @override
  void dispose() {
    for (final item in _items) {
      (item['desc'] as TextEditingController).dispose();
    }
    super.dispose();
  }

  Future<void> _pickImages() async {
    final picked = await _picker.pickMultiImage(imageQuality: 85);
    if (picked.isEmpty) return;
    setState(() {
      for (final xf in picked) {
        _items.add({
          'file': File(xf.path),
          'name': xf.name,
          'desc': TextEditingController(),
        });
      }
    });
  }

  void _removeItem(int index) {
    final ctrl = _items[index]['desc'] as TextEditingController;
    ctrl.dispose();
    setState(() => _items.removeAt(index));
  }

  Future<void> _upload() async {
    if (_items.isEmpty) return;
    setState(() {
      _uploading = true;
      _uploadedCount = 0;
    });
    int successCount = 0;
    String? lastError;
    for (final item in _items) {
      try {
        await PrestataireService.instance.addPhoto(
          image: item['file'] as File,
          description: (item['desc'] as TextEditingController).text.trim(),
        );
        successCount++;
        if (mounted) setState(() => _uploadedCount++);
      } catch (e) {
        lastError = e.toString();
      }
    }
    if (!mounted) return;
    setState(() => _uploading = false);
    if (successCount > 0) widget.onUploaded();
    Navigator.of(context).pop();
    debugPrint(
      lastError == null
          ? '[Profile] $successCount photo(s) ajoutée(s).'
          : '[Profile] upload photos partial error: $lastError',
    );
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
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
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  Icons.add_photo_alternate_outlined,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              SizedBox(width: 10),
              Text(
                'Ajouter des photos',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          SizedBox(height: 18),

          _PickBtn(
            icon: Icons.photo_library_outlined,
            label: _items.isEmpty
                ? 'Choisir dans la galerie'
                : 'Ajouter encore',
            onTap: _uploading ? null : _pickImages,
          ),

          // Selected images list
          if (_items.isNotEmpty) ...[
            SizedBox(height: 16),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.35,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _items.length,
                separatorBuilder: (_, __) => SizedBox(height: 12),
                itemBuilder: (ctx, i) {
                  final file = _items[i]['file'] as File;
                  final name =
                      (_items[i]['name'] as String?) ??
                      file.path.split('/').last;
                  final ctrl = _items[i]['desc'] as TextEditingController;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Thumbnail
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(
                          file,
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                        ),
                      ),
                      SizedBox(width: 12),
                      // Description field
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: 6),
                            TextField(
                              controller: ctrl,
                              enabled: !_uploading,
                              decoration: InputDecoration(
                                hintText: 'Description (optionnelle)',
                                hintStyle: TextStyle(
                                  color: AppColors.textHint,
                                  fontSize: 13,
                                ),
                                filled: true,
                                fillColor: Colors.white,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: AppColors.glassBorder,
                                    width: 1.2,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: AppColors.glassBorder,
                                    width: 1.2,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: AppColors.primary,
                                    width: 1.6,
                                  ),
                                ),
                              ),
                              style: TextStyle(fontSize: 13),
                              maxLines: 2,
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: 8),
                      // Remove button
                      if (!_uploading)
                        GestureDetector(
                          onTap: () => _removeItem(i),
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.close_rounded,
                              color: Colors.red.shade400,
                              size: 16,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],

          SizedBox(height: 20),

          // Upload progress indicator
          if (_uploading)
            Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$_uploadedCount / ${_items.length} photo${_items.length > 1 ? 's' : ''} envoyée${_items.length > 1 ? 's' : ''}...',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: _items.isEmpty
                        ? null
                        : _uploadedCount / _items.length,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.primary,
                    ),
                    borderRadius: BorderRadius.circular(4),
                    minHeight: 5,
                  ),
                ],
              ),
            ),

          // Submit button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: GestureDetector(
              onTap: (_uploading || _items.isEmpty) ? null : _upload,
              child: Container(
                decoration: BoxDecoration(
                  gradient: (_uploading || _items.isEmpty)
                      ? null
                      : AppColors.primaryGradient,
                  color: (_uploading || _items.isEmpty)
                      ? AppColors.textHint.withValues(alpha: 0.2)
                      : null,
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: _uploading
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.4,
                        ),
                      )
                    : Text(
                        _items.isEmpty
                            ? 'Sélectionner des photos'
                            : 'Envoyer ${_items.length} photo${_items.length > 1 ? 's' : ''}',
                        style: TextStyle(
                          color: _items.isEmpty
                              ? AppColors.textHint
                              : Colors.white,
                          fontWeight: FontWeight.w600,
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

class _PickBtn extends StatelessWidget {
  _PickBtn({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.glassBorder, width: 1.4),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: AppColors.primary),
            SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Portfolio gallery viewer ─────────────────────────────────────────────────

class _ProfileGallery extends StatefulWidget {
  _ProfileGallery({
    required this.photos,
    required this.initialIndex,
    this.onPhotoDeleted,
  });
  final List<PrestatairePhoto> photos;
  final int initialIndex;
  final VoidCallback? onPhotoDeleted;

  @override
  State<_ProfileGallery> createState() => _ProfileGalleryState();
}

class _ProfileGalleryState extends State<_ProfileGallery> {
  late final PageController _pageCtrl;
  final ScrollController _thumbCtrl = ScrollController();
  late int _current;
  late List<PrestatairePhoto> _photos;
  bool _deleting = false;

  static double _thumbSize = 52;
  static double _thumbSpacing = 6;

  @override
  void initState() {
    super.initState();
    _photos = List<PrestatairePhoto>.from(widget.photos);
    _current = widget.initialIndex.clamp(0, widget.photos.length - 1);
    _pageCtrl = PageController(initialPage: _current);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _thumbCtrl.dispose();
    super.dispose();
  }

  double _thumbOffset(int i) =>
      i * (_thumbSize + _thumbSpacing) - (_thumbSize + _thumbSpacing) * 2;

  void _goTo(int i) {
    _pageCtrl.jumpToPage(i);
    final offset = _thumbOffset(i).clamp(
      0.0,
      _thumbCtrl.hasClients
          ? _thumbCtrl.position.maxScrollExtent
          : double.infinity,
    );
    if (_thumbCtrl.hasClients) {
      _thumbCtrl.animateTo(
        offset,
        duration: Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Color(0xFF1C1C1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          'Supprimer la photo',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Cette photo sera définitivement supprimée de votre portfolio.',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Annuler', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Supprimer',
              style: TextStyle(
                color: Colors.red.shade400,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _deleting = true);
    try {
      await PrestataireService.instance.deletePhoto(_photos[_current].id);
      if (!mounted) return;
      widget.onPhotoDeleted?.call();
      final newPhotos = List<PrestatairePhoto>.from(_photos)
        ..removeAt(_current);
      if (newPhotos.isEmpty) {
        Navigator.of(context).pop();
        return;
      }
      final newIndex = _current.clamp(0, newPhotos.length - 1);
      setState(() {
        _photos = newPhotos;
        _current = newIndex;
        _deleting = false;
      });
      _pageCtrl.jumpToPage(newIndex);
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      debugPrint('[Profile] delete photo error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final photos = _photos;
    return Scaffold(
      backgroundColor: Colors.black87,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Main viewer
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

          // Top bar
          SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                  SizedBox(width: 10),
                  // Delete button
                  GestureDetector(
                    onTap: _deleting ? null : _confirmDelete,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.red.withValues(alpha: 0.45),
                              width: 1.2,
                            ),
                          ),
                          child: _deleting
                              ? Padding(
                                  padding: EdgeInsets.all(10),
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  Icons.delete_outline_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom: description + thumbnails
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
                ),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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

// ── Helper widgets ────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool tappable;

  _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.tappable = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.primarySurface,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: AppColors.primary, size: 18),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: AppColors.textHint,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    color: tappable ? AppColors.primary : AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (tappable)
            Icon(
              Icons.chevron_right_rounded,
              color: AppColors.primary,
              size: 18,
            ),
        ],
      ),
    );
  }
}

class _RowDivider extends StatelessWidget {
  _RowDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(color: AppColors.divider, height: 1);
  }
}

class _AvatarInitial extends StatelessWidget {
  final String initial;
  _AvatarInitial({required this.initial});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 36,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

// ── Bottom-sheet helpers ──────────────────────────────────────────────────────

Future<List<ServiceDisponible>> _loadAvailableServices() async {
  return PrestataireService.instance.getServices(pageSize: 500);
}

Future<List<ServiceDisponible>?> _showServiceTypePicker({
  required BuildContext context,
  required List<ServiceDisponible> services,
  required Set<int> selectedIds,
}) {
  return showModalBottomSheet<List<ServiceDisponible>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        _ServiceTypePickerModal(services: services, selectedIds: selectedIds),
  );
}

class _ServiceTypePickerModal extends StatefulWidget {
  _ServiceTypePickerModal({required this.services, required this.selectedIds});

  final List<ServiceDisponible> services;
  final Set<int> selectedIds;

  @override
  State<_ServiceTypePickerModal> createState() =>
      _ServiceTypePickerModalState();
}

class _ServiceTypePickerModalState extends State<_ServiceTypePickerModal> {
  late final TextEditingController _searchCtrl;
  late List<ServiceDisponible> _filtered;
  late Set<int> _selectedIds;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController();
    _filtered = List<ServiceDisponible>.from(widget.services);
    _selectedIds = Set<int>.from(widget.selectedIds);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _filter(String value) {
    final query = value.trim().toLowerCase();
    setState(() {
      _filtered = widget.services
          .where((service) => service.nom.toLowerCase().contains(query))
          .toList();
    });
  }

  List<ServiceDisponible> get _selectedServices => widget.services
      .where((service) => _selectedIds.contains(service.id))
      .toList();

  void _validate() => Navigator.of(context).pop(_selectedServices);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              height: MediaQuery.of(context).size.height * 0.72,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: AppColors.glassBorder, width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.glassShadow,
                    blurRadius: 26,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(18, 14, 18, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Services proposés',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: AppColors.primarySurface,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.close_rounded,
                              color: AppColors.primary,
                              size: 19,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(18, 0, 18, 10),
                    child: TextField(
                      controller: _searchCtrl,
                      autofocus: true,
                      onChanged: _filter,
                      decoration: InputDecoration(
                        hintText: 'Rechercher un service...',
                        hintStyle: TextStyle(
                          color: AppColors.textHint,
                          fontSize: 13,
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: AppColors.primary,
                          size: 19,
                        ),
                        filled: true,
                        fillColor: AppColors.primarySurface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: widget.services.isEmpty
                        ? Center(
                            child: CircularProgressIndicator(
                              color: AppColors.primary,
                              strokeWidth: 2,
                            ),
                          )
                        : _filtered.isEmpty
                        ? Center(
                            child: Text(
                              'Aucun service trouvé',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _filtered.length,
                            padding: EdgeInsets.only(bottom: 12),
                            itemBuilder: (_, index) {
                              final service = _filtered[index];
                              final isSelected = _selectedIds.contains(
                                service.id,
                              );
                              return InkWell(
                                onTap: () {
                                  setState(() {
                                    if (isSelected) {
                                      _selectedIds.remove(service.id);
                                    } else {
                                      _selectedIds.add(service.id);
                                    }
                                  });
                                },
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 14,
                                  ),
                                  color: isSelected
                                      ? AppColors.primarySurface
                                      : Colors.transparent,
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          service.nom,
                                          style: TextStyle(
                                            color: isSelected
                                                ? AppColors.primary
                                                : AppColors.textPrimary,
                                            fontSize: 14,
                                            fontWeight: isSelected
                                                ? FontWeight.w800
                                                : FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                      if (isSelected)
                                        Icon(
                                          Icons.check_rounded,
                                          color: AppColors.primary,
                                          size: 18,
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  Container(
                    padding: EdgeInsets.fromLTRB(18, 12, 18, 18),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.96),
                      border: Border(
                        top: BorderSide(color: AppColors.divider, width: 1),
                      ),
                    ),
                    child: GestureDetector(
                      onTap: _validate,
                      child: Container(
                        height: 50,
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.26),
                              blurRadius: 16,
                              offset: Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            _selectedIds.isEmpty
                                ? 'Valider'
                                : 'Valider (${_selectedIds.length})',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
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

class _SheetLabel extends StatelessWidget {
  final String text;
  _SheetLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
      ),
    );
  }
}

class _SheetField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscure;
  final TextInputAction textInputAction;
  final VoidCallback onToggleObscure;
  final FormFieldValidator<String>? validator;
  final bool showToggle;
  final TextInputType? keyboardType;

  _SheetField({
    required this.controller,
    required this.hint,
    required this.icon,
    required this.obscure,
    required this.textInputAction,
    required this.onToggleObscure,
    this.validator,
    this.showToggle = true,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      textInputAction: textInputAction,
      keyboardType: keyboardType,
      validator: validator,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: AppColors.textHint,
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.65),
        contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        prefixIcon: Padding(
          padding: EdgeInsets.only(left: 14, right: 10),
          child: Icon(icon, color: AppColors.primary, size: 19),
        ),
        prefixIconConstraints: BoxConstraints(),
        suffixIcon: showToggle
            ? Padding(
                padding: EdgeInsets.only(right: 14),
                child: GestureDetector(
                  onTap: onToggleObscure,
                  child: Icon(
                    obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 20,
                    color: AppColors.textHint,
                  ),
                ),
              )
            : null,
        suffixIconConstraints: BoxConstraints(),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColors.divider, width: 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColors.divider, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColors.primary, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColors.error, width: 1.4),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColors.error, width: 1.8),
        ),
        errorStyle: TextStyle(fontSize: 11, color: AppColors.error),
      ),
    );
  }
}

class _SheetErrorBanner extends StatelessWidget {
  final String message;
  _SheetErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.error.withValues(alpha: 0.25),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: AppColors.error, size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.error,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetSuccessBanner extends StatelessWidget {
  final String message;
  _SheetSuccessBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.25),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_outline_rounded,
            color: AppColors.primary,
            size: 18,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Become Provider Sheet
// ═══════════════════════════════════════════════════════════════════════════
class _BecomeProviderSheet extends StatefulWidget {
  _BecomeProviderSheet();

  @override
  State<_BecomeProviderSheet> createState() => _BecomeProviderSheetState();
}

class _BecomeProviderSheetState extends State<_BecomeProviderSheet> {
  final _formKey = GlobalKey<FormState>();
  final _adresseRueCtrl = TextEditingController();
  final _communeSearchCtrl = TextEditingController();
  final _serviceSearchCtrl = TextEditingController();
  final _villeCtrl = TextEditingController(text: 'Kinshasa');
  final _presentationCtrl = TextEditingController();

  // ── type de service dropdown ────────────────────────────────────────────
  String? _selectedTypeService;
  final Set<int> _selectedServiceIds = {};
  List<ServiceDisponible> _servicesList = [];
  List<ServiceDisponible> _filteredServices = [];
  bool _showServiceList = false;

  // ── commune dropdown ────────────────────────────────────────────────────
  String? _selectedVille = 'Kinshasa';
  String? _selectedCommune;
  bool _showCommuneList = false;
  List<String> _filteredCommunes = Locations.communesDe('Kinshasa');

  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadServices();
  }

  Future<void> _loadServices() async {
    try {
      final list = await _loadAvailableServices();
      if (!mounted) return;
      setState(() {
        _servicesList = list;
        _filteredServices = list;
      });
    } catch (_) {}
  }

  void _filterServices(String q) {
    final lower = q.toLowerCase();
    setState(() {
      _filteredServices = _servicesList
          .where((s) => s.nom.toLowerCase().contains(lower))
          .toList();
    });
  }

  List<ServiceDisponible> get _selectedServices => _servicesList
      .where((service) => _selectedServiceIds.contains(service.id))
      .toList();

  String get _selectedServicesLabel {
    final selected = _selectedServices.map((service) => service.nom).toList();
    if (selected.isEmpty) return 'Sélectionner un ou plusieurs services';
    if (selected.length <= 2) return selected.join(', ');
    return '${selected.take(2).join(', ')} +${selected.length - 2}';
  }

  void _filterCommunes(String q) {
    final lower = q.toLowerCase();
    setState(() {
      _filteredCommunes = Locations.communesDe(_villeCtrl.text.trim())
          .where((c) => c.toLowerCase().contains(lower))
          .toList();
    });
  }

  @override
  void dispose() {
    _adresseRueCtrl.dispose();
    _serviceSearchCtrl.dispose();
    _communeSearchCtrl.dispose();
    _villeCtrl.dispose();
    _presentationCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await AuthService.instance.becomeProvider(
        typeService: _selectedTypeService ?? '',
        serviceIds: _selectedServiceIds.where((id) => id > 0).toList(),
        adresseRue: _adresseRueCtrl.text.trim(),
        commune: _selectedCommune ?? '',
        ville: _selectedVille?.trim() ?? '',
        presentation: _presentationCtrl.text.trim(),
      );
      if (!mounted) return;
      if (res['success'] == true) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _error = (res['message'] as String?) ?? 'Une erreur est survenue.';
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = userFriendlyError(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return ClipRRect(
      borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottom),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
            border: Border.all(color: AppColors.glassBorder, width: 1.3),
          ),
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Handle bar
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // ── Title
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.work_outline_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Devenir prestataire',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            'Complétez votre profil professionnel',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  SizedBox(height: 24),
 // ── Ville (liste déroulante) ───────────────────────────
                  _SheetLabel('Ville'),
                  SizedBox(height: 8),
                  FormField<String>(
                    initialValue: _selectedVille,
                    validator: (_) => _selectedVille == null
                        ? 'Veuillez sélectionner une ville'
                        : null,
                    builder: (field) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ProviderInlineDropdown<String>(
                          value: _selectedVille,
                          placeholder: 'Sélectionner une ville',
                          icon: Icons.location_city_outlined,
                          options: Locations.nomsVilles,
                          onChanged: (v) {
                            FocusScope.of(context).unfocus();
                            setState(() {
                              _selectedVille = v;
                              _villeCtrl.text = v ?? '';
                              // La commune dépend de la ville.
                              if (!Locations.communeAppartientA(
                                commune: _selectedCommune,
                                ville: v,
                              )) {
                                _selectedCommune = null;
                                _communeSearchCtrl.clear();
                              }
                              _showCommuneList = false;
                            });
                            field.didChange(v);
                          },
                        ),
                        if (field.hasError) ...[
                          SizedBox(height: 6),
                          Text(
                            field.errorText!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.error,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(height: 14),
                  // ── Commune — dropdown search ──────────────────────────
                  _SheetLabel('Commune'),
                  SizedBox(height: 8),
                  FormField<String>(
                    initialValue: _selectedCommune,
                    validator: (_) => _selectedCommune == null
                        ? 'Veuillez sélectionner une commune'
                        : null,
                    builder: (field) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        GestureDetector(
                          onTap: () => setState(() {
                            _showCommuneList = !_showCommuneList;
                            if (_showCommuneList) {
                              _communeSearchCtrl.clear();
                              _filteredCommunes = Locations.communesDe(_villeCtrl.text.trim());
                            }
                          }),
                          child: Container(
                            height: 52,
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: field.hasError
                                    ? AppColors.error
                                    : _showCommuneList
                                    ? AppColors.primary
                                    : AppColors.divider,
                                width: (_showCommuneList || field.hasError)
                                    ? 1.8
                                    : 1.2,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.map_outlined,
                                  color: AppColors.primary,
                                  size: 19,
                                ),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _selectedCommune ??
                                        'Sélectionner une commune',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: _selectedCommune != null
                                          ? AppColors.textPrimary
                                          : AppColors.textHint,
                                    ),
                                  ),
                                ),
                                Icon(
                                  _showCommuneList
                                      ? Icons.keyboard_arrow_up_rounded
                                      : Icons.keyboard_arrow_down_rounded,
                                  color: AppColors.textHint,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (field.hasError)
                          Padding(
                            padding: EdgeInsets.only(top: 6, left: 14),
                            child: Text(
                              field.errorText!,
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.error,
                              ),
                            ),
                          ),
                        if (_showCommuneList) ...[
                          SizedBox(height: 6),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.97),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: AppColors.divider,
                                width: 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.glassShadow,
                                  blurRadius: 14,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                Padding(
                                  padding: EdgeInsets.fromLTRB(12, 10, 12, 4),
                                  child: TextField(
                                    controller: _communeSearchCtrl,
                                    autofocus: true,
                                    onChanged: _filterCommunes,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: AppColors.textPrimary,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: 'Rechercher une commune...',
                                      hintStyle: TextStyle(
                                        color: AppColors.textHint,
                                        fontSize: 13,
                                      ),
                                      prefixIcon: Icon(
                                        Icons.search_rounded,
                                        color: AppColors.primary,
                                        size: 18,
                                      ),
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(
                                        vertical: 10,
                                      ),
                                      filled: true,
                                      fillColor: AppColors.primarySurface,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide.none,
                                      ),
                                    ),
                                  ),
                                ),
                                ConstrainedBox(
                                  constraints: BoxConstraints(maxHeight: 200),
                                  child: _filteredCommunes.isEmpty
                                      ? Padding(
                                          padding: EdgeInsets.symmetric(
                                            vertical: 16,
                                          ),
                                          child: Center(
                                            child: Text(
                                              'Aucune commune trouvée',
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: AppColors.textHint,
                                              ),
                                            ),
                                          ),
                                        )
                                      : ListView.builder(
                                          padding: EdgeInsets.only(bottom: 8),
                                          shrinkWrap: true,
                                          itemCount: _filteredCommunes.length,
                                          itemBuilder: (_, i) {
                                            final c = _filteredCommunes[i];
                                            final selected =
                                                c == _selectedCommune;
                                            return GestureDetector(
                                              onTap: () {
                                                setState(() {
                                                  _selectedCommune = c;
                                                  _showCommuneList = false;
                                                });
                                                field.didChange(c);
                                              },
                                              child: Container(
                                                padding: EdgeInsets.symmetric(
                                                  horizontal: 16,
                                                  vertical: 12,
                                                ),
                                                color: selected
                                                    ? AppColors.primarySurface
                                                    : Colors.transparent,
                                                child: Row(
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        c,
                                                        style: TextStyle(
                                                          fontSize: 14,
                                                          fontWeight: selected
                                                              ? FontWeight.w600
                                                              : FontWeight.w400,
                                                          color: selected
                                                              ? AppColors
                                                                    .primary
                                                              : AppColors
                                                                    .textPrimary,
                                                        ),
                                                      ),
                                                    ),
                                                    if (selected)
                                                      Icon(
                                                        Icons.check_rounded,
                                                        color:
                                                            AppColors.primary,
                                                        size: 16,
                                                      ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(height: 14),
                  // ── Type de service — dropdown search ─────────────────
                  _SheetLabel('Services proposés'),
                  SizedBox(height: 8),
                  FormField<String>(
                    initialValue: _selectedTypeService,
                    validator: (_) => _selectedServiceIds.isEmpty
                        ? 'Champ obligatoire'
                        : null,
                    builder: (field) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        GestureDetector(
                          onTap: () async {
                            final selectedServices =
                                await _showServiceTypePicker(
                                  context: context,
                                  services: _servicesList,
                                  selectedIds: _selectedServiceIds,
                                );
                            if (!mounted || selectedServices == null) return;
                            setState(() {
                              _selectedServiceIds
                                ..clear()
                                ..addAll(
                                  selectedServices
                                      .where((service) => service.id > 0)
                                      .map((service) => service.id),
                                );
                              _selectedTypeService = selectedServices.isNotEmpty
                                  ? selectedServices.first.nom
                                  : null;
                              _showServiceList = false;
                            });
                            field.didChange(_selectedTypeService);
                          },
                          child: Container(
                            height: 52,
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: field.hasError
                                    ? AppColors.error
                                    : _showServiceList
                                    ? AppColors.primary
                                    : AppColors.divider,
                                width: (_showServiceList || field.hasError)
                                    ? 1.8
                                    : 1.2,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.design_services_outlined,
                                  color: AppColors.primary,
                                  size: 19,
                                ),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _selectedServicesLabel,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: _selectedServiceIds.isNotEmpty
                                          ? AppColors.textPrimary
                                          : AppColors.textHint,
                                    ),
                                  ),
                                ),
                                Icon(
                                  _showServiceList
                                      ? Icons.keyboard_arrow_up_rounded
                                      : Icons.keyboard_arrow_down_rounded,
                                  color: AppColors.textHint,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (field.hasError)
                          Padding(
                            padding: EdgeInsets.only(top: 6, left: 14),
                            child: Text(
                              field.errorText!,
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.error,
                              ),
                            ),
                          ),
                        if (_showServiceList) ...[
                          SizedBox(height: 6),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.97),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: AppColors.divider,
                                width: 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.glassShadow,
                                  blurRadius: 14,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                Padding(
                                  padding: EdgeInsets.fromLTRB(12, 10, 12, 4),
                                  child: TextField(
                                    controller: _serviceSearchCtrl,
                                    autofocus: true,
                                    onChanged: _filterServices,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: AppColors.textPrimary,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: 'Rechercher un service...',
                                      hintStyle: TextStyle(
                                        color: AppColors.textHint,
                                        fontSize: 13,
                                      ),
                                      prefixIcon: Icon(
                                        Icons.search_rounded,
                                        color: AppColors.primary,
                                        size: 18,
                                      ),
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(
                                        vertical: 10,
                                      ),
                                      filled: true,
                                      fillColor: AppColors.primarySurface,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide.none,
                                      ),
                                    ),
                                  ),
                                ),
                                ConstrainedBox(
                                  constraints: BoxConstraints(maxHeight: 200),
                                  child: _servicesList.isEmpty
                                      ? Padding(
                                          padding: EdgeInsets.symmetric(
                                            vertical: 16,
                                          ),
                                          child: Center(
                                            child: SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: AppColors.primary,
                                              ),
                                            ),
                                          ),
                                        )
                                      : ListView.builder(
                                          padding: EdgeInsets.only(bottom: 8),
                                          shrinkWrap: true,
                                          itemCount: _filteredServices.length,
                                          itemBuilder: (_, i) {
                                            final s = _filteredServices[i];
                                            final selected = _selectedServiceIds
                                                .contains(s.id);
                                            return GestureDetector(
                                              onTap: () {
                                                setState(() {
                                                  if (selected) {
                                                    _selectedServiceIds.remove(
                                                      s.id,
                                                    );
                                                  } else {
                                                    _selectedServiceIds.add(
                                                      s.id,
                                                    );
                                                  }
                                                  _selectedTypeService =
                                                      _selectedServices
                                                          .isNotEmpty
                                                      ? _selectedServices
                                                            .first
                                                            .nom
                                                      : null;
                                                });
                                                field.didChange(
                                                  _selectedTypeService,
                                                );
                                              },
                                              child: Container(
                                                padding: EdgeInsets.symmetric(
                                                  horizontal: 16,
                                                  vertical: 12,
                                                ),
                                                color: selected
                                                    ? AppColors.primarySurface
                                                    : Colors.transparent,
                                                child: Row(
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        s.nom,
                                                        style: TextStyle(
                                                          fontSize: 14,
                                                          fontWeight: selected
                                                              ? FontWeight.w600
                                                              : FontWeight.w400,
                                                          color: selected
                                                              ? AppColors
                                                                    .primary
                                                              : AppColors
                                                                    .textPrimary,
                                                        ),
                                                      ),
                                                    ),
                                                    if (selected)
                                                      Icon(
                                                        Icons.check_rounded,
                                                        color:
                                                            AppColors.primary,
                                                        size: 16,
                                                      ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(height: 14),

                  // ── Présentation
                  _ProviderFormField(
                    controller: _presentationCtrl,
                    label: 'Présentation',
                    hint: 'Décrivez votre expérience et vos compétences…',
                    icon: Icons.notes_rounded,
                    maxLines: 3,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Champ requis' : null,
                  ),
                  SizedBox(height: 14),

                  // ── Adresse
                  _ProviderFormField(
                    controller: _adresseRueCtrl,
                    label: 'Adresse / Rue',
                    hint: 'ex : 123 Avenue de la Paix',
                    icon: Icons.location_on_outlined,
                  ),
                  SizedBox(height: 14),

                  

                 
                  if (_error != null) ...[
                    SizedBox(height: 14),
                    Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline_rounded,
                            color: Colors.red.shade400,
                            size: 18,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.red.shade600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  SizedBox(height: 24),

                  // ── Submit
                  GestureDetector(
                    onTap: _loading ? null : _submit,
                    child: Container(
                      width: double.infinity,
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: _loading ? null : AppColors.primaryGradient,
                        color: _loading ? Colors.grey.shade300 : null,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: _loading
                            ? []
                            : [
                                BoxShadow(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.30,
                                  ),
                                  blurRadius: 16,
                                  offset: Offset(0, 6),
                                ),
                              ],
                      ),
                      child: Center(
                        child: _loading
                            ? SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                'Soumettre ma demande',
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
            ),
          ),
        ),
      ),
    );
  }
}

class _ProviderFormField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final int maxLines;
  final String? Function(String?)? validator;

  _ProviderFormField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.maxLines = 1,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      validator: validator,
      style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: AppColors.primary, size: 18),
        labelStyle: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        hintStyle: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        filled: true,
        fillColor: AppColors.primarySurface,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: AppColors.primary.withValues(alpha: 0.5),
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.red),
        ),
      ),
    );
  }
}
