import 'package:colorful_iconify_flutter/icons/noto.dart';
import 'package:flutter/material.dart';
import 'package:iconify_flutter/iconify_flutter.dart';

import '../../../core/l10n/enum_labels.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/vendor.dart';

/// One entry in the home category row. Richer than [VendorCategory] on
/// purpose: the row shows every vertical a customer should be able to
/// browse toward (matching the full Wolt-style category list), while only
/// some of those verticals have real vendor data behind them yet.
/// [vendorCategory] is the real marketplace category this entry filters the
/// home feed by; null means this vertical has no backing `VendorCategory`
/// in the data model today, so selecting it honestly shows the existing
/// "no products in this category yet" empty state rather than silently
/// fabricating vendors that don't exist. Extending `VendorCategory` itself
/// (and the Firestore rules/backend behind it) is out of scope for this
/// UI-only category row.
enum HomeCategoryId {
  restaurants,
  groceries,
  pharmacy,
  bakery,
  drinks,
  beauty,
  clothing,
  gifts,
  flowers,
  electronics,
  kidsToys,
  homeAndDiy,
  hobbies,
  offers,
}

class HomeCategoryEntry {
  const HomeCategoryEntry({
    required this.id,
    required this.icon,
    required this.color,
    this.vendorCategory,
  });

  final HomeCategoryId id;
  // Raw SVG markup from `colorful_iconify_flutter`'s `Noto` set (Google's
  // full-color emoji-style illustrations), rendered via `Iconify` — not an
  // `IconData`, since Material's icon font only draws single-color glyphs
  // and this row needs an actual colorful product illustration per
  // category (see the redesign brief this replaced: "richer than generic
  // Material icons"). The same string is reused at both large and small
  // size, so the exact same illustration persists through the collapse.
  final String icon;
  final Color color;
  final VendorCategory? vendorCategory;
}

/// Distinct per-category backdrop tones — a wall of identical tiles would
/// defeat the point of a category row. Restaurants leads the list (and is
/// the default selection — see `CustomerHomeScreen`) since the home feed is
/// primarily a restaurant feed; customers reach every other vertical
/// through this row. Deliberately no "All" entry and nothing named
/// "تصنيف" — every entry is a real, specific vertical.
const List<HomeCategoryEntry> homeCategories = [
  HomeCategoryEntry(
    id: HomeCategoryId.restaurants,
    icon: Noto.pizza,
    color: Color(0xFF7A1F3D),
    vendorCategory: VendorCategory.restaurants,
  ),
  HomeCategoryEntry(
    id: HomeCategoryId.groceries,
    icon: Noto.avocado,
    color: Color(0xFF2F5233),
    vendorCategory: VendorCategory.groceries,
  ),
  HomeCategoryEntry(
    id: HomeCategoryId.pharmacy,
    icon: Noto.pill,
    color: Color(0xFF5B3A8C),
    vendorCategory: VendorCategory.pharmacy,
  ),
  HomeCategoryEntry(
    id: HomeCategoryId.bakery,
    icon: Noto.croissant,
    color: Color(0xFF8A6D1E),
    vendorCategory: VendorCategory.bakery,
  ),
  HomeCategoryEntry(
    id: HomeCategoryId.drinks,
    icon: Noto.cup_with_straw,
    color: Color(0xFF1F5C5C),
    vendorCategory: VendorCategory.drinks,
  ),
  HomeCategoryEntry(
    id: HomeCategoryId.beauty,
    icon: Noto.lotion_bottle,
    color: Color(0xFF6B3B8C),
  ),
  HomeCategoryEntry(
    id: HomeCategoryId.clothing,
    icon: Noto.t_shirt,
    color: Color(0xFF1E4A7A),
  ),
  HomeCategoryEntry(
    id: HomeCategoryId.gifts,
    icon: Noto.wrapped_gift,
    color: Color(0xFF3B2E8C),
  ),
  HomeCategoryEntry(
    id: HomeCategoryId.flowers,
    icon: Noto.bouquet,
    color: Color(0xFFA8447A),
  ),
  HomeCategoryEntry(
    id: HomeCategoryId.electronics,
    icon: Noto.headphone,
    color: Color(0xFF2C2C54),
  ),
  HomeCategoryEntry(
    id: HomeCategoryId.kidsToys,
    icon: Noto.teddy_bear,
    color: Color(0xFFB06A1E),
  ),
  HomeCategoryEntry(
    id: HomeCategoryId.homeAndDiy,
    icon: Noto.hammer_and_wrench,
    color: Color(0xFF6B5C3D),
  ),
  HomeCategoryEntry(
    id: HomeCategoryId.hobbies,
    icon: Noto.books,
    color: Color(0xFF3A5A7A),
  ),
  HomeCategoryEntry(
    id: HomeCategoryId.offers,
    icon: Noto.label,
    color: Color(0xFFB0442E),
  ),
];

