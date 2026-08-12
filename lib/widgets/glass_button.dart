import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// A premium glass-morphism button with a gradient fill.
class GlassButton extends StatelessWidget {
  GlassButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.fullWidth = false,
    this.small = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool fullWidth;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final double hPad = small ? 18 : 24;
    final double vPad = small ? 10 : 15;
    final double fontSize = small ? 13 : 15;
    final double iconSize = small ? 16 : 18;
    final double radius = small ? 14 : 18;

    Widget btn = GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
        decoration: BoxDecoration(
          gradient: onPressed == null
              ? LinearGradient(
                  colors: [
                    AppColors.textHint.withValues(alpha: 0.22),
                    AppColors.textHint.withValues(alpha: 0.12),
                  ],
                )
              : AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(
                alpha: onPressed == null ? 0 : (dark ? 0.22 : 0.32),
              ),
              blurRadius: 18,
              offset: Offset(0, 6),
            ),
          ],
          border: Border.all(
            color: Colors.white.withValues(alpha: dark ? 0.22 : 0.35),
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, color: Colors.white, size: iconSize),
              SizedBox(width: 8),
            ],
            Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );

    if (fullWidth) {
      btn = ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
          child: btn,
        ),
      );
    }

    return btn;
  }
}

/// A ghost (outline) glass button.
class GlassOutlineButton extends StatelessWidget {
  GlassOutlineButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.fullWidth = false,
    this.small = false,
    this.color = AppColors.primary,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool fullWidth;
  final bool small;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final double hPad = small ? 16 : 22;
    final double vPad = small ? 9 : 14;
    final double fontSize = small ? 13 : 15;
    final double iconSize = small ? 16 : 18;
    final double radius = small ? 14 : 18;

    return GestureDetector(
      onTap: onPressed,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
            decoration: BoxDecoration(
              color: color.withValues(alpha: dark ? 0.14 : 0.08),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: color.withValues(alpha: dark ? 0.55 : 0.45),
                width: 1.4,
              ),
            ),
            child: Row(
              mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: color, size: iconSize),
                  SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: fontSize,
                    fontWeight: FontWeight.w600,
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

/// A round icon-only glass FAB.
class GlassIconButton extends StatelessWidget {
  GlassIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.size = 44,
    this.iconSize = 20,
    this.primary = false,
    this.color,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final bool primary;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final Color effectiveColor =
        color ?? (primary ? AppColors.primary : AppColors.textSecondary);

    return GestureDetector(
      onTap: onPressed,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              gradient: primary
                  ? AppColors.primaryGradient
                  : LinearGradient(
                      colors: dark
                          ? [
                              AppColors.surface.withValues(alpha: 0.92),
                              AppColors.surface.withValues(alpha: 0.76),
                            ]
                          : [Color(0xEAFFFFFF), Color(0xCCFFFFFF)],
                    ),
              borderRadius: BorderRadius.circular(size / 2),
              border: Border.all(
                color: primary
                    ? AppColors.primary.withValues(alpha: 0.4)
                    : AppColors.glassBorder,
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: primary
                      ? AppColors.primary.withValues(alpha: dark ? 0.18 : 0.25)
                      : AppColors.glassShadow,
                  blurRadius: 14,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              icon,
              size: iconSize,
              color: primary ? Colors.white : effectiveColor,
            ),
          ),
        ),
      ),
    );
  }
}
