import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// PowerWarden Design System v2.
/// Single source of truth for colors, typography, and component themes.
/// Screens read from Theme.of(context) — no per-screen color ternaries.
class AppTheme {
  AppTheme._();

  // ── Core Palettes ──────────────────────────────────────────────
  static const Color pureOledBackground = Color(0xFF000000);
  static const Color surfaceDark = Color(0xFF121212);
  static const Color surfaceVariantDark = Color(0xFF1E1E1E);
  static const Color surfaceBorderDark = Color(0xFF2C2C2C);

  static const Color lightBackground = Color(0xFFFFFFFF);
  static const Color surfaceLight = Color(0xFFF8F9FA);
  static const Color surfaceVariantLight = Color(0xFFF1F3F5);
  static const Color surfaceBorderLight = Color(0xFFE5E7EB);

  // ── Semantic Status Colors (Dark) ───────────────────────────────
  static const Color statusHealthy = Color(0xFF00E676); // Normal drain / healthy
  static const Color statusWarning = Color(0xFFFFB300); // Mild / moderate drain
  static const Color statusCritical = Color(0xFFFF1744); // Critical drain / thermal
  static const Color statusCharging = Color(0xFF00E5FF); // Charging active

  // ── Semantic Status Colors (Light, WCAG AA >= 4.5:1) ────────────
  static const Color statusHealthyLight = Color(0xFF00873D);
  static const Color statusWarningLight = Color(0xFFB45309);
  static const Color statusCriticalLight = Color(0xFFDC2626);
  static const Color statusChargingLight = Color(0xFF0284C7);

  // ── Text (Dark, OLED contrast >= 5.0:1) ─────────────────────────
  static const Color textPrimary = Color(0xFFF4F4F5);
  static const Color textSecondary = Color(0xFFD4D4D8);
  static const Color textMuted = Color(0xFFA1A1AA);

  // ── Text (Light, WCAG AA >= 6.0:1) ──────────────────────────────
  static const Color textPrimaryLight = Color(0xFF18181B);
  static const Color textSecondaryLight = Color(0xFF3F3F46);
  static const Color textMutedLight = Color(0xFF52525B);

  // ── Backwards-compat aliases (existing screens keep compiling) ──
  static const Color accentGreen = statusHealthy;
  static const Color amber = statusWarning;
  static const Color crimson = statusCritical;
  static const Color chargingCyan = statusCharging;
  static const Color accentGreenLight = statusHealthyLight;
  static const Color amberLight = statusWarningLight;
  static const Color crimsonLight = statusCriticalLight;
  static const Color chargingCyanLight = statusChargingLight;
  static const Color surface = surfaceDark;
  static const Color surfaceVariant = surfaceVariantDark;
  static const Color surfaceBorder = surfaceBorderDark;

  /// Semantic status color resolved by theme brightness.
  static Color healthColor(Brightness b) => b == Brightness.dark ? statusHealthy : statusHealthyLight;
  static Color warningColor(Brightness b) => b == Brightness.dark ? statusWarning : statusWarningLight;
  static Color criticalColor(Brightness b) => b == Brightness.dark ? statusCritical : statusCriticalLight;
  static Color chargingColor(Brightness b) => b == Brightness.dark ? statusCharging : statusChargingLight;

  // ── Typography Scale (replaces hardcoded fontSize) ─────────────
  static const TextStyle _displayDark = TextStyle(
    color: textPrimary,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
  );
  static const TextStyle _bodyDark = TextStyle(color: textPrimary);
  static const TextStyle _labelDark = TextStyle(
    color: textMuted,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.3,
  );

  static const TextStyle _displayLight = TextStyle(
    color: textPrimaryLight,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
  );
  static const TextStyle _bodyLight = TextStyle(color: textPrimaryLight);
  static const TextStyle _labelLight = TextStyle(
    color: textMutedLight,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.3,
  );

