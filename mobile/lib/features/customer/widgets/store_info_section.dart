import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n/enum_labels.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_network_image.dart';
import '../../../core/widgets/star_rating.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/city.dart';
import '../../../models/vendor.dart';

const _logoBorderWidth = 4.0;
const _logoInnerPadding = 14.0;
// Corner radius as a fraction of the logo card's side length — a "squircle"
// (rounded square, not a full circle) matching the reference storefront
// design, where the corners stay visibly rounded regardless of card size.
const _logoCornerRadiusFraction = 0.28;
// 58% of the logo sits above the hero/content boundary, 42% below — an
// intentional, uneven overlap (not a plain half-and-half split) so it reads
// as "hanging off the hero" rather than centered exactly on the seam.
const _logoOverlapAboveFraction = 0.58;

/// Vendor identity block below VendorMenuScreen's hero header — logo, name,
/// rating, open/closed status, delivery metadata, and a collapsible "more
/// info" section. Centered, dark-navy/cyan presentation per Phase 4A's
/// visual redesign — consumes `Theme.of(context)` for colors/type scale,
/// which the caller (`VendorMenuScreen`) has already scoped to
/// [VendorPalette] via `VendorPalette.themeFrom`, so this widget itself
/// stays theme-token-driven rather than hardcoding colors, same as before.
/// Owns its own expand/collapse state since nothing outside this widget
/// needs to observe it.
class StoreInfoSection extends StatefulWidget {
  const StoreInfoSection({
    required this.vendor,
    required this.currencyFormat,
    this.liveCities = const [],
    super.key,
  });

  final Vendor vendor;
  final NumberFormat currencyFormat;

  // Canonical live city list (see FirestoreService.watchCities() /
  // allCitiesProvider) — passed in by the caller rather than watched here,
  // since this widget is a plain StatefulWidget, not Riverpod-aware, same
  // reasoning as currencyFormat above. Defaults to empty (falls back to
  // cityLabel's own legacy ARB names) so existing/other callers, if any,
  // keep working unchanged.
  final List<CityOption> liveCities;

  @override
  State<StoreInfoSection> createState() => _StoreInfoSectionState();
}

class _StoreInfoSectionState extends State<StoreInfoSection> {
  bool _moreInfoExpanded = false;

  String _statusText(AppLocalizations l10n) {
    final vendor = widget.vendor;
    if (!vendor.isOpen) return l10n.storeClosedLabel;
    if (vendor.closeTime != null) return l10n.storeOpenUntilLabel(vendor.closeTime!);
    return l10n.storeOpenNowLabel;
  }

