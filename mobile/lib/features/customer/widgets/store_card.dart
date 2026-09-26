import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_network_image.dart';
import '../../../core/widgets/star_rating.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/vendor.dart';

/// Width/height proportions mirror `MostOrderedCard`'s own
/// aspect-ratio-for-width pattern (`core/discovery`'s
/// mostOrderedCardAspectRatioForWidth`) so both the horizontal carousel and
/// `StoreListScreen`'s grid reproduce the same card shape from one formula
/// instead of two hand-tuned layouts.
const double storeCardImageAspectRatio = 1.55;
const double storeCardBodyHeight = 116;

/// [storeCardBodyHeight] at the current text scale — the body is text only
/// (name, rating, ETA/fee), so it must grow with it.
double storeCardBodyHeightFor(TextScaler scaler) => scaler.scale(storeCardBodyHeight);

double storeCardAspectRatioForWidth(double width, [TextScaler scaler = TextScaler.noScaling]) {
  final height = width / storeCardImageAspectRatio + storeCardBodyHeightFor(scaler);
  return width / height;
}

/// Vendor/store tile for the redesigned CustomerHomeScreen's carousels —
/// large rounded photo, a "free delivery" badge when that's actually true
/// for this vendor (never a fabricated promo like the reference's own
/// Wolt-specific discount copy — see `vendor_carousels.dart`'s dealVendors,
/// the same real signal), name, an optional rating row, a dashed divider,
/// then an ETA/fee footer. Width-agnostic like `MostOrderedCard`: the caller
/// sizes this via an ancestor `SizedBox`/grid cell.
class StoreCard extends StatelessWidget {
  const StoreCard({
    required this.vendor,
    required this.currencyFormat,
    this.onTap,
    this.showRating = true,
    super.key,
  });

  final Vendor vendor;
  final NumberFormat currencyFormat;
  final VoidCallback? onTap;

  /// The full rating UI (stars/"not rated yet") stays available here for
  /// every caller — real rating data, calculation, and submission are
  /// untouched (see VendorMenuScreen/StoreInfoSection, RateOrderDialog).
  /// `false` only hides this one card's visual rating row; CustomerHomeScreen
  /// (via StoreCarousel) is the only caller that passes it — StoreListScreen
  /// ("View all") and FavoritesScreen keep the default `true`.
  final bool showRating;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final hasEta = vendor.etaMinMinutes != null && vendor.etaMaxMinutes != null;
    final hasFee = vendor.deliveryFee != null;
    final isFreeDelivery = vendor.deliveryFee == 0;

    final footerParts = [
      if (hasEta) l10n.etaMinutesRangeLabel(vendor.etaMinMinutes!, vendor.etaMaxMinutes!),
      if (hasFee)
        isFreeDelivery
            ? l10n.freeDeliveryLabel
            : l10n.deliveryFeeValueLabel(currencyFormat.format(vendor.deliveryFee)),
    ];

    return ClipRRect(
      borderRadius: AppRadius.large,
      child: ColoredBox(
        color: VendorPalette.surfaceContainer,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // The photo gives way (by a pixel or two) if the text body
              // needs more than its budgeted height, so the name/rating/
              // ETA are never clipped. Every parent sizes the card with a
              // bounded height (see storeCardBodyHeightFor).
              Flexible(
                child: AspectRatio(
                  aspectRatio: storeCardImageAspectRatio,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: vendor.imageUrl != null
                            ? AppNetworkImage(imageUrl: vendor.imageUrl!, fit: BoxFit.cover)
                            : Container(
                                color: VendorPalette.surfaceElevated,
                                child: const Icon(
                                  Icons.storefront_outlined,
                                  size: 32,
                                  color: VendorPalette.textMuted,
                                ),
                              ),
                      ),
                      // Literal top-left (not RTL start/end) — matches the
                      // reference's badge position and this codebase's other
                      // corner-badge precedent (MostOrderedCard's "+" badge).
                      if (isFreeDelivery)
                        const Positioned(top: 8, left: 8, child: _FreeDeliveryBadge()),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vendor.name,
                      style: textTheme.titleSmall
                          ?.copyWith(color: VendorPalette.textPrimary, fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (showRating) ...[
                      const SizedBox(height: 4),
                      vendor.ratingCount == 0
                          ? Text(
                              l10n.notRatedYetLabel,
                              style: textTheme.bodySmall?.copyWith(color: VendorPalette.textMuted),
                            )
                          : StarRatingDisplay(
                              rating: vendor.averageRating,
                              count: vendor.ratingCount,
                              size: 14,
                            ),
                    ],
                    const SizedBox(height: 8),
                    const _DashedDivider(),
                    const SizedBox(height: 8),
                    if (footerParts.isNotEmpty)
                      Row(
                        children: [
                          const Icon(
                            Icons.pedal_bike_outlined,
                            size: 16,
                            color: VendorPalette.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              footerParts.join('  ·  '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodySmall?.copyWith(color: VendorPalette.textSecondary),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FreeDeliveryBadge extends StatelessWidget {
  const _FreeDeliveryBadge();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: VendorPalette.primaryCyan, borderRadius: AppRadius.pill),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.sell_outlined, size: 12, color: VendorPalette.background),
          const SizedBox(width: 4),
          Text(
            l10n.freeDeliveryLabel,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: VendorPalette.background, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// Plain-widget dashed line (no `CustomPainter`) — a `LayoutBuilder` picks
/// how many fixed-width dash segments fit the available width, avoiding a
/// painter sized with an unconstrained `double.infinity` `Size`.
class _DashedDivider extends StatelessWidget {
  const _DashedDivider();

  static const double _dashWidth = 5;
  static const double _dashGap = 4;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = (constraints.maxWidth / (_dashWidth + _dashGap)).floor().clamp(0, 200);
        return SizedBox(
          height: 1,
          child: Row(
            children: [
              for (var i = 0; i < count; i++) ...[
                Container(width: _dashWidth, height: 1, color: VendorPalette.divider),
                if (i != count - 1) const SizedBox(width: _dashGap),
              ],
            ],
          ),
        );
      },
    );
  }
}
