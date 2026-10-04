import 'package:flutter/material.dart';

/// Dynamic Theme Palette for PowerWarden: Pure OLED Black & Crisp Clean Light Mode.
class AppTheme {
  AppTheme._();

  // OLED Dark Palette
  static const Color pureOledBackground = Color(0xFF000000);
  static const Color surfaceDark = Color(0xFF121212);
  static const Color surfaceVariantDark = Color(0xFF1E1E1E);
  static const Color surfaceBorderDark = Color(0xFF2C2C2C);

  // Clean Light Palette (Pure 100% White)
  static const Color lightBackground = Color(0xFFFFFFFF);
  static const Color surfaceLight = Color(0xFFF8F9FA);
  static const Color surfaceVariantLight = Color(0xFFF1F3F5);
  static const Color surfaceBorderLight = Color(0xFFE5E7EB);

  // Backwards compatibility aliases for dark theme default
  static const Color surface = surfaceDark;
  static const Color surfaceVariant = surfaceVariantDark;
  static const Color surfaceBorder = surfaceBorderDark;

  // Status & Accents (Dark)
  static const Color accentGreen = Color(0xFF00E676); // Normal drain / healthy
  static const Color amber = Color(0xFFFFB300); // Mild / moderate drain
  static const Color crimson = Color(
    0xFFFF1744,
  ); // Critical drain / thermal alert
  static const Color chargingCyan = Color(0xFF00E5FF); // Charging active

  // High-Contrast Accents for Light Mode (WCAG AA >= 4.5:1 on light backgrounds)
  static const Color accentGreenLight = Color(0xFF00873D);
  static const Color amberLight = Color(0xFFB45309);
  static const Color crimsonLight = Color(0xFFDC2626);
  static const Color chargingCyanLight = Color(0xFF0284C7);

  // Dark text colors (OLED contrast compliant >= 5.0:1)
  static const Color textPrimary = Color(0xFFF4F4F5);
  static const Color textSecondary = Color(0xFFD4D4D8);
  static const Color textMuted = Color(0xFFA1A1AA); // 7.4:1 contrast on #000000

  // Light text colors (WCAG AA compliant >= 6.0:1 on #FFFFFF)
  static const Color textPrimaryLight = Color(0xFF18181B);
  static const Color textSecondaryLight = Color(0xFF3F3F46);
  static const Color textMutedLight = Color(
    0xFF52525B,
  ); // 6.8:1 contrast on #F8F9FA
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
        primary: accentGreenLight,
        secondary: chargingCyanLight,
        error: crimsonLight,
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
