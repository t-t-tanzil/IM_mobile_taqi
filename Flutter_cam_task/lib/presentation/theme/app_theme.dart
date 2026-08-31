import 'package:flutter/material.dart';

/// Central color/typography tokens for the dark "field capture" look.
/// Kept as one small file rather than scattering hex values across widgets -
/// no new state or architecture, purely presentation constants.
class AppColors {
  const AppColors._();

  static const background = Color(0xFF0B0E14);
  static const surface = Color(0xFF141821);
  static const surfaceElevated = Color(0xFF1B2029);
  static const border = Color(0xFF2A2F3A);

  static const textPrimary = Color(0xFFF2F4F8);
  static const textSecondary = Color(0xFFAEB4C2);

  static const blue = Color(0xFF3B82F6);
  static const green = Color(0xFF22C55E);
  static const red = Color(0xFFEF4444);
  static const orange = Color(0xFFF59E0B);
  static const neutral = Color(0xFF7C8493);
}

class AppTheme {
  const AppTheme._();

  static ThemeData get dark {
    final colorScheme = const ColorScheme.dark(
      primary: AppColors.blue,
      onPrimary: Colors.white,
      secondary: AppColors.blue,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      surfaceContainerHighest: AppColors.surfaceElevated,
      error: AppColors.red,
      onError: Colors.white,
      errorContainer: Color(0xFF3A1518),
      onErrorContainer: AppColors.red,
      outline: AppColors.border,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.blue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.blue,
        inactiveTrackColor: AppColors.border,
        thumbColor: Colors.white,
        overlayColor: Color(0x333B82F6),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.surfaceElevated,
        contentTextStyle: TextStyle(color: AppColors.textPrimary),
        behavior: SnackBarBehavior.floating,
      ),
      textTheme: const TextTheme(
        titleLarge: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700),
        titleMedium: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(color: AppColors.textPrimary),
        bodyMedium: TextStyle(color: AppColors.textSecondary),
        bodySmall: TextStyle(color: AppColors.textSecondary),
        labelLarge: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
      ),
      iconTheme: const IconThemeData(color: AppColors.textPrimary),
    );
  }
}