  static TextTheme _textTheme(TextStyle display, TextStyle body, TextStyle label, Color secondaryText) {
    return TextTheme(
      displaySmall: display.copyWith(fontSize: 34),
      headlineLarge: display.copyWith(fontSize: 28),
      headlineMedium: display.copyWith(fontSize: 24),
      headlineSmall: display.copyWith(fontSize: 20),
      titleLarge: body.copyWith(fontSize: 20, fontWeight: FontWeight.w700),
      titleMedium: body.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
      titleSmall: body.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
      bodyLarge: body.copyWith(fontSize: 15),
      bodyMedium: body.copyWith(fontSize: 13, color: secondaryText),
      bodySmall: label.copyWith(fontSize: 11),
      labelLarge: label.copyWith(fontSize: 13),
      labelMedium: label.copyWith(fontSize: 11),
      labelSmall: label.copyWith(fontSize: 9.5, letterSpacing: 0.5),
    );
  }

  static TextTheme get darkTextTheme =>
      _textTheme(_displayDark, _bodyDark, _labelDark, textSecondary);
  static TextTheme get lightTextTheme =>
      _textTheme(_displayLight, _bodyLight, _labelLight, textSecondaryLight);

  static ThemeData get theme => darkTheme;

  static ThemeData _baseTheme({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color surfaceContainerHighest,
    required Color primary,
    required Color secondary,
    required Color error,
    required Color onSurface,
    required Color outline,
    required Color variant,
    required TextTheme textTheme,
  }) {
    final isDark = brightness == Brightness.dark;
    final scheme = isDark
        ? ColorScheme.dark(
            surface: surface,
            surfaceContainerHighest: surfaceContainerHighest,
            primary: primary,
            secondary: secondary,
            error: error,
            onSurface: onSurface,
            onError: Colors.white,
            outline: outline,
          )
        : ColorScheme.light(
            surface: surface,
            surfaceContainerHighest: surfaceContainerHighest,
            primary: primary,
            secondary: secondary,
            error: error,
            onSurface: onSurface,
            onError: Colors.white,
            outline: outline,
          );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: background,
      colorScheme: scheme,
      textTheme: textTheme,
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: outline, width: 1),
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: statusHealthy,
        unselectedLabelColor: textMuted,
        indicatorColor: statusHealthy,
        dividerColor: Colors.transparent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 64,
        indicatorColor: primary.withValues(alpha: isDark ? 0.2 : 0.15),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: variant,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: isDark ? textPrimary : textPrimaryLight,
          fontWeight: FontWeight.w600,
        ),
        behavior: SnackBarBehavior.floating,
      ),
      dividerTheme: DividerThemeData(
        color: outline.withValues(alpha: 0.5),
        thickness: 1,
        space: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: isDark ? Colors.black : Colors.white,
          textStyle: textTheme.titleSmall,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  static ThemeData get darkTheme => _baseTheme(
        brightness: Brightness.dark,
        background: pureOledBackground,
        surface: surfaceDark,
        surfaceContainerHighest: surfaceVariantDark,
        primary: statusHealthy,
        secondary: statusCharging,
        error: statusCritical,
        onSurface: textPrimary,
        outline: surfaceBorderDark,
        variant: surfaceVariantDark,
        textTheme: darkTextTheme,
      );

  static ThemeData get lightTheme => _baseTheme(
        brightness: Brightness.light,
        background: lightBackground,
        surface: surfaceLight,
        surfaceContainerHighest: surfaceVariantLight,
        primary: statusHealthyLight,
        secondary: statusChargingLight,
        error: statusCriticalLight,
        onSurface: textPrimaryLight,
        outline: surfaceBorderLight,
        variant: surfaceVariantLight,
        textTheme: lightTextTheme,
      );

  static SystemUiOverlayStyle overlayStyleFor(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isLight ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: isLight ? lightBackground : pureOledBackground,
      systemNavigationBarIconBrightness: isLight ? Brightness.dark : Brightness.light,
    );
  }
}
