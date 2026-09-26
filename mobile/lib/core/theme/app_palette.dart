import 'package:flutter/painting.dart';

/// The app's single colour source of truth — every other colour API
/// ([AppTheme]'s `ColorScheme`, [AppColors]' semantic roles, the legacy
/// [VendorPalette] aliases, [AppGradients]) reads from here, so the visual
/// identity is changed in exactly one place.
///
/// One identity for every role (customer, vendor, driver, admin): a warm
/// off-white background, deep burgundy/raspberry primary, soft coral/pink
/// accent, near-black text. Green/orange/red/blue are reserved for semantic
/// status only — never decoration.
///
/// Light only for now. Dark mode is not a separate identity in this phase:
/// when it's built, add a second set of these same roles and feed it through
/// `AppTheme._themeFrom` rather than inventing new colours per screen.
class AppPalette {
  AppPalette._();

  // Surfaces.
  static const background = Color(0xFFFAFAF8);
  static const surface = Color(0xFFFFFFFF);
  /// Cards and list rows — white on the off-white background.
  static const surfaceContainer = Color(0xFFFFFFFF);
  /// Chips, avatars, input fills, selected rows: a subtly darker warm tone.
  static const surfaceElevated = Color(0xFFF2EFEB);

  // Brand.
  static const primary = Color(0xFFA3224A);
  static const onPrimary = Color(0xFFFFFFFF);
  /// Lighter step of [primary], only for the end stop of primary gradients.
  static const primaryLight = Color(0xFFC23A62);
  static const primaryContainer = Color(0xFFFBE4EB);
  static const onPrimaryContainer = Color(0xFF5E0F28);
  static const accent = Color(0xFFFF8FA8);
  static const onAccent = Color(0xFF3F0A19);

  // Text.
  static const textPrimary = Color(0xFF171717);
  static const textSecondary = Color(0xFF5E5A56);
  /// Hints, placeholders and de-emphasised metadata only (not body text).
  static const textMuted = Color(0xFF8C8782);

  // Lines.
  static const border = Color(0xFFE6E2DD);

  // Semantic status.
  static const success = Color(0xFF1E8A4C);
  static const warning = Color(0xFFC46A00);
  static const error = Color(0xFFC62828);
  static const info = Color(0xFF2563EB);
  static const rating = Color(0xFFF2A100);
  static const discount = Color(0xFFE4572E);

  // States.
  static const disabled = Color(0xFFD9D5D0);
  static const onDisabled = Color(0xFF8C8782);

  // Effects.
  static const shadow = Color(0xFF000000);
  /// Dark overlay behind controls placed on top of photos.
  static const imageScrim = Color(0x66000000);

  /// Per-category tile backdrops on the customer home category row (kept as
  /// distinct tones on purpose — a wall of identical tiles would defeat the
  /// row's purpose). Referenced by name from `category_section.dart`.
  static const categoryRestaurants = Color(0xFF7A1F3D);
  static const categoryGroceries = Color(0xFF2F5233);
  static const categoryPharmacy = Color(0xFF5B3A8C);
  static const categoryBakery = Color(0xFF8A6D1E);
  static const categoryDrinks = Color(0xFF1F5C5C);
  static const categoryBeauty = Color(0xFF6B3B8C);
  static const categoryClothing = Color(0xFF1E4A7A);
  static const categoryGifts = Color(0xFF3B2E8C);
  static const categoryFlowers = Color(0xFFA8447A);
  static const categoryElectronics = Color(0xFF2C2C54);
  static const categoryKidsToys = Color(0xFFB06A1E);
  static const categoryHomeAndDiy = Color(0xFF6B5C3D);
  static const categoryHobbies = Color(0xFF3A5A7A);
  static const categoryOffers = Color(0xFFB0442E);
}
