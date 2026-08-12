import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final base = ThemeData.light(useMaterial3: true);

    return base.copyWith(
      // ── Colour scheme ───────────────────────────────────────────────────
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.light,
        primary: AppColors.primary,
        secondary: AppColors.accent,
        surface: AppColors.surface,
        onPrimary: AppColors.white,
        onSecondary: AppColors.white,
        onSurface: AppColors.textPrimary,
      ),

      // ── Scaffold ────────────────────────────────────────────────────────
      scaffoldBackgroundColor: AppColors.background,

      // ── Typography ──────────────────────────────────────────────────────
      textTheme: GoogleFonts.dmSansTextTheme(base.textTheme).copyWith(
        displayLarge: GoogleFonts.dmSans(
          fontSize: 36,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
          height: 1.2,
        ),
        displayMedium: GoogleFonts.dmSans(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
          height: 1.25,
        ),
        headlineLarge: GoogleFonts.dmSans(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        headlineMedium: GoogleFonts.dmSans(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        headlineSmall: GoogleFonts.dmSans(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        titleLarge: GoogleFonts.dmSans(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        titleMedium: GoogleFonts.dmSans(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
        ),
        bodyLarge: GoogleFonts.dmSans(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: AppColors.textPrimary,
        ),
        bodyMedium: GoogleFonts.dmSans(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AppColors.textSecondary,
        ),
        bodySmall: GoogleFonts.dmSans(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: AppColors.textHint,
        ),
        labelLarge: GoogleFonts.dmSans(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
        ),
        labelMedium: GoogleFonts.dmSans(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColors.textSecondary,
        ),
      ),

      // ── AppBar ──────────────────────────────────────────────────────────
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.dmSans(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        iconTheme: IconThemeData(color: AppColors.textPrimary, size: 22),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarBrightness: Brightness.light,
          statusBarIconBrightness: Brightness.dark,
          statusBarColor: Colors.transparent,
        ),
      ),

      // ── Bottom NavBar ────────────────────────────────────────────────────
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: Colors.transparent,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textHint,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),

      // ── Elevated button ─────────────────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.white,
          elevation: 0,
          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: GoogleFonts.dmSans(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // ── Outlined button ─────────────────────────────────────────────────
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: BorderSide(color: AppColors.primary, width: 1.5),
          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: GoogleFonts.dmSans(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // ── Text button ─────────────────────────────────────────────────────
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: GoogleFonts.dmSans(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // ── Input decoration ────────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.white,
        contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColors.divider, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColors.primary, width: 1.8),
        ),
        hintStyle: GoogleFonts.dmSans(color: AppColors.textHint, fontSize: 14),
        labelStyle: GoogleFonts.dmSans(
          color: AppColors.textSecondary,
          fontSize: 14,
        ),
      ),

      // ── Card ────────────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        color: AppColors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        margin: EdgeInsets.symmetric(horizontal: 0, vertical: 6),
      ),

      // ── Chip ────────────────────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.primarySurface,
        selectedColor: AppColors.primary,
        labelStyle: GoogleFonts.dmSans(
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        side: BorderSide.none,
      ),

      // ── Divider ─────────────────────────────────────────────────────────
      dividerTheme: DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 1,
      ),

      // ── Icon ────────────────────────────────────────────────────────────
      iconTheme: IconThemeData(color: AppColors.textSecondary, size: 22),
    );
  }

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    final surface = Color(0xFF10221A);
    final background = Color(0xFF07140F);
    final textPrimary = Color(0xFFEAF8F1);
    final textSecondary = Color(0xFFB7D2C6);
    final textHint = Color(0xFF82A093);

    return base.copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.dark,
        primary: AppColors.primaryLight,
        secondary: AppColors.accent,
        surface: surface,
        onPrimary: Color(0xFF052015),
        onSecondary: Color(0xFF052015),
        onSurface: textPrimary,
      ),
      scaffoldBackgroundColor: background,
      textTheme: GoogleFonts.dmSansTextTheme(base.textTheme).copyWith(
        displayLarge: GoogleFonts.dmSans(
          fontSize: 36,
          fontWeight: FontWeight.w700,
          color: textPrimary,
          height: 1.2,
        ),
        displayMedium: GoogleFonts.dmSans(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: textPrimary,
          height: 1.25,
        ),
        headlineLarge: GoogleFonts.dmSans(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        headlineMedium: GoogleFonts.dmSans(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        headlineSmall: GoogleFonts.dmSans(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        titleLarge: GoogleFonts.dmSans(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        titleMedium: GoogleFonts.dmSans(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: textPrimary,
        ),
        bodyLarge: GoogleFonts.dmSans(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: textPrimary,
        ),
        bodyMedium: GoogleFonts.dmSans(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: textSecondary,
        ),
        bodySmall: GoogleFonts.dmSans(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: textHint,
        ),
        labelLarge: GoogleFonts.dmSans(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.primaryLight,
        ),
        labelMedium: GoogleFonts.dmSans(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: textSecondary,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.dmSans(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        iconTheme: IconThemeData(color: textPrimary, size: 22),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarBrightness: Brightness.dark,
          statusBarIconBrightness: Brightness.light,
          statusBarColor: Colors.transparent,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Color(0xFF234235)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Color(0xFF234235), width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColors.primaryLight, width: 1.8),
        ),
        hintStyle: GoogleFonts.dmSans(color: textHint, fontSize: 14),
        labelStyle: GoogleFonts.dmSans(color: textSecondary, fontSize: 14),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        margin: EdgeInsets.symmetric(horizontal: 0, vertical: 6),
      ),
      iconTheme: IconThemeData(color: textSecondary, size: 22),
    );
  }
}
