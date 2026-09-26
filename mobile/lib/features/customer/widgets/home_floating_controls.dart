import 'package:flutter/material.dart';

import '../../../core/format/display_formatters.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';

/// Floating white/off-white search pill for the redesigned
/// CustomerHomeScreen — replaces the previous bottom-right
/// `FloatingActionButton.extended`. Fixed white (not `ColorScheme`) since
/// this deliberately reads as a bright, neutral control against the
/// screen's dark-navy background regardless of theme, matching the
/// reference. Opens the same `SearchScreen` as before — only the visual
/// presentation changed.
class HomeFloatingSearchBar extends StatelessWidget {
  const HomeFloatingSearchBar({required this.onTap, super.key});

  final VoidCallback onTap;

  static const double height = 52;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Material(
      color: AppPalette.surface,
      borderRadius: AppRadius.pill,
      elevation: 6,
      shadowColor: AppShadows.floatingShadowColor,
      child: InkWell(
        borderRadius: AppRadius.pill,
        onTap: onTap,
        child: Container(
          height: height,
          // Tighter padding/gaps than the app's usual AppSpacing.lg — this
          // pill is now a fixed ~35% of the screen width (see
          // CustomerHomeScreen), narrow enough that the default spacing
          // pushed the row past its available width on smaller phones.
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Row(
            children: [
              const Icon(Icons.search, color: AppPalette.textPrimary, size: 20),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  l10n.searchFieldHint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppPalette.textPrimary, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              const Icon(Icons.tune, color: AppPalette.textMuted, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// Floating white circular bag/cart button — new on the home screen (there
/// was no cart entry point here before this redesign), wired to the same
/// real `cartProvider` state every other screen's cart button reads, not a
/// fabricated/static icon. Shows a small cyan count badge only when the
/// cart actually has items, matching [FloatingOrderButton]'s
/// always-real-data rule.
class HomeFloatingBagButton extends StatelessWidget {
  const HomeFloatingBagButton({required this.itemCount, required this.onTap, super.key});

  final int itemCount;
  final VoidCallback onTap;

  static const double diameter = 52;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Material(
      color: AppPalette.surface,
      shape: const CircleBorder(),
      elevation: 6,
      shadowColor: AppShadows.floatingShadowColor,
      child: SizedBox(
        width: diameter,
        height: diameter,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Center(
              child: IconButton(
                icon: const Icon(Icons.shopping_bag_outlined, color: AppPalette.textPrimary),
                tooltip: l10n.cartTitle,
                onPressed: onTap,
              ),
            ),
            if (itemCount > 0)
              Positioned(
                top: -2,
                right: -2,
                child: Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: VendorPalette.primaryCyan,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    formatCount(itemCount, Localizations.localeOf(context).toString()),
                    style: const TextStyle(
                      color: VendorPalette.background,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
