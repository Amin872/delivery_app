import 'package:flutter/material.dart';

/// Color aliases for roles `ColorScheme` genuinely has no field for.
///
/// Deliberately small: `background`/`surface`, `surfaceContainerHighest`
/// (the modern replacement for the deprecated `surfaceVariant`),
/// `onSurface` (text-primary), `onSurfaceVariant` (text-secondary),
/// `outlineVariant` (divider), and `error` already exist natively on
/// `ColorScheme` and are used directly elsewhere in the app — duplicating
/// them here would just be a second name for the same value. Only
/// success/warning/discount/rating have no `ColorScheme` equivalent at all.
///
/// Fixed hues rather than derived from the seed color, same reasoning as
/// [AppGradients.onPrimary]: a "success green"/"warning amber" needs to read
/// as unambiguously that color in both light and dark mode, not shift hue
/// with the brand seed. Alpha/lightness is nudged per brightness so each
/// stays legible on its mode's background.
class AppColors {
  AppColors._();

  static Color success(ColorScheme colorScheme) =>
      colorScheme.brightness == Brightness.dark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A);

  static Color warning(ColorScheme colorScheme) =>
      colorScheme.brightness == Brightness.dark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);

  /// Discounted-price accent — distinct from [warning] even though both are
  /// warm tones, so a promo price and a low-stock/expiry warning never look
  /// like the same signal.
  static Color discount(ColorScheme colorScheme) =>
      colorScheme.brightness == Brightness.dark ? const Color(0xFFFF8A65) : const Color(0xFFE64A19);

  static Color rating(ColorScheme colorScheme) =>
      colorScheme.brightness == Brightness.dark ? const Color(0xFFFFD54F) : const Color(0xFFF59E0B);
}

/// Fixed dark-navy/cyan palette for the customer Vendor/Restaurant screen
/// only (Phase 4A visual redesign) — deliberately *not* folded into
/// [AppTheme.light]/[AppTheme.dark]: those still govern the rest of the app
/// and continue to follow the system/user light-dark preference untouched.
/// This screen is a dedicated "always dark" surface (same idea as a video
/// player or a photo-heavy detail screen opting out of the ambient theme),
/// applied via [vendorScreenTheme] rather than by hand-placing this class's
/// constants across widgets, so most existing widgets keep reading
/// `Theme.of(context).colorScheme`/`textTheme` unchanged and only actually
/// need this class directly for the couple of roles `ColorScheme` has no
/// slot for (`textMuted`, the two-step surface/elevated split).
class VendorPalette {
  VendorPalette._();

  static const background = Color(0xFF080A18);
  static const surface = Color(0xFF101326);
  static const surfaceContainer = Color(0xFF151A31);
  static const surfaceElevated = Color(0xFF1B2039);
  static const primaryCyan = Color(0xFF45D8FF);
  static const secondaryCyan = Color(0xFF6BE4FF);
  static const textPrimary = Color(0xFFF5F5F7);
  static const textSecondary = Color(0xFFAEB4CA);
  static const textMuted = Color(0xFF777F99);
  static const divider = Color(0xFF252B43);

  /// Builds a scoped [ThemeData] carrying this palette, derived from [base]
  /// (the ambient app theme) so unrelated theme slots this palette doesn't
  /// care about — `cardTheme`, `inputDecorationTheme`, button themes, font
  /// family — still come from the real app theme rather than Material
  /// defaults. Only `colorScheme` (so `colorScheme.primary`/`surface`/etc.
  /// resolve to this palette) and `textTheme` (re-derived via `.apply` so
  /// the type *scale* stays [AppTheme]'s, just recolored to
  /// [textPrimary]) are overridden. Callers needing [textSecondary] or
  /// [textMuted] still reach for this class directly via `copyWith(color:
  /// ...)`, same as any other role `ColorScheme` has no slot for.
  static ThemeData themeFrom(ThemeData base) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primaryCyan,
      brightness: Brightness.dark,
    ).copyWith(
      surface: surface,
      onSurface: textPrimary,
      onSurfaceVariant: textSecondary,
      outlineVariant: divider,
      primary: primaryCyan,
      onPrimary: background,
      secondary: secondaryCyan,
      surfaceContainer: surfaceContainer,
      surfaceContainerHighest: surfaceElevated,
    );
    return base.copyWith(
      colorScheme: colorScheme,
      textTheme: base.textTheme.apply(bodyColor: textPrimary, displayColor: textPrimary),
    );
  }
}
