import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// A reusable glassmorphism card widget.
///
/// Renders a frosted-glass panel with a configurable blur, opacity,
/// border and shadow.
class GlassCard extends StatelessWidget {
  GlassCard({
    super.key,
    required this.child,
    this.blur = 12.0,
    this.opacity = 0.75,
    this.borderRadius = 24.0,
    this.padding = const EdgeInsets.all(20),
    this.margin = EdgeInsets.zero,
    this.borderColor,
    this.borderWidth = 1.4,
    this.shadowColor,
    this.shadowBlurRadius = 24,
    this.shadowSpreadRadius = 0,
    this.gradient,
    this.width,
    this.height,
    this.onTap,
  });

  final Widget child;
  final double blur;
  final double opacity;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color? borderColor;
  final double borderWidth;
  final Color? shadowColor;
  final double shadowBlurRadius;
  final double shadowSpreadRadius;
  final Gradient? gradient;
  final double? width;
  final double? height;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final effectiveBorderColor = borderColor ?? AppColors.glassBorder;
    final effectiveShadowColor = shadowColor ?? AppColors.glassShadow;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: effectiveShadowColor,
            blurRadius: shadowBlurRadius,
            spreadRadius: shadowSpreadRadius,
            offset: Offset(0, 8),
          ),
          BoxShadow(
            color: dark
                ? Colors.black.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.6),
            blurRadius: 8,
            spreadRadius: -2,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              padding: padding,
              decoration: BoxDecoration(
                gradient:
                    gradient ??
                    LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        dark
                            ? AppColors.surface.withValues(alpha: 0.88)
                            : Colors.white.withValues(alpha: opacity),
                        dark
                            ? AppColors.surface.withValues(alpha: 0.72)
                            : Colors.white.withValues(alpha: opacity - 0.15),
                      ],
                    ),
                borderRadius: BorderRadius.circular(borderRadius),
                border: Border.all(
                  color: effectiveBorderColor,
                  width: borderWidth,
                ),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// A more prominent glass card with a vivid primary-green tint.
class GlassPrimaryCard extends StatelessWidget {
  GlassPrimaryCard({
    super.key,
    required this.child,
    this.borderRadius = 24.0,
    this.padding = const EdgeInsets.all(20),
    this.margin = EdgeInsets.zero,
    this.width,
    this.height,
    this.onTap,
  });

  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double? width;
  final double? height;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderRadius: borderRadius,
      padding: padding,
      margin: margin,
      width: width,
      height: height,
      onTap: onTap,
      opacity: 0.18,
      blur: 16,
      borderColor: AppColors.primary.withValues(alpha: 0.28),
      shadowColor: AppColors.primary.withValues(alpha: 0.15),
      shadowBlurRadius: 28,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AppColors.primary.withValues(alpha: 0.15),
          AppColors.accent.withValues(alpha: 0.10),
          AppColors.surface.withValues(alpha: 0.55),
        ],
        stops: [0.0, 0.4, 1.0],
      ),
      child: child,
    );
  }
}

/// A floating pill / chip with glassmorphism.
class GlassPill extends StatelessWidget {
  GlassPill({
    super.key,
    required this.label,
    this.icon,
    this.selected = false,
    this.onTap,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(50),
          gradient: selected
              ? AppColors.primaryGradient
              : LinearGradient(colors: [Color(0xE0FFFFFF), Color(0xC8FFFFFF)]),
          border: Border.all(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.5)
                : AppColors.glassBorder,
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: selected
                  ? AppColors.primary.withValues(alpha: 0.25)
                  : AppColors.glassShadow,
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 14,
                color: selected ? Colors.white : AppColors.textSecondary,
              ),
              SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
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
