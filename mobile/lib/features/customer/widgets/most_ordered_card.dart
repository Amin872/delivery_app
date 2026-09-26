import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/widgets/app_network_image.dart';
import '../../../models/vendor.dart';
import 'cart_quantity_control.dart';

/// Width/height proportions and colors below are measured pixel-for-pixel
/// from the reference "Most ordered" screenshots (not eyeballed): a card's
/// image area keeps a fixed ~1.78:1 (width:height) ratio regardless of the
/// card's own width, and the price/name footer stays a fixed ~90dp tall
/// regardless of width too — so scaling `width` up or down (carousel vs.
/// the 2-column full-page grid) reproduces the same reference proportions
/// rather than needing two different card designs.
const double mostOrderedImageAspectRatio = 1.78;
const double mostOrderedFooterHeight = 90;

/// The `childAspectRatio` a `GridView`/`SliverGrid` of [MostOrderedCard]s
/// needs for a given cell [cardWidth] so the grid's own height-from-ratio
/// math reproduces the same fixed image-ratio + fixed-footer-height card
/// shape as the horizontal carousel — shared by `MostOrderedScreen` and
/// `ProductDetailsSheet`'s recommended-products grid so this formula only
/// lives in one place.
/// [mostOrderedFooterHeight] at the current text scale — the footer holds
/// only text (price + two-line name), so it must grow with it.
double mostOrderedFooterHeightFor(TextScaler scaler) => scaler.scale(mostOrderedFooterHeight);

double mostOrderedCardAspectRatioForWidth(double cardWidth, [TextScaler scaler = TextScaler.noScaling]) {
  final cardHeight = cardWidth / mostOrderedImageAspectRatio + mostOrderedFooterHeightFor(scaler);
  return cardWidth / cardHeight;
}

/// The "+" corner badge / carousel arrow pair: a soft primary-container
/// fill with the brand primary for the icon and prices. Unified-palette
/// tokens (Phase 2A) — previously a dark-teal/cyan pair.
const Color mostOrderedAccentBackground = AppPalette.primaryContainer;
const Color mostOrderedAccentForeground = AppPalette.primary;

/// Fill of every order/checkout pill in the store screens (`ProductOrderBar`'s
/// "Add to order", `FloatingOrderButton`'s "View order"): the brand primary,
/// with [AppPalette.onPrimary]-coloured content.
const Color orderAccentBackground = AppPalette.primary;

/// Product tile shared by VendorMenuScreen's horizontal "Most ordered"
/// carousel (`MostOrderedSection`) and the full "Most ordered" grid page
/// (`MostOrderedScreen`) — same component, same look, per "the carousel and
/// full-page grid should use the same card implementation." Deliberately
/// width-agnostic: callers size it via an ancestor (`SizedBox` in the
/// carousel, `GridView`'s own cell in the full page) and this card fills
/// whatever it's given, so both contexts stay pixel-identical without a
/// duplicate card design.
class MostOrderedCard extends StatelessWidget {
  const MostOrderedCard({
    required this.item,
    required this.currencyFormat,
    required this.onAddToCart,
    this.onTap,
    super.key,
  });

  final MenuItem item;
  final NumberFormat currencyFormat;
  final VoidCallback onAddToCart;

  /// Opens this product's details (`ProductDetailsSheet`) — kept separate
  /// from [onAddToCart] so the "+" badge still adds directly without also
  /// opening details: the badge is its own `InkWell` nested inside this
  /// card's outer `InkWell`, so a tap on the badge is consumed there and
  /// never reaches this one. Optional because some callers (none currently)
  /// may want a purely informational, non-tappable card.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(AppRadius.smallValue);

    return ClipRRect(
      borderRadius: radius,
      child: ColoredBox(
        color: colorScheme.surfaceContainerHighest,
        child: InkWell(
          onTap: onTap,
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: mostOrderedImageAspectRatio,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: item.imageUrl != null
                        ? AppNetworkImage(imageUrl: item.imageUrl!, fit: BoxFit.cover)
                        : Container(
                            color: colorScheme.surfaceContainerHighest,
                            child: Icon(
                              Icons.fastfood_outlined,
                              size: 32,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                  ),
                  // Deliberately a literal top-left position (not RTL-mirrored
                  // PositionedDirectional/start) — the reference keeps this
                  // badge at the physical top-left corner even though the
                  // rest of the app chrome around it is RTL, so matching it
                  // exactly means not flipping this one element.
                  Positioned(
                    top: 0,
                    left: 0,
                    child: CartQuantityControl(
                      item: item,
                      onAdd: onAddToCart,
                      direction: Axis.horizontal,
                      addButtonBuilder: (onTap) => _AddBadge(onTap: onTap, cornerRadius: radius),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: mostOrderedFooterHeightFor(MediaQuery.textScalerOf(context)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Column(
                  // `.start` (not a hardcoded `.end`/`.right`): under this
                  // screen's RTL Directionality that's already the reference
                  // screenshot's right-aligned look, and it flips correctly
                  // if the app is ever run in an LTR locale instead.
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      currencyFormat.format(item.price),
                      style: textTheme.titleMedium?.copyWith(
                        color: mostOrderedAccentForeground,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      item.name,
                      style: textTheme.titleSmall?.copyWith(
                        color: item.available
                            ? colorScheme.onSurface
                            : Theme.of(context).disabledColor,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
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

/// The corner-flag "+" badge itself — flush against the card's top-left
/// corner (sharing its outer radius there) with a large inner curve on the
/// opposite (bottom-right) corner, matching the reference's badge shape
/// (measured: a roughly 36x36dp flag, not a floating circular button).
class _AddBadge extends StatelessWidget {
  const _AddBadge({required this.onTap, required this.cornerRadius});

  final VoidCallback? onTap;
  final BorderRadius cornerRadius;

  static const double _size = 36;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: mostOrderedAccentBackground,
      borderRadius: BorderRadius.only(
        topLeft: cornerRadius.topLeft,
        // Larger than the badge itself so it always resolves to the
        // biggest curve Flutter can fit — a plain quarter-circle sweep,
        // same as the reference.
        bottomRight: const Radius.circular(_size),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.only(
          topLeft: cornerRadius.topLeft,
          bottomRight: const Radius.circular(_size),
        ),
        child: const SizedBox(
          width: _size,
          height: _size,
          child: Center(child: Icon(Icons.add, color: mostOrderedAccentForeground, size: 20)),
        ),
      ),
    );
  }
}
