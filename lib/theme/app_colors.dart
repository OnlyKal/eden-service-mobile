import 'package:flutter/material.dart';

/// Zwacop – green-first colour palette
class AppColors {
  AppColors._();

  // ── Core greens ─────────────────────────────────────────────────────────
  static const Color primary = Color(0xFF34C17A);
  static const Color primaryLight = Color(0xFF6EDDA3);
  static const Color primaryDark = Color(0xFF1F9C5C);
  static const Color primarySurface = Color(0xFFEAF8F1);

  // ── Accent / secondary ──────────────────────────────────────────────────
  static const Color accent = Color(0xFF00D4AA);
  static const Color accentLight = Color(0xFFB2F5EA);

  // ── Neutrals ────────────────────────────────────────────────────────────
  static const Color white = Color(0xFFFFFFFF);
  static const Color background = Color(0xFFF4FDF8);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color divider = Color(0xFFE0F2EB);

  // ── Text ────────────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFF1B3A2E);
  static const Color textSecondary = Color(0xFF5A7A6C);
  static const Color textHint = Color(0xFF9DB8AC);

  // ── Status ──────────────────────────────────────────────────────────────
  static const Color success = Color(0xFF34C17A);
  static const Color warning = Color(0xFFFFC107);
  static const Color error = Color(0xFFE53935);
  static const Color info = Color(0xFF00A88A);

  /// Bleu du badge de certification du compte.
  static const Color certification = Color(0xFF1877F2);

  // ── WhatsApp (marque) ───────────────────────────────────────────────────
  /// Vert officiel WhatsApp, proche du vert Zwacop pour rester cohérent
  /// avec la palette de l'application.
  static const Color whatsapp = Color(0xFF25D366);
  static const Color whatsappDark = Color(0xFF1EAE5B);

  // ── Glass layer ─────────────────────────────────────────────────────────
  static const Color glassWhite = Color(0xCCFFFFFF);
  static const Color glassGreen = Color(0x2234C17A);
  static const Color glassBorder = Color(0x66FFFFFF);
  static const Color glassShadow = Color(0x1A34C17A);

  // ── Gradient presets ────────────────────────────────────────────────────
  static const LinearGradient bgGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF0FDF6), Color(0xFFE8F8F2), Color(0xFFDDF5EC)],
    stops: [0.0, 0.5, 1.0],
  );

  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF34C17A), Color(0xFF00D4AA)],
  );

  static const LinearGradient primaryGradientSoft = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF6EDDA3), Color(0xFF34C17A)],
  );

  static const LinearGradient whatsappGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF25D366), Color(0xFF1EAE5B)],
  );

  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xF0FFFFFF), Color(0xD9FFFFFF)],
  );
}
