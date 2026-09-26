import 'package:flutter/material.dart';

import 'app_palette.dart';

export 'app_palette.dart';

/// Semantic colour roles `ColorScheme` has no field for (success, warning,
/// info, rating, discount, disabled, accent, secondary/muted text).
///
/// Everything `ColorScheme` already covers (`primary`, `surface`,
/// `onSurface`, `onSurfaceVariant`, `outlineVariant`, `error`, ...) is read
/// from `Theme.of(context).colorScheme` directly — built from the same
/// [AppPalette] tokens in `AppTheme` — so it isn't duplicated here.
///
/// The [ColorScheme] parameter is kept so call sites stay brightness-aware:
/// today there is one (light) identity, and a future dark token set only
/// needs to be selected here, not at every call site.
class AppColors {
  AppColors._();

  static Color success(ColorScheme colorScheme) => AppPalette.success;

  static Color warning(ColorScheme colorScheme) => AppPalette.warning;

  static Color info(ColorScheme colorScheme) => AppPalette.info;

  /// Discounted-price accent — distinct from [warning] so a promo price and
  /// a warning never read as the same signal.
  static Color discount(ColorScheme colorScheme) => AppPalette.discount;

  static Color rating(ColorScheme colorScheme) => AppPalette.rating;

  static Color accent(ColorScheme colorScheme) => AppPalette.accent;

  static Color textSecondary(ColorScheme colorScheme) => AppPalette.textSecondary;

  static Color textMuted(ColorScheme colorScheme) => AppPalette.textMuted;

  static Color disabled(ColorScheme colorScheme) => AppPalette.disabled;
}

/// LEGACY ALIASES — not a palette of its own any more.
///
/// This class used to define a separate dark-navy/cyan identity for the
/// customer and admin screens. That identity is retired: every member now
/// points at the unified [AppPalette] token with the same *role*, and
/// [themeFrom] returns the app theme unchanged, so the ~50 existing callers
/// render in the single burgundy/off-white identity without each being
/// rewritten in the foundation phase.
///
/// New code must use [AppPalette] / `Theme.of(context).colorScheme` /
/// [AppColors] instead. Screens migrate off these aliases in Phases 2B–2E;
/// the class is deleted once no caller remains.
class VendorPalette {
  VendorPalette._();

  static const background = AppPalette.background;
  static const surface = AppPalette.surface;
  static const surfaceContainer = AppPalette.surfaceContainer;
  static const surfaceElevated = AppPalette.surfaceElevated;
  /// Role: the brand primary (was cyan).
  static const primaryCyan = AppPalette.primary;
  /// Role: the lighter primary step used as a gradient end (was cyan).
  static const secondaryCyan = AppPalette.primaryLight;
  static const textPrimary = AppPalette.textPrimary;
  static const textSecondary = AppPalette.textSecondary;
  static const textMuted = AppPalette.textMuted;
  static const divider = AppPalette.border;

  /// No-op kept for existing `Theme(data: VendorPalette.themeFrom(...))`
  /// wrappers: the ambient app theme already *is* the unified identity.
  static ThemeData themeFrom(ThemeData base) => base;
}
