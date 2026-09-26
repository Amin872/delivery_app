import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_palette.dart';
import 'app_radius.dart';
import 'app_sizes.dart';
import 'app_spacing.dart';

/// The one app theme. Every role (customer, vendor, driver, admin) renders
/// from this; all colours come from [AppPalette], all shapes from
/// [AppRadius], control sizes from [AppSizes].
class AppTheme {
  AppTheme._();

  /// Bundled variable font (weights 100–900, Arabic + Latin + both digit
  /// sets — see pubspec.yaml). Flutter drives its `wght` axis from
  /// `FontWeight`, so every weight below is a real weight, not synthetic bold.
  static const fontFamily = 'Noto Sans Arabic';

  /// Kept for existing references; the brand primary token.
  static const brandColor = AppPalette.primary;

  static ThemeData get light => _themeFrom(_lightScheme);

  /// False until a real dark token set exists. While false, the effective
  /// theme mode is always light (see `app.dart`) and Settings offers no
  /// Dark/System choice — no fake dark theme is exposed.
  static const supportsDarkMode = false;

  /// Dark mode is not a separate identity yet (Phase 2A decision): this
  /// returns the light theme so `themeMode` stays wired through
  /// `MaterialApp` without producing a half-designed dark UI. When a dark
  /// token set exists, build its scheme and pass it to [_themeFrom] here.
  static ThemeData get dark => light;

  static final ColorScheme _lightScheme = ColorScheme.fromSeed(
    seedColor: AppPalette.primary,
    brightness: Brightness.light,
  ).copyWith(
    primary: AppPalette.primary,
    onPrimary: AppPalette.onPrimary,
    primaryContainer: AppPalette.primaryContainer,
    onPrimaryContainer: AppPalette.onPrimaryContainer,
    secondary: AppPalette.accent,
    onSecondary: AppPalette.onAccent,
    error: AppPalette.error,
    onError: AppPalette.onPrimary,
    surface: AppPalette.surface,
    onSurface: AppPalette.textPrimary,
    onSurfaceVariant: AppPalette.textSecondary,
    outline: AppPalette.textMuted,
    outlineVariant: AppPalette.border,
    surfaceContainerLowest: AppPalette.surface,
    surfaceContainerLow: AppPalette.background,
    surfaceContainer: AppPalette.surfaceContainer,
    surfaceContainerHigh: AppPalette.surfaceElevated,
    surfaceContainerHighest: AppPalette.surfaceElevated,
    shadow: AppPalette.shadow,
    surfaceTint: Colors.transparent,
  );

  static ThemeData _themeFrom(ColorScheme colorScheme) {
    final textTheme = _textTheme(colorScheme);
    // Finite minimum widths only — see AppSizes.buttonMinWidth.
    const buttonSize = Size(AppSizes.buttonMinWidth, AppSizes.buttonHeight);
    const buttonShape = RoundedRectangleBorder(borderRadius: AppRadius.medium);

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppPalette.background,
      canvasColor: AppPalette.background,
      dividerColor: AppPalette.border,
      // Applied over every style in `textTheme` — see [fontFamily].
      fontFamily: fontFamily,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: AppPalette.background,
        foregroundColor: AppPalette.textPrimary,
        surfaceTintColor: Colors.transparent,
        // Dark status-bar icons on the light background.
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: buttonSize,
          shape: buttonShape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: buttonSize,
          shape: buttonShape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: buttonSize,
          shape: buttonShape,
          side: const BorderSide(color: AppPalette.border),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(AppSizes.buttonMinWidth, AppSizes.compactButtonHeight),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: AppPalette.surfaceElevated,
        border: OutlineInputBorder(borderRadius: AppRadius.medium, borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: AppRadius.medium, borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.medium,
          borderSide: BorderSide(color: AppPalette.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.medium,
          borderSide: BorderSide(color: AppPalette.error),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 14),
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        color: AppPalette.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.large,
          side: BorderSide(color: AppPalette.border),
        ),
        margin: EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
      ),
      listTileTheme: const ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.medium),
        contentPadding: EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
        iconColor: AppPalette.textSecondary,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppPalette.surfaceElevated,
        selectedColor: AppPalette.primaryContainer,
        checkmarkColor: AppPalette.onPrimaryContainer,
        side: BorderSide.none,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.pill),
        labelStyle: textTheme.labelLarge,
      ),
      dividerTheme: const DividerThemeData(color: AppPalette.border, thickness: 1),
      dialogTheme: const DialogThemeData(
        backgroundColor: AppPalette.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.extraLarge),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppPalette.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.extraLargeValue)),
        ),
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: AppPalette.surface,
        surfaceTintColor: Colors.transparent,
      ),
      navigationRailTheme: const NavigationRailThemeData(backgroundColor: AppPalette.surface),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.medium),
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

  /// Primary CTA gradient: burgundy to its lighter step, direction-aware
  /// (starts at the reading-start corner in both LTR and RTL).
  static LinearGradient primary(ColorScheme colorScheme) {
    return const LinearGradient(
      begin: AlignmentDirectional.topStart,
      end: AlignmentDirectional.bottomEnd,
      colors: [AppPalette.primary, AppPalette.primaryLight],
    );
  }

  /// Foreground color for content painted on [primary] — always white,
  /// since [primary] is a fixed brand color rather than a brightness-aware
  /// `ColorScheme` role (see the note on [primary]).
  static const onPrimary = AppPalette.onPrimary;

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
