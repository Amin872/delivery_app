import 'package:flutter/material.dart';
// intl exports its own conflicting `TextDirection` — hide it so
// `Directionality.of(context) == TextDirection.rtl` below resolves to
// Flutter's (dart:ui's) TextDirection instead.
import 'package:intl/intl.dart' hide TextDirection;

import '../../../core/theme/app_spacing.dart';
import '../../../models/vendor.dart';
import 'most_ordered_card.dart';

// Card width as a fraction of the section's available width — measured from
// the reference screenshot (a 166dp card on a 390dp-wide screen), then kept
// as a *proportion* rather than a fixed dp so it scales instead of assuming
// one device width. Clamped to a sane range so it doesn't balloon on a wide
// window (this screen is capped by ResponsiveCenter, but the clamp is the
// same defensive pattern StoreInfoSection's logo sizing already uses).
const double _cardWidthFraction = 0.426;
const double _cardWidthMin = 140;
const double _cardWidthMax = 220;
const double _arrowButtonSize = 40;

/// Horizontal "Most ordered" carousel — VendorMenuScreen renders this in
/// place of the normal vertical `MenuItemCard` list only for the single
/// `MenuSection` where `isMostOrdered` is true (see
/// `core/discovery/menu_sections.dart`, which ranks [items] by real,
/// server-aggregated `MenuItem.orderCount` — nothing here invents or
/// re-derives popularity); every other category section keeps the plain
/// vertical list untouched.
class MostOrderedSection extends StatelessWidget {
  const MostOrderedSection({
    required this.title,
    required this.items,
    required this.currencyFormat,
    required this.onAddToCart,
    required this.onViewAll,
    required this.onTapItem,
    super.key,
  });

  final String title;
  final List<MenuItem> items;
  final NumberFormat currencyFormat;
  final ValueChanged<MenuItem> onAddToCart;

  /// Opens the tapped product's details sheet — separate from
  /// [onAddToCart] so the card's own "+" badge keeps adding directly.
  final ValueChanged<MenuItem> onTapItem;

  /// Opens the full "Most ordered" grid page — shown as a trailing arrow
  /// button at the end of the carousel (see [_ViewAllArrow]), not by hiding
  /// it once every item happens to fit on screen.
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth =
                (constraints.maxWidth * _cardWidthFraction).clamp(_cardWidthMin, _cardWidthMax);
            final rowHeight = cardWidth / mostOrderedImageAspectRatio + mostOrderedFooterHeight;

            return SizedBox(
              height: rowHeight,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                itemCount: items.length + 1,
                separatorBuilder: (context, index) => const SizedBox(width: AppSpacing.sm),
                itemBuilder: (context, index) {
                  if (index == items.length) {
                    return SizedBox(
                      height: rowHeight,
                      child: Center(
                        child: _ViewAllArrow(onTap: onViewAll),
                      ),
                    );
                  }
                  final item = items[index];
                  return SizedBox(
                    width: cardWidth,
                    child: MostOrderedCard(
                      item: item,
                      currencyFormat: currencyFormat,
                      onAddToCart: () => onAddToCart(item),
                      onTap: () => onTapItem(item),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Trailing "view all" button at the end of the carousel — a fixed 40x40dp
/// square (measured from the reference), not the app's usual circular
/// "View all" affordance (`ProductCarousel`'s `_ViewAllButton`), reusing the
/// same dark-teal/cyan pair as the card's "+" badge. Always shown, never
/// hidden just because the current items happen to fit on screen — matching
/// "do not simply hide the arrow ... when more products exist."
class _ViewAllArrow extends StatelessWidget {
  const _ViewAllArrow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: mostOrderedAccentBackground,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: _arrowButtonSize,
          height: _arrowButtonSize,
          // `Icon` has no built-in RTL auto-mirroring (unlike `Image`'s
          // `matchTextDirection`), so this flips by hand: under this
          // screen's RTL Directionality the reference shows "<", and it
          // flips back to ">" automatically if the app ever runs in an LTR
          // locale instead of a separate icon chosen for each direction.
          // `arrow_forward_ios_rounded` renders as "<" unflipped (verified
          // live) — flipping is for the LTR case, not RTL.
          child: Transform.flip(
            flipX: Directionality.of(context) != TextDirection.rtl,
            child: const Icon(
              Icons.arrow_forward_ios_rounded,
              color: mostOrderedAccentForeground,
              size: 18,
            ),
          ),
        ),
      ),
    );
  }
}
