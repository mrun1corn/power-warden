import 'package:flutter/material.dart';

/// Pure OLED Dark Theme palette for PowerWarden.
class AppTheme {
  AppTheme._();

  // Colors
  static const Color pureOledBackground = Color(0xFF000000);
  static const Color surface = Color(0xFF121212);
  static const Color surfaceVariant = Color(0xFF1E1E1E);
  static const Color surfaceBorder = Color(0xFF2C2C2C);

  // Status & Accents
  static const Color accentGreen = Color(0xFF00E676); // Normal drain / healthy
  static const Color amber = Color(0xFFFFB300); // Mild / moderate drain
  static const Color crimson = Color(0xFFFF1744); // Critical drain / thermal alert
  static const Color chargingCyan = Color(0xFF00E5FF); // Charging active

  static const Color textPrimary = Color(0xFFEEEEEE);
  static const Color textSecondary = Color(0xFF9E9E9E);
  static const Color textMuted = Color(0xFF616161);

  static ThemeData get theme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: pureOledBackground,
      colorScheme: const ColorScheme.dark(
        surface: surface,
        surfaceContainerHighest: surfaceVariant,
        primary: accentGreen,
        secondary: chargingCyan,
        error: crimson,
        onSurface: textPrimary,
        onError: Colors.white,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: surfaceBorder, width: 1),
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
      chipTheme: ChipThemeData(
        backgroundColor: surfaceVariant,
        side: const BorderSide(color: surfaceBorder, width: 1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        labelStyle: const TextStyle(
          color: textPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
