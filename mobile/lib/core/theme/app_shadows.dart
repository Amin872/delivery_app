import 'package:flutter/material.dart';

import 'app_palette.dart';

/// Centralized elevation shadows. Deliberately subtle — these are for the
/// few surfaces that should visually lift off the page (hero cards, floating
/// controls), not a default applied to every `Card` (the app's `CardTheme`
/// already handles ordinary cards via `elevation`/`shadowColor`).
///
/// Built from [ColorScheme.shadow] rather than a fixed black, so shadows stay
/// correctly balanced in both light and dark mode instead of over-darkening
/// dark-mode surfaces.
/// Elevation shadows, all tinted from [AppPalette.shadow]. The
/// [ColorScheme] parameter is kept for call-site compatibility.
class AppShadows {
  AppShadows._();

  static const List<BoxShadow> none = [];

  static List<BoxShadow> small(ColorScheme colorScheme) => [
        BoxShadow(
          color: AppPalette.shadow.withValues(alpha: 0.08),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ];

  static List<BoxShadow> medium(ColorScheme colorScheme) => [
        BoxShadow(
          color: AppPalette.shadow.withValues(alpha: 0.12),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> large(ColorScheme colorScheme) => [
        BoxShadow(
          color: AppPalette.shadow.withValues(alpha: 0.16),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ];

  /// Floating controls over content (search pill, bag button, header
  /// buttons on photos).
  static List<BoxShadow> floating() => [
        BoxShadow(
          color: AppPalette.shadow.withValues(alpha: 0.18),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ];

  /// Shadow colour for `Material(elevation:)` floating controls.
  static Color get floatingShadowColor => AppPalette.shadow.withValues(alpha: 0.35);
}
