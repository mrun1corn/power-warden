import 'package:flutter/material.dart';

/// Dynamic Theme Palette for PowerWarden: Pure OLED Black & Crisp Clean Light Mode.
class AppTheme {
  AppTheme._();

  // OLED Dark Palette
  static const Color pureOledBackground = Color(0xFF000000);
  static const Color surfaceDark = Color(0xFF121212);
  static const Color surfaceVariantDark = Color(0xFF1E1E1E);
  static const Color surfaceBorderDark = Color(0xFF2C2C2C);

  // Clean Light Palette
  static const Color lightBackground = Color(0xFFF8F9FA);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceVariantLight = Color(0xFFF1F3F5);
  static const Color surfaceBorderLight = Color(0xFFE9ECEF);

  // Backwards compatibility aliases for dark theme default
  static const Color surface = surfaceDark;
  static const Color surfaceVariant = surfaceVariantDark;
  static const Color surfaceBorder = surfaceBorderDark;

  // Status & Accents
  static const Color accentGreen = Color(0xFF00E676); // Normal drain / healthy
  static const Color amber = Color(0xFFFFB300); // Mild / moderate drain
  static const Color crimson = Color(0xFFFF1744); // Critical drain / thermal alert
  static const Color chargingCyan = Color(0xFF00E5FF); // Charging active

  static const Color textPrimary = Color(0xFFEEEEEE);
  static const Color textSecondary = Color(0xFF9E9E9E);
  static const Color textMuted = Color(0xFF616161);

  // Light text colors
  static const Color textPrimaryLight = Color(0xFF1A1A1A);
  static const Color textSecondaryLight = Color(0xFF5F6368);
  static const Color textMutedLight = Color(0xFF80868B);

  static ThemeData get theme => darkTheme;

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: pureOledBackground,
      colorScheme: const ColorScheme.dark(
        surface: surfaceDark,
        surfaceContainerHighest: surfaceVariantDark,
        primary: accentGreen,
        secondary: chargingCyan,
        error: crimson,
        onSurface: textPrimary,
        onError: Colors.white,
      ),
      cardTheme: CardThemeData(
        color: surfaceDark,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: surfaceBorderDark, width: 1),
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: pureOledBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: lightBackground,
      colorScheme: const ColorScheme.light(
        surface: surfaceLight,
        surfaceContainerHighest: surfaceVariantLight,
        primary: Color(0xFF00C853),
        secondary: Color(0xFF00B0FF),
        error: crimson,
        onSurface: textPrimaryLight,
        onError: Colors.white,
      ),
      cardTheme: CardThemeData(
        color: surfaceLight,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: surfaceBorderLight, width: 1),
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: lightBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimaryLight,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