  @override
  Widget build(BuildContext context) {
    final vendor = widget.vendor;
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final statusColor = vendor.isOpen ? AppColors.success(colorScheme) : colorScheme.error;
    final hasFee = vendor.deliveryFee != null;
    final hasEta = vendor.etaMinMinutes != null && vendor.etaMaxMinutes != null;
    final hasMinimum = vendor.minimumOrderAmount != null;

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 112–140dp, scaled off the available width so it stays
          // proportionate from a small phone (iPhone SE) up to a large one
          // (Pro Max) — big and clearly legible, like the reference design,
          // while `ResponsiveCenter`'s 700dp cap keeps it from ballooning on
          // wide (web/desktop) windows.
          final logoDiameter = (constraints.maxWidth * 0.32).clamp(112.0, 140.0);
          final overlapAbove = logoDiameter * _logoOverlapAboveFraction;
          final overlapBelow = logoDiameter - overlapAbove;

          return Stack(
            // `Clip.none` is the actual fix for the logo being cut off: a
            // `Positioned` child poking above `top: 0` inside a `Stack`
            // paints in full by default, but only once nothing upstream
            // clips it — this guarantees that, rather than relying on a
            // `Transform.translate` shifting a normally-clipped box.
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              Padding(
                padding: EdgeInsets.only(top: overlapBelow + AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      vendor.name,
                      textAlign: TextAlign.center,
                      style: textTheme.headlineMedium
                          ?.copyWith(fontSize: 30, color: VendorPalette.textPrimary),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    vendor.ratingCount == 0
                        ? Text(
                            l10n.notRatedYetLabel,
                            textAlign: TextAlign.center,
                            style: textTheme.bodyMedium?.copyWith(color: VendorPalette.textSecondary),
                          )
                        : StarRatingDisplay(rating: vendor.averageRating, count: vendor.ratingCount),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          _statusText(l10n),
                          textAlign: TextAlign.center,
                          style: textTheme.bodyMedium
                              ?.copyWith(color: statusColor, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    if (hasFee || hasEta || hasMinimum) ...[
                      const SizedBox(height: AppSpacing.lg),
                      _DeliveryInfoPill(
                        vendor: vendor,
                        currencyFormat: widget.currencyFormat,
                        hasFee: hasFee,
                        hasEta: hasEta,
                        hasMinimum: hasMinimum,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      alignment: Alignment.topCenter,
                      child: !_moreInfoExpanded
                          ? const SizedBox(width: double.infinity)
                          : Padding(
                              padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.sm),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    vendor.description,
                                    textAlign: TextAlign.start,
                                    style: textTheme.bodyMedium
                                        ?.copyWith(color: VendorPalette.textSecondary),
                                  ),
                                  const SizedBox(height: AppSpacing.xs),
                                  Text(
                                    '${vendorCategoryLabel(context, vendor.category)} · ${cityLabel(context, vendor.city, widget.liveCities)}',
                                    textAlign: TextAlign.start,
                                    style: textTheme.bodyMedium
                                        ?.copyWith(color: VendorPalette.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                    ),
                    InkWell(
                      onTap: () => setState(() => _moreInfoExpanded = !_moreInfoExpanded),
                      borderRadius: AppRadius.small,
                      child: Padding(
                        padding: const EdgeInsetsDirectional.symmetric(vertical: AppSpacing.xs),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _moreInfoExpanded ? l10n.lessInfoLabel : l10n.moreInfoLabel,
                              textAlign: TextAlign.center,
                              style: textTheme.labelLarge?.copyWith(color: VendorPalette.primaryCyan),
                            ),
                            AnimatedRotation(
                              turns: _moreInfoExpanded ? 0.5 : 0,
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeOut,
                              child: Icon(Icons.expand_more, color: VendorPalette.primaryCyan),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: -overlapAbove,
                child: _VendorLogo(
                  logoUrl: vendor.logoUrl,
                  colorScheme: colorScheme,
                  diameter: logoDiameter,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Rounded-square ("squircle") vendor logo card overlapping the hero/content
/// boundary — a plain white backdrop (deliberately fixed, not `ColorScheme`:
/// an arbitrary uploaded logo — often with a transparent background or dark
/// text — needs one neutral, universally-safe backdrop regardless of the
/// screen's own dark theme, same reasoning as [StoreSearchBar]'s pill) with
/// a premium shadow lifting it off both the photo above and the page below.
/// `BoxFit.contain` (not `.cover`) and no `ClipRRect` around the image itself
/// so the whole logo is always visible letterboxed within the card instead
/// of a non-square source image having its edges cropped away.
///
/// Reads [logoUrl] only — never [Vendor.imageUrl] (the wide hero/cover
/// photo). Falling back to the cover photo here was the original bug: a
/// landscape storefront photo squeezed into a square card reads as
/// "cropped" no matter how it's fitted, because it was never designed as a
/// logo. A missing/null logo renders a neutral placeholder icon instead.
class _VendorLogo extends StatelessWidget {
  const _VendorLogo({required this.logoUrl, required this.colorScheme, required this.diameter});

  final String? logoUrl;
  final ColorScheme colorScheme;
  final double diameter;

  // Demo-only convention: a `logoUrl` that's a relative `assets/...` path
  // (rather than an `http(s)://` URL) refers to an image bundled with the
  // app itself, so it renders via `Image.asset` instead of going through
  // `AppNetworkImage`'s network fetch. Real vendor logos are always
  // uploaded to Firebase Storage and stored as a normal download URL — this
  // branch exists solely so the "Green Valley Grocers" demo vendor can ship
  // with a real logo image without needing network access.
  bool get _isBundledAsset => logoUrl != null && !logoUrl!.startsWith('http');

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(diameter * _logoCornerRadiusFraction);
    return Container(
      width: diameter,
      height: diameter,
      padding: const EdgeInsets.all(_logoBorderWidth),
      decoration: BoxDecoration(
        color: AppPalette.surface,
        borderRadius: radius,
        boxShadow: AppShadows.large(colorScheme),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(color: AppPalette.surface, borderRadius: radius),
        child: Padding(
          padding: const EdgeInsets.all(_logoInnerPadding),
          child: switch (logoUrl) {
            null => const Icon(Icons.storefront_outlined, color: AppPalette.textMuted),
            _ when _isBundledAsset => Image.asset(logoUrl!, fit: BoxFit.contain),
            _ => AppNetworkImage(imageUrl: logoUrl!, fit: BoxFit.contain),
          },
        ),
      ),
    );
  }
}

/// Single premium "delivery facts" pill/card grouping whichever of
/// ETA/fee/minimum-order actually exist on [Vendor] — real data only, never
/// a fabricated placeholder for a field the vendor hasn't set.
class _DeliveryInfoPill extends StatelessWidget {
  const _DeliveryInfoPill({
    required this.vendor,
    required this.currencyFormat,
    required this.hasFee,
    required this.hasEta,
    required this.hasMinimum,
  });

  final Vendor vendor;
  final NumberFormat currencyFormat;
  final bool hasFee;
  final bool hasEta;
  final bool hasMinimum;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final parts = [
      if (hasEta) l10n.etaMinutesRangeLabel(vendor.etaMinMinutes!, vendor.etaMaxMinutes!),
      if (hasFee)
        vendor.deliveryFee == 0
            ? l10n.freeDeliveryLabel
            : l10n.deliveryFeeValueLabel(currencyFormat.format(vendor.deliveryFee)),
      if (hasMinimum) l10n.minimumOrderLabel(currencyFormat.format(vendor.minimumOrderAmount)),
    ];

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: VendorPalette.surfaceContainer,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        children: [
          const Icon(Icons.pedal_bike_outlined, color: VendorPalette.primaryCyan, size: 22),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              parts.join('  ·  '),
              textAlign: TextAlign.start,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodyMedium?.copyWith(color: VendorPalette.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
