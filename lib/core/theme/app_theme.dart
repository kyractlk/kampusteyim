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

  /// Liquid Glass — cam yüzeyler, yumuşak pill butonlar.
  static ThemeData get liquidGlass => _build(
        brightness: Brightness.light,
        background: const Color(0xFFEAF0F6),
        surface: const Color(0xE6FFFFFF),
        surfaceMuted: const Color(0xCCE8EEF5),
        textPrimary: AppColors.textPrimary,
        textSecondary: AppColors.textSecondary,
        border: const Color(0x73B8C7D8),
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
    final radius = liquid ? 22.0 : 14.0;
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

    final filledBg = liquid
        ? (isDark
            ? Colors.white.withValues(alpha: 0.18)
            : AppColors.navy.withValues(alpha: 0.90))
        : (isDark ? AppColors.cyan : AppColors.navy);
    final filledFg = liquid || !isDark ? Colors.white : AppColors.navy;

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: liquid ? Colors.white.withValues(alpha: 0.55) : surface,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: liquid ? 0 : 0.5,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: liquid ? Colors.white.withValues(alpha: 0.55) : surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: AppColors.cyan, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: AppColors.crimson),
        ),
        labelStyle: TextStyle(color: textSecondary),
        hintStyle: TextStyle(color: textSecondary),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: filledBg,
          foregroundColor: filledFg,
          elevation: 0,
          shadowColor: Colors.transparent,
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(liquid ? 24 : 14),
            side: liquid
                ? BorderSide(
                    color: Colors.white.withValues(alpha: isDark ? 0.28 : 0.35),
                  )
                : BorderSide.none,
          ),
          textStyle:
              textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: filledBg,
          foregroundColor: filledFg,
          elevation: 0,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(liquid ? 24 : 14),
          ),
          textStyle:
              textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: isDark ? AppColors.cyan : AppColors.navy,
          backgroundColor: liquid
              ? Colors.white.withValues(alpha: isDark ? 0.08 : 0.35)
              : null,
          minimumSize: const Size.fromHeight(48),
          side: BorderSide(
            color: liquid
                ? Colors.white.withValues(alpha: isDark ? 0.32 : 0.55)
                : border,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(liquid ? 24 : 14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.cyan),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: liquid
            ? AppColors.navy.withValues(alpha: 0.88)
            : (isDark ? AppColors.cyan : AppColors.navy),
        foregroundColor: Colors.white,
        elevation: liquid ? 0 : 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(liquid ? 20 : 16),
          side: liquid
              ? BorderSide(color: Colors.white.withValues(alpha: 0.35))
              : BorderSide.none,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: liquid
            ? Colors.white.withValues(alpha: 0.45)
            : surfaceMuted,
        selectedColor: liquid
            ? AppColors.navy.withValues(alpha: 0.88)
            : AppColors.cyan.withValues(alpha: 0.18),
        labelStyle: textTheme.labelLarge!,
        secondaryLabelStyle: textTheme.labelLarge?.copyWith(color: Colors.white),
        side: liquid
            ? BorderSide(color: Colors.white.withValues(alpha: 0.55))
            : BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(liquid ? 22 : 20),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6),
      ),
      cardTheme: CardThemeData(
        color: liquid ? Colors.white.withValues(alpha: 0.62) : surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(liquid ? 22 : 18),
          side: BorderSide(
            color: liquid ? Colors.white.withValues(alpha: 0.65) : border,
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: liquid ? Colors.white.withValues(alpha: 0.88) : surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(liquid ? 28 : 20),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: liquid ? Colors.white.withValues(alpha: 0.92) : surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(liquid ? 28 : 20),
          ),
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
