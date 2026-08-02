import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(
        brightness: Brightness.light,
        background: AppColors.background,
        surface: AppColors.surface,
        surfaceMuted: AppColors.surfaceMuted,
        textPrimary: AppColors.textPrimary,
        textSecondary: AppColors.textSecondary,
        border: AppColors.border,
        liquid: false,
      );

  /// Liquid Glass — açık zemin + cam hissi (alt bar blur ile tamamlanır).
  static ThemeData get liquidGlass => _build(
        brightness: Brightness.light,
        background: const Color(0xFFF2F5F9),
        surface: const Color(0xF7FFFFFF),
        surfaceMuted: const Color(0xFFE8EEF5),
        textPrimary: AppColors.textPrimary,
        textSecondary: AppColors.textSecondary,
        border: const Color(0x66A8B8C8),
        liquid: true,
      );

  static ThemeData get dark => _build(
        brightness: Brightness.dark,
        background: const Color(0xFF0A0E14),
        surface: const Color(0xFF141A22),
        surfaceMuted: const Color(0xFF1C2430),
        textPrimary: const Color(0xFFF2F5F8),
        textSecondary: const Color(0xFF9AA8B8),
        border: const Color(0xFF2A3544),
        liquid: false,
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color surfaceMuted,
    required Color textPrimary,
    required Color textSecondary,
    required Color border,
    required bool liquid,
  }) {
    final isDark = brightness == Brightness.dark;
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.navy,
        brightness: brightness,
        primary: isDark ? AppColors.cyan : AppColors.navy,
        secondary: AppColors.cyan,
        tertiary: AppColors.lime,
        error: AppColors.crimson,
        surface: surface,
      ),
      scaffoldBackgroundColor: background,
    );

    final textTheme = GoogleFonts.plusJakartaSansTextTheme(base.textTheme).apply(
      bodyColor: textPrimary,
      displayColor: textPrimary,
    );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: liquid ? surface.withValues(alpha: 0.72) : surface,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: liquid ? 0 : 0.5,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.cyan, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.crimson),
        ),
        labelStyle: TextStyle(color: textSecondary),
        hintStyle: TextStyle(color: textSecondary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: isDark ? AppColors.cyan : AppColors.navy,
          foregroundColor: isDark ? AppColors.navy : Colors.white,
          elevation: 0,
          minimumSize: const Size.fromHeight(52),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: isDark ? AppColors.cyan : AppColors.navy,
          minimumSize: const Size.fromHeight(52),
          side: BorderSide(color: border),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.cyan),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceMuted,
        selectedColor: AppColors.cyan.withValues(alpha: 0.18),
        labelStyle: textTheme.labelLarge!,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: border),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: Colors.transparent,
        selectedItemColor: isDark ? AppColors.cyan : AppColors.navy,
        unselectedItemColor: textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      dividerColor: border,
    );
  }
}
