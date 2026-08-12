import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Full-screen gradient background with decorative blurred blob accents.
class GradientBackground extends StatelessWidget {
  GradientBackground({
    super.key,
    required this.child,
    this.showDecorations = true,
  });

  final Widget child;
  final bool showDecorations;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Container(
      decoration: BoxDecoration(gradient: AppColors.bgGradient),
      child: Stack(
        children: [
          if (showDecorations) ...[
            // Top-right large blob
            Positioned(
              top: -size.height * 0.08,
              right: -size.width * 0.15,
              child: _Blob(
                size: size.width * 0.72,
                color: AppColors.primaryLight.withValues(alpha: 0.28),
              ),
            ),
            // Mid-left smaller blob
            Positioned(
              top: size.height * 0.32,
              left: -size.width * 0.20,
              child: _Blob(
                size: size.width * 0.55,
                color: AppColors.accent.withValues(alpha: 0.14),
              ),
            ),
            // Bottom-right blob
            Positioned(
              bottom: -size.height * 0.06,
              right: -size.width * 0.10,
              child: _Blob(
                size: size.width * 0.60,
                color: AppColors.primary.withValues(alpha: 0.12),
              ),
            ),
            // Tiny accent top-left
            Positioned(
              top: size.height * 0.12,
              left: size.width * 0.08,
              child: _Blob(
                size: size.width * 0.25,
                color: AppColors.accent.withValues(alpha: 0.18),
              ),
            ),
          ],
          child,
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  _Blob({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

/// A simple horizontal divider with a faint gradient fade.
class GlassDivider extends StatelessWidget {
  GlassDivider({super.key, this.margin});

  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin ?? EdgeInsets.symmetric(vertical: 8),
      height: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.transparent, AppColors.divider, Colors.transparent],
        ),
      ),
    );
  }
}
