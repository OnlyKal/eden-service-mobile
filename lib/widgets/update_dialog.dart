import 'package:flutter/material.dart';

import '../core/services/version_check_service.dart';
import '../theme/app_colors.dart';

/// Affiche la modale de mise à jour obligatoire.
///
/// - Empêche la fermeture (non dismissible, pas de bouton retour).
/// - Empêche le contournement (barrière système bloquée).
/// - Propose uniquement le bouton « Mettre à jour ».
Future<void> showMandatoryUpdateDialog(
  BuildContext context, {
  required String message,
  VoidCallback? onReturnFromStore,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _MandatoryUpdateDialog(
      message: message,
      onReturnFromStore: onReturnFromStore,
    ),
  );
}

/// Affiche la modale de mise à jour recommandée.
///
/// - Permet de continuer avec « Plus tard ».
/// - Propose le bouton « Mettre à jour ».
Future<void> showRecommendedUpdateDialog(
  BuildContext context, {
  required String message,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _RecommendedUpdateDialog(message: message),
  );
}

/// Widget racine qui vérifie la version au démarrage et affiche
/// la modale appropriée.
class VersionCheckGate extends StatefulWidget {
  const VersionCheckGate({super.key, required this.child});

  /// Le contenu de l'application à afficher une fois la vérification passée.
  final Widget child;

  @override
  State<VersionCheckGate> createState() => _VersionCheckGateState();
}

class _VersionCheckGateState extends State<VersionCheckGate> {
  bool _checking = true;
  bool _blocked = false;

  @override
  void initState() {
    super.initState();
    _runCheck();
  }

  Future<void> _runCheck() async {
    setState(() {
      _checking = true;
    });

    final result = await VersionCheckService.instance.checkForUpdate(
      force: true,
    );

    if (!mounted) return;

    final server = VersionCheckService.instance.lastServerVersion;
    final message = server?.messageAlerte ??
        'Une nouvelle version de ZWACOP est disponible. '
            'Mettez votre application à jour pour profiter des dernières '
            'améliorations et corrections.';

    if (result == VersionCheckResult.updateAvailable) {
      final mandatory = VersionCheckService.instance.isUpdateMandatory;
      setState(() {
        _checking = false;
        _blocked = mandatory;
      });

      if (mandatory) {
        // Modale obligatoire : bloque l'accès tant que la mise à jour
        // n'est pas effectuée. On re-vérifie après le retour du store.
        await showMandatoryUpdateDialog(
          context,
          message: message,
          onReturnFromStore: _runCheck,
        );
      } else {
        // Modale recommandée : l'utilisateur peut continuer.
        await showRecommendedUpdateDialog(context, message: message);
        if (mounted) {
          setState(() {
            _blocked = false;
          });
        }
      }
    } else {
      // Version à jour, plus récente que le serveur, ou erreur réseau :
      // continuer normalement.
      setState(() {
        _checking = false;
        _blocked = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    if (_blocked) {
      // L'utilisateur est bloqué par la modale obligatoire.
      // On affiche un écran vide derrière la modale.
      return const Scaffold(
        body: SizedBox.shrink(),
      );
    }

    return widget.child;
  }
}

/// Modale de mise à jour obligatoire.
class _MandatoryUpdateDialog extends StatelessWidget {
  const _MandatoryUpdateDialog({
    required this.message,
    this.onReturnFromStore,
  });

  final String message;
  final VoidCallback? onReturnFromStore;

  Future<void> _openStore(BuildContext context) async {
    final opened = await VersionCheckService.instance.openStore();
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Impossible d\'ouvrir le store. Veuillez réessayer.',
          ),
        ),
      );
      return;
    }
    // Ferme la modale puis re-vérifie la version après le retour du store.
    if (context.mounted) {
      Navigator.of(context).pop();
    }
    onReturnFromStore?.call();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Empêche la fermeture par le bouton retour système.
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black.withValues(alpha: 0.6),
        body: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.primaryGradient,
                  ),
                  child: const Icon(
                    Icons.system_update_alt,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Mise à jour requise',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => _openStore(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Mettre à jour',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
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
}

/// Modale de mise à jour recommandée.
class _RecommendedUpdateDialog extends StatelessWidget {
  const _RecommendedUpdateDialog({required this.message});

  final String message;

  Future<void> _openStore(BuildContext context) async {
    final opened = await VersionCheckService.instance.openStore();
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Impossible d\'ouvrir le store. Veuillez réessayer.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        backgroundColor: AppColors.surface,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppColors.primaryGradient,
                ),
                child: const Icon(
                  Icons.system_update_alt,
                  color: Colors.white,
                  size: 36,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Nouvelle version disponible',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                message,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _openStore(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Mettre à jour',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: const Text(
                    'Plus tard',
                    style: TextStyle(fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}