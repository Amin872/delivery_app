import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const _seedColor = Colors.deepOrange;

  static ThemeData get light => _themeFrom(
        ColorScheme.fromSeed(seedColor: _seedColor, brightness: Brightness.light),
      );

  static ThemeData get dark => _themeFrom(
        ColorScheme.fromSeed(seedColor: _seedColor, brightness: Brightness.dark),
      );

  static ThemeData _themeFrom(ColorScheme colorScheme) {
    final textTheme = _textTheme(colorScheme);

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 2,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size.fromHeight(44),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shadowColor: colorScheme.shadow.withValues(alpha: 0.25),
        color: colorScheme.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  static TextTheme _textTheme(ColorScheme colorScheme) {
    return const TextTheme(
      headlineSmall: TextStyle(fontWeight: FontWeight.w700),
      titleLarge: TextStyle(fontWeight: FontWeight.w600),
      titleMedium: TextStyle(fontWeight: FontWeight.w600),
      labelLarge: TextStyle(fontWeight: FontWeight.w600),
    ).apply(
      bodyColor: colorScheme.onSurface,
      displayColor: colorScheme.onSurface,
    );
  }
}

/// Gradient design tokens, derived from a [ColorScheme] so they adapt
/// automatically between light and dark mode instead of needing a separate
/// hand-tuned dark palette.
class AppGradients {
  AppGradients._();

  /// Diagonal brand gradient for primary CTAs and accent surfaces. Built by
  /// hue-shifting/lightening `colorScheme.primary` itself (rather than
  /// pairing it with `colorScheme.tertiary`) — Material 3's auto-derived
  /// tertiary tone can land on a muddy, unrelated hue for some seed colors,
  /// while a same-family shift always reads as cohesive and vibrant.
  static LinearGradient primary(ColorScheme colorScheme) {
    final hsl = HSLColor.fromColor(colorScheme.primary);
    final shifted = hsl
        .withHue((hsl.hue + 25) % 360)
        .withLightness((hsl.lightness + 0.10).clamp(0.0, 1.0))
        .withSaturation((hsl.saturation + 0.05).clamp(0.0, 1.0));
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [colorScheme.primary, shifted.toColor()],
    );
  }

  /// Very subtle background wash for auth/onboarding screens.
  static LinearGradient surface(ColorScheme colorScheme) {
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        colorScheme.surface,
        Color.alphaBlend(
          colorScheme.primaryContainer.withValues(alpha: 0.35),
          colorScheme.surface,
        ),
      ],
    );
  }
}