String homeCategoryLabel(BuildContext context, HomeCategoryId id) {
  final l10n = AppLocalizations.of(context)!;
  switch (id) {
    case HomeCategoryId.restaurants:
      return vendorCategoryLabel(context, VendorCategory.restaurants);
    case HomeCategoryId.groceries:
      return vendorCategoryLabel(context, VendorCategory.groceries);
    case HomeCategoryId.pharmacy:
      return vendorCategoryLabel(context, VendorCategory.pharmacy);
    case HomeCategoryId.bakery:
      return vendorCategoryLabel(context, VendorCategory.bakery);
    case HomeCategoryId.drinks:
      return vendorCategoryLabel(context, VendorCategory.drinks);
    case HomeCategoryId.beauty:
      return l10n.homeCategoryBeauty;
    case HomeCategoryId.clothing:
      return l10n.homeCategoryClothing;
    case HomeCategoryId.gifts:
      return l10n.homeCategoryGifts;
    case HomeCategoryId.flowers:
      return l10n.homeCategoryFlowers;
    case HomeCategoryId.electronics:
      return l10n.homeCategoryElectronics;
    case HomeCategoryId.kidsToys:
      return l10n.homeCategoryKidsToys;
    case HomeCategoryId.homeAndDiy:
      return l10n.homeCategoryHomeAndDiy;
    case HomeCategoryId.hobbies:
      return l10n.homeCategoryHobbies;
    case HomeCategoryId.offers:
      return l10n.homeCategoryOffers;
  }
}

const double categoryHeaderMaxExtent = 158;
const double categoryHeaderMinExtent = 60;

/// Collapsing category header for [CustomerHomeScreen] — large image cards
/// at the top of the page that morph into a compact pinned pill bar as the
/// user scrolls, matching the reference screen recording. A single
/// [SliverPersistentHeaderDelegate] (not two separate slivers, one pinned
/// one not) drives both visual states from one `shrinkOffset`, crossfading
/// between them, so there is exactly one category row on screen at any
/// scroll position rather than a large row and a compact bar both visible
/// at once. Each entry's icon/color stays identical across both states, so
/// the same visual element the user picked out at the top is still there
/// once it collapses. [bigController]/[pillController] are owned by the
/// parent screen's State (not this delegate, which is recreated on every
/// rebuild) so scroll position survives category-selection rebuilds.
class CategoryCollapsingHeaderDelegate extends SliverPersistentHeaderDelegate {
  CategoryCollapsingHeaderDelegate({
    required this.selected,
    required this.onSelected,
    required this.bigController,
    required this.pillController,
  });

  final HomeCategoryId selected;
  final ValueChanged<HomeCategoryId> onSelected;
  final ScrollController bigController;
  final ScrollController pillController;

  @override
  double get minExtent => categoryHeaderMinExtent;

  @override
  double get maxExtent => categoryHeaderMaxExtent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final t = (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);
    final bigOpacity = (1 - t * 2).clamp(0.0, 1.0);
    final pillOpacity = ((t - 0.5) * 2).clamp(0.0, 1.0);

    return ColoredBox(
      color: VendorPalette.background,
      child: SizedBox.expand(
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Opacity(
                opacity: bigOpacity,
                child: IgnorePointer(
                  ignoring: t > 0.5,
                  child: _LargeCategoryRow(
                    controller: bigController,
                    selected: selected,
                    onSelected: onSelected,
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Opacity(
                opacity: pillOpacity,
                child: IgnorePointer(
                  ignoring: t <= 0.5,
                  child: _CompactPillRow(
                    controller: pillController,
                    selected: selected,
                    onSelected: onSelected,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant CategoryCollapsingHeaderDelegate oldDelegate) =>
      oldDelegate.selected != selected;
}

class _LargeCategoryRow extends StatelessWidget {
  const _LargeCategoryRow({required this.controller, required this.selected, required this.onSelected});

  final ScrollController controller;
  final HomeCategoryId selected;
  final ValueChanged<HomeCategoryId> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: categoryHeaderMaxExtent,
      child: ListView(
        controller: controller,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        children: [
          for (final entry in homeCategories)
            _LargeCard(
              label: homeCategoryLabel(context, entry.id),
              icon: entry.icon,
              color: entry.color,
              selected: selected == entry.id,
              onTap: () => onSelected(entry.id),
            ),
        ],
      ),
    );
  }
}

class _LargeCard extends StatelessWidget {
  const _LargeCard({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  static const double _imageSize = 92;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: InkWell(
        borderRadius: AppRadius.large,
        onTap: onTap,
        child: SizedBox(
          width: 100,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: _imageSize,
                height: _imageSize,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: AppRadius.large,
                  border: selected
                      ? Border.all(color: VendorPalette.primaryCyan, width: 2.5)
                      : null,
                ),
                // No `color:` — that would tint the whole illustration a
                // single flat color via Iconify's ColorFilter, destroying
                // the point of using a full-color Noto icon here.
                alignment: Alignment.center,
                child: Iconify(icon, size: 52),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 32,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: VendorPalette.textPrimary,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactPillRow extends StatelessWidget {
  const _CompactPillRow({required this.controller, required this.selected, required this.onSelected});

  final ScrollController controller;
  final HomeCategoryId selected;
  final ValueChanged<HomeCategoryId> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: categoryHeaderMinExtent,
      child: ListView(
        controller: controller,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        children: [
          for (final entry in homeCategories)
            _CompactPill(
              label: homeCategoryLabel(context, entry.id),
              icon: entry.icon,
              color: entry.color,
              selected: selected == entry.id,
              onTap: () => onSelected(entry.id),
            ),
        ],
      ),
    );
  }
}

class _CompactPill extends StatelessWidget {
  const _CompactPill({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        borderRadius: AppRadius.pill,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? color : VendorPalette.surfaceContainer,
            borderRadius: AppRadius.pill,
            border: selected ? Border.all(color: VendorPalette.primaryCyan, width: 1.5) : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Same icon string as the large card, at a smaller size — the
              // illustration persists through the collapse instead of
              // swapping to a different, plainer glyph.
              Iconify(icon, size: 20),
              const SizedBox(width: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: VendorPalette.textPrimary,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
