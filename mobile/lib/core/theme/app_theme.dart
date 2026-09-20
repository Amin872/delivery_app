import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const brandColor = Color(0xFF7A1F3D);

  static ThemeData get light => _themeFrom(
        ColorScheme.fromSeed(seedColor: brandColor, brightness: Brightness.light),
      );

  static ThemeData get dark => _themeFrom(
        ColorScheme.fromSeed(seedColor: brandColor, brightness: Brightness.dark),
      );

  static ThemeData _themeFrom(ColorScheme colorScheme) {
    final textTheme = _textTheme(colorScheme);

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      // Applied last, over every style in `textTheme` below (including the
      // ones that already set an explicit `fontWeight`) — `ThemeData` layers
      // `fontFamily` on top of the merged text theme rather than only
      // filling in styles that omit it, so this alone is enough to cover
      // the whole scale without repeating the family per style.
      fontFamily: 'Noto Sans Arabic',
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

  /// Full Material 3 type scale with a deliberate weight hierarchy — heavier
  /// weights are reserved for roles that need to stand out (names, prices,
  /// buttons); body/label roles stay at regular/medium so a screen full of
  /// text doesn't read as uniformly bold. Sizes are Material 3's own
  /// defaults (untouched); only `fontWeight` is overridden here, so this
  /// only needs to set what actually changes per role rather than
  /// redeclaring the whole scale from scratch.
  ///
  /// Suggested usage mapping for the vendor-menu screen (not enforced by
  /// this class, just the intended pairing):
  /// - `headlineMedium` — vendor/restaurant name
  /// - `headlineSmall` / `titleLarge` — section or category name
  /// - `titleMedium` — product/menu-item name
  /// - `bodyMedium` — product description
  /// - `titleMedium` + [AppColors.discount] — discounted price (struck
  ///   through original price uses `bodySmall` + [AppColors.textSecondary])
  /// - `bodySmall` — metadata (ETA, distance, order count)
  /// - `labelLarge` — button text
  static TextTheme _textTheme(ColorScheme colorScheme) {
    return const TextTheme(
      displayLarge: TextStyle(fontWeight: FontWeight.w700),
      displayMedium: TextStyle(fontWeight: FontWeight.w700),
      displaySmall: TextStyle(fontWeight: FontWeight.w700),
      headlineLarge: TextStyle(fontWeight: FontWeight.w700),
      headlineMedium: TextStyle(fontWeight: FontWeight.w700),
      headlineSmall: TextStyle(fontWeight: FontWeight.w700),
      titleLarge: TextStyle(fontWeight: FontWeight.w600),
      titleMedium: TextStyle(fontWeight: FontWeight.w600),
      titleSmall: TextStyle(fontWeight: FontWeight.w500),
      bodyLarge: TextStyle(fontWeight: FontWeight.w400),
      bodyMedium: TextStyle(fontWeight: FontWeight.w400),
      bodySmall: TextStyle(fontWeight: FontWeight.w400),
      labelLarge: TextStyle(fontWeight: FontWeight.w600),
      labelMedium: TextStyle(fontWeight: FontWeight.w500),
      labelSmall: TextStyle(fontWeight: FontWeight.w500),
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
  /// hue-shifting/lightening the theme's seed color itself — deliberately
  /// *not* `colorScheme.primary`: Material 3 inverts that role's emphasis
  /// between brightnesses (it's the vivid, high-contrast tone in light mode
  /// but a light pastel tone in dark mode, meant for small accents, not a
  /// big filled surface — confirmed by inspecting `ColorScheme.fromSeed`
  /// directly: dark mode's `primary` for this seed renders as pale pink).
  /// Anchoring to the seed keeps this brand gradient the same rich burgundy
  /// in both modes, paired with [onPrimary] (always white) rather than
  /// `colorScheme.onPrimary`, which would flip to dark text in dark mode.
  static LinearGradient primary(ColorScheme colorScheme) {
    final hsl = HSLColor.fromColor(AppTheme.brandColor);
    final shifted = hsl
        .withHue((hsl.hue + 25) % 360)
        .withLightness((hsl.lightness + 0.10).clamp(0.0, 1.0))
        .withSaturation((hsl.saturation + 0.05).clamp(0.0, 1.0));
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [AppTheme.brandColor, shifted.toColor()],
    );
  }

  /// Foreground color for content painted on [primary] — always white,
  /// since [primary] is a fixed brand color rather than a brightness-aware
  /// `ColorScheme` role (see the note on [primary]).
  static const onPrimary = Colors.white;

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
