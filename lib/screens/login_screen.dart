import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../core/models/auth_models.dart';
import '../core/services/auth_service.dart';
import '../theme/app_colors.dart';
import '../widgets/gradient_background.dart';
import '../widgets/glass_button.dart';

class LoginScreen extends StatefulWidget {
  LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  // Login fields
  final _identifierCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  // Register fields
  final _emailCtrl = TextEditingController();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _telephoneCtrl = TextEditingController();

  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _isRegisterMode = false;
  int _registerStep = 0;
  String? _errorMessage;

  static int _registerStepCount = 3;

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut));
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _identifierCtrl.dispose();
    _passwordCtrl.dispose();
    _emailCtrl.dispose();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _telephoneCtrl.dispose();
    super.dispose();
  }

  void _switchMode() {
    setState(() {
      _isRegisterMode = !_isRegisterMode;
      _registerStep = 0;
      _errorMessage = null;
    });
  }

  void _nextRegisterStep() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_registerStep >= _registerStepCount - 1) {
      _register();
      return;
    }
    setState(() {
      _registerStep++;
      _errorMessage = null;
    });
  }

  void _previousRegisterStep() {
    if (_registerStep == 0) return;
    setState(() {
      _registerStep--;
      _errorMessage = null;
    });
  }

  void _showForgotPasswordInfo() {
    debugPrint('[Login] Password reset requested.');
  }

  // ── Login logic ────────────────────────────────────────────────────────────
  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await AuthService.instance.login(
        LoginRequest(
          identifier: _identifierCtrl.text.trim(),
          password: _passwordCtrl.text,
        ),
      );

      if (!mounted) return;

      if (response.success && response.data != null) {
        Navigator.of(context).pop(); // retour au HomeScreen
      } else {
        setState(() => _errorMessage = response.message);
      }
    } on SocketException {
      setState(
        () => _errorMessage =
            'Impossible de se connecter — vérifiez votre connexion internet.',
      );
    } on TimeoutException {
      setState(
        () => _errorMessage = 'La requête a expiré. Veuillez réessayer.',
      );
    } catch (e) {
      setState(
        () => _errorMessage = 'Erreur de connexion. Veuillez réessayer.',
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Register logic ──────────────────────────────────────────────────────
  Future<void> _register() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await AuthService.instance.register(
        RegisterRequest(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
          firstName: _firstNameCtrl.text.trim(),
          lastName: _lastNameCtrl.text.trim(),
          telephone: _telephoneCtrl.text.trim(),
        ),
      );

      if (!mounted) return;

      if (response.success && response.data != null) {
        Navigator.of(context).pop(); // retour au HomeScreen
      } else {
        setState(() => _errorMessage = response.message);
      }
    } catch (e) {
      setState(
        () =>
            _errorMessage = "Erreur lors de l’inscription. Veuillez réessayer.",
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GradientBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              physics: BouncingScrollPhysics(),
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: FadeTransition(
                opacity: _fadeAnim,
                child: SlideTransition(
                  position: _slideAnim,
                  child: Column(
                    children: [
                      _buildLogo(),
                      SizedBox(height: 36),
                      _buildFormCard(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Logo section ───────────────────────────────────────────────────────────
  Widget _buildLogo() {
    final subtitle = _isRegisterMode
        ? 'Créez votre compte étape par étape'
        : 'Connectez-vous à votre compte';
    return Column(
      children: [
        // Glow ring
        Container(
          width: 90,
          height: 90,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppColors.primaryGradient,
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.38),
                blurRadius: 32,
                spreadRadius: 4,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
              child: Icon(Icons.eco_rounded, color: Colors.white, size: 46),
            ),
          ),
        ),
        SizedBox(height: 18),
        Text(
          'Zwacop',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            letterSpacing: -0.5,
          ),
        ),
        SizedBox(height: 6),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 14,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }

  // ── Form card ──────────────────────────────────────────────────────────────
  Widget _buildFormCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: AppColors.glassBorder, width: 1.4),
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
          padding: EdgeInsets.fromLTRB(24, 28, 24, 28),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Error banner ──────────────────────────────────────────
                if (_errorMessage != null) ...[
                  _ErrorBanner(message: _errorMessage!),
                  SizedBox(height: 20),
                ],

                // ── Register / Login fields ───────────────────────────
                if (_isRegisterMode) ...[
                  _buildRegisterContent(),
                ] else ...[
                  _buildLabel("E-mail ou nom d'utilisateur"),
                  SizedBox(height: 8),
                  _GlassTextField(
                    controller: _identifierCtrl,
                    hint: 'tony@eden.local',
                    prefixIcon: Icons.person_outline_rounded,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return "Veuillez saisir votre e-mail ou nom d'utilisateur";
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: 18),
                  _buildLabel('Mot de passe'),
                  SizedBox(height: 8),
                  _GlassTextField(
                    controller: _passwordCtrl,
                    hint: '••••••••',
                    prefixIcon: Icons.lock_outline_rounded,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    suffixIcon: GestureDetector(
                      onTap: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                      child: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 20,
                        color: AppColors.textHint,
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) {
                        return 'Veuillez saisir votre mot de passe';
                      }
                      return null;
                    },
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _showForgotPasswordInfo,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 10,
                        ),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        'Mot de passe oublié ?',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 8),
                  _isLoading
                      ? _LoadingButton()
                      : GlassButton(
                          label: 'Se connecter',
                          icon: Icons.arrow_forward_rounded,
                          onPressed: _submit,
                          fullWidth: true,
                        ),
                ],

                SizedBox(height: 20),
                _OrDivider(),
                SizedBox(height: 20),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _isRegisterMode
                          ? 'Déjà un compte ? '
                          : 'Pas encore de compte ? ',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    GestureDetector(
                      onTap: _switchMode,
                      child: Text(
                        _isRegisterMode ? 'Se connecter' : "S'inscrire",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
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
    );
  }

  Widget _buildRegisterContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RegisterProgress(
          currentStep: _registerStep,
          totalSteps: _registerStepCount,
        ),
        SizedBox(height: 22),
        AnimatedSwitcher(
          duration: Duration(milliseconds: 220),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: KeyedSubtree(
            key: ValueKey<int>(_registerStep),
            child: _buildRegisterStepFields(),
          ),
        ),
        SizedBox(height: 24),
        _buildRegisterActions(),
      ],
    );
  }

  Widget _buildRegisterStepFields() {
    switch (_registerStep) {
      case 0:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildRegisterStepHeader(
              title: 'Identité',
              subtitle: 'Commençons par vos informations personnelles.',
            ),
            SizedBox(height: 18),
            _buildLabel('Prénom'),
            SizedBox(height: 8),
            _GlassTextField(
              controller: _firstNameCtrl,
              hint: 'Jean',
              prefixIcon: Icons.badge_outlined,
              textInputAction: TextInputAction.next,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Veuillez saisir votre prénom'
                  : null,
            ),
            SizedBox(height: 14),
            _buildLabel('Nom de famille'),
            SizedBox(height: 8),
            _GlassTextField(
              controller: _lastNameCtrl,
              hint: 'Dupont',
              prefixIcon: Icons.person_outline_rounded,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _nextRegisterStep(),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Veuillez saisir votre nom'
                  : null,
            ),
          ],
        );
      case 1:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildRegisterStepHeader(
              title: 'Coordonnées',
              subtitle: 'Ces informations serviront à identifier votre compte.',
            ),
            SizedBox(height: 18),
            _buildLabel('E-mail (facultatif)'),
            SizedBox(height: 8),
            _GlassTextField(
              controller: _emailCtrl,
              hint: 'jean@eden.local',
              prefixIcon: Icons.mail_outline_rounded,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              validator: (v) {
                final value = v?.trim() ?? '';
                if (value.isEmpty) return null;
                if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)) {
                  return 'E-mail invalide';
                }
                return null;
              },
            ),
            SizedBox(height: 14),
            _buildLabel('Téléphone'),
            SizedBox(height: 8),
            _GlassTextField(
              controller: _telephoneCtrl,
              hint: '+243 81 234 5678',
              prefixIcon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _nextRegisterStep(),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Veuillez saisir votre numéro de téléphone'
                  : null,
            ),
          ],
        );
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildRegisterStepHeader(
              title: 'Sécurité',
              subtitle: 'Choisissez un mot de passe pour finaliser.',
            ),
            SizedBox(height: 18),
            _buildLabel('Mot de passe'),
            SizedBox(height: 8),
            _GlassTextField(
              controller: _passwordCtrl,
              hint: '••••••••',
              prefixIcon: Icons.lock_outline_rounded,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _register(),
              suffixIcon: GestureDetector(
                onTap: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                child: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 20,
                  color: AppColors.textHint,
                ),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) {
                  return 'Veuillez saisir un mot de passe';
                }
                if (v.length < 8) return 'Minimum 8 caractères';
                return null;
              },
            ),
          ],
        );
    }
  }

  Widget _buildRegisterStepHeader({
    required String title,
    required String subtitle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: 5),
        Text(
          subtitle,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  Widget _buildRegisterActions() {
    final bool isLastStep = _registerStep == _registerStepCount - 1;
    if (_isLoading) return _LoadingButton();

    return Row(
      children: [
        if (_registerStep > 0) ...[
          Expanded(
            child: GlassOutlineButton(
              label: 'Retour',
              icon: Icons.arrow_back_rounded,
              onPressed: _previousRegisterStep,
              fullWidth: true,
            ),
          ),
          SizedBox(width: 12),
        ],
        Expanded(
          child: GlassButton(
            label: isLastStep ? 'Valider' : 'Suivant',
            icon: isLastStep
                ? Icons.person_add_rounded
                : Icons.arrow_forward_rounded,
            onPressed: _nextRegisterStep,
            fullWidth: true,
          ),
        ),
      ],
    );
  }

  Widget _buildLabel(String text) {
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

// ── Reusable sub-widgets ──────────────────────────────────────────────────────

class _RegisterProgress extends StatelessWidget {
  _RegisterProgress({required this.currentStep, required this.totalSteps});

  final int currentStep;
  final int totalSteps;

  @override
  Widget build(BuildContext context) {
    final progress = (currentStep + 1) / totalSteps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Étape ${currentStep + 1}/$totalSteps',
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            Spacer(),
            Text(
              '${(progress * 100).round()}%',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 7,
            backgroundColor: AppColors.primarySurface,
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        ),
      ],
    );
  }
}

class _GlassTextField extends StatelessWidget {
  _GlassTextField({
    required this.controller,
    required this.hint,
    required this.prefixIcon,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.onFieldSubmitted,
    this.suffixIcon,
    this.validator,
  });

  final TextEditingController controller;
  final String hint;
  final IconData prefixIcon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final Widget? suffixIcon;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
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
          child: Icon(prefixIcon, color: AppColors.primary, size: 19),
        ),
        prefixIconConstraints: BoxConstraints(),
        suffixIcon: suffixIcon != null
            ? Padding(padding: EdgeInsets.only(right: 14), child: suffixIcon)
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

class _ErrorBanner extends StatelessWidget {
  _ErrorBanner({required this.message});
  final String message;

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

class _LoadingButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            color: Colors.white,
            strokeWidth: 2.4,
          ),
        ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.transparent, AppColors.divider],
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            'ou',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textHint,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.divider, Colors.transparent],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
