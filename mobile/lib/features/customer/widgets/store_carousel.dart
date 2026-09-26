import 'package:flutter/material.dart';
// intl exports its own conflicting `TextDirection` — hide it so
// `Directionality.of(context) != TextDirection.rtl` below resolves to
// Flutter's (dart:ui's) TextDirection instead (same fix already applied in
// most_ordered_section.dart for the identical conflict).
import 'package:intl/intl.dart' hide TextDirection;

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/vendor.dart';
import 'store_card.dart';
import '../../../core/theme/app_shadows.dart';

/// One row of CustomerHomeScreen's dynamic, extensible, **store-first**
/// feed — see `core/discovery/vendor_carousels.dart` for how [vendors] is
/// chosen (a real vendor-level rule: "fastest," "free delivery," a specific
/// category, ...). Deliberately just data (no widget/BuildContext
/// dependency), same shape as the redesign this replaces, so the screen can
/// build an ordered `List<CarouselSection>`, drop any with an empty
/// [vendors] list, and render the rest with a single `SliverList.builder`.
class CarouselSection {
  const CarouselSection({required this.title, required this.vendors});

  final String title;
  final List<Vendor> vendors;
}

/// Renders one [CarouselSection]: a title + "مشاهدة الكل" pill header, then
/// a horizontal row of [StoreCard]s — matching the reference's store-card
/// carousels ("أسرع توصيل" etc.) rather than the small individual-product
/// tiles the previous product-first feed used.
///
/// A `StatefulWidget` (rather than the previous stateless version) solely so
/// each carousel can own its own [ScrollController] — needed to animate the
/// list from the trailing nav arrow (see [_CarouselNavArrow]) instead of
/// just relying on the user's own swipe.
class StoreCarousel extends StatefulWidget {
  const StoreCarousel({
    required this.section,
    required this.currencyFormat,
    required this.onTapStore,
    required this.onViewAll,
    super.key,
  });

  final CarouselSection section;
  final NumberFormat currencyFormat;
  final ValueChanged<Vendor> onTapStore;
  final VoidCallback onViewAll;

  // Card width as a fraction of the section's available width — the same
  // tuned proportion `MostOrderedSection` already uses for "~2 cards with a
  // sliver of a third peeking" on a phone-sized viewport, reused here rather
  // than inventing a second arbitrary constant for the same visual target.
  static const double _cardWidthFraction = 0.426;
  static const double _cardWidthMin = 150;
  static const double _cardWidthMax = 220;

  @override
  State<StoreCarousel> createState() => _StoreCarouselState();
}

class _StoreCarouselState extends State<StoreCarousel> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // Advances by ~80% of the visible viewport — enough to feel like a real
  // "next" page rather than a nudge, while leaving a sliver of the previous
  // row in view for scroll continuity. Clamped to maxScrollExtent so tapping
  // near/at the end is a harmless no-op rather than overshooting.
  void _scrollForward(double viewportWidth) {
    if (!_scrollController.hasClients) return;
    final target = (_scrollController.offset + viewportWidth * 0.8)
        .clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.section.title,
                  textAlign: TextAlign.start,
                  style: textTheme.titleLarge
                      ?.copyWith(color: VendorPalette.textPrimary, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: AppSpacing.sm),
                // "end" under RTL is the physical left, matching the
                // reference's pill position beneath a right-aligned title —
                // falls out of normal RTL semantics, no literal-position
                // override needed here (unlike the header's bell/account).
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: _ViewAllPill(onTap: widget.onViewAll),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth = (constraints.maxWidth * StoreCarousel._cardWidthFraction)
                  .clamp(StoreCarousel._cardWidthMin, StoreCarousel._cardWidthMax);
              final cardHeight = cardWidth / storeCardImageAspectRatio + storeCardBodyHeight;

              return SizedBox(
                height: cardHeight,
                child: Stack(
                  children: [
                    ListView.separated(
                      controller: _scrollController,
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                      itemCount: widget.section.vendors.length,
                      separatorBuilder: (context, index) => const SizedBox(width: AppSpacing.sm),
                      itemBuilder: (context, index) {
                        final vendor = widget.section.vendors[index];
                        return SizedBox(
                          width: cardWidth,
                          child: StoreCard(
                            vendor: vendor,
                            currencyFormat: widget.currencyFormat,
                            onTap: () => widget.onTapStore(vendor),
                            // CustomerHomeScreen's own cards don't show the
                            // rating row — View all/Favorites still do (see
                            // StoreCard.showRating's doc).
                            showRating: false,
                          ),
                        );
                      },
                    ),
                    // Wolt-style "next" affordance floating at the
                    // carousel's trailing edge — physical left under RTL.
                    // A Stack/Positioned overlay only, never a list item, so
                    // it can never affect the ListView's own item sizing or
                    // spacing; it only calls animateTo on the existing
                    // scroll position — no navigation, no product/Firestore
                    // change. Always shown, same "don't hide just because
                    // content currently fits" reasoning as
                    // MostOrderedSection's own end-of-carousel arrow.
                    PositionedDirectional(
                      end: AppSpacing.xs,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: _CarouselNavArrow(
                          onTap: () => _scrollForward(constraints.maxWidth),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ViewAllPill extends StatelessWidget {
  const _ViewAllPill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Material(
      color: VendorPalette.surfaceContainer,
      borderRadius: AppRadius.pill,
      child: InkWell(
        borderRadius: AppRadius.pill,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
          child: Text(
            l10n.viewAllButtonLabel,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: VendorPalette.primaryCyan, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

/// Small floating circular button at a [StoreCarousel]'s trailing edge —
/// same translucent-circle treatment as [StoreHeaderActionButton] (this
/// design system's existing "icon floating over content" language), just
/// smaller/more subtle to match a carousel-chrome role rather than a
/// hero-image action ("Keep the arrow subtle and clean, similar to Wolt").
class _CarouselNavArrow extends StatelessWidget {
  const _CarouselNavArrow({required this.onTap});

  final VoidCallback onTap;

  static const double _diameter = 32;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: VendorPalette.surfaceElevated.withValues(alpha: 0.85),
      shape: const CircleBorder(),
      elevation: 2,
      shadowColor: AppShadows.floatingShadowColor,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: const SizedBox(
          width: _diameter,
          height: _diameter,
          child: Center(child: _DirectionalArrowIcon()),
        ),
      ),
    );
  }
}

/// Same RTL handling as the app's other end-of-carousel arrow
/// (`MostOrderedSection`'s `_ViewAllArrow`, in `most_ordered_section.dart`)
/// — `arrow_forward_ios_rounded` has no built-in RTL auto-mirroring, so this
/// flips by hand; under this (RTL) app it renders unflipped, i.e. "‹",
/// pointing toward the direction more content is revealed.
class _DirectionalArrowIcon extends StatelessWidget {
  const _DirectionalArrowIcon();

  @override
  Widget build(BuildContext context) {
    return Transform.flip(
      flipX: Directionality.of(context) != TextDirection.rtl,
      child: const Icon(
        Icons.arrow_forward_ios_rounded,
        color: VendorPalette.primaryCyan,
        size: 14,
      ),
    );
  }
}
