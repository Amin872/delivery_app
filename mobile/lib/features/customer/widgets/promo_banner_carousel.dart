import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/promotion.dart';
import '../../../models/vendor.dart';
import '../../../routing/page_transitions.dart';
import '../screens/customer_home_screen.dart' show firestoreServiceProvider, openVendorsProvider;
import '../screens/vendor_menu_screen.dart';

final activePromotionsProvider = StreamProvider<List<Promotion>>((ref) {
  return ref.watch(firestoreServiceProvider).watchActivePromotions();
});

/// Admin-managed promotional carousel atop [CustomerHomeScreen]. Real
/// content from `promotions/{promotionId}` (enabled, ordered by `order`) —
/// see AdminPromotionsScreen for the write side — when at least one active
/// promotion exists; otherwise a static [_PromoBannerEmptyState] fills the
/// same slot so this section is always present at the same location,
/// whether that's because there's genuinely nothing enabled yet, the stream
/// is still loading, or it errored (e.g. rules not yet deployed) — none of
/// those are the "no offers" case worth losing the section over, and none
/// of them should ever surface fabricated promotional content.
class PromoBannerCarousel extends ConsumerWidget {
  const PromoBannerCarousel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final promotions = ref.watch(activePromotionsProvider).valueOrNull;
    if (promotions != null && promotions.isNotEmpty) {
      return _PromoBannerContent(promotions: promotions);
    }
    return const _PromoBannerEmptyState();
  }
}

/// Default card shown in [PromoBannerCarousel]'s slot when there are no
/// active promotions to display — same footprint (150 tall, same
/// horizontal/vertical padding, 24-radius rounded corners) as a single real
/// promotion card, built only from [VendorPalette] tokens, no new colors.
class _PromoBannerEmptyState extends StatelessWidget {
  const _PromoBannerEmptyState();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        height: 150,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [VendorPalette.surfaceContainer, VendorPalette.surfaceElevated],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: VendorPalette.divider),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -10,
              bottom: -10,
              child: Icon(
                Icons.campaign_outlined,
                size: 96,
                color: VendorPalette.primaryCyan.withValues(alpha: 0.12),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.local_offer_outlined, color: VendorPalette.primaryCyan, size: 22),
                  const SizedBox(height: 10),
                  Text(
                    l10n.promotionsEmptyStateTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: VendorPalette.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.promotionsEmptyStateSubtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: VendorPalette.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PromoBannerContent extends ConsumerStatefulWidget {
  const _PromoBannerContent({required this.promotions});

  final List<Promotion> promotions;

  @override
  ConsumerState<_PromoBannerContent> createState() => _PromoBannerContentState();
}

class _PromoBannerContentState extends ConsumerState<_PromoBannerContent> {
  final _controller = PageController();
  int _page = 0;
  Timer? _autoplayTimer;

  static const _autoplayInterval = Duration(seconds: 6);

  @override
  void initState() {
    super.initState();
    _restartAutoplay();
  }

  @override
  void didUpdateWidget(covariant _PromoBannerContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The live stream can add/remove/reorder promotions under this widget —
    // clamp the current page and restart autoplay whenever the count
    // crosses the "more than one page" threshold (or just changes size).
    if (oldWidget.promotions.length != widget.promotions.length) {
      if (_page >= widget.promotions.length) _page = 0;
      _restartAutoplay();
    }
  }

  // Single-page carousels get no timer at all — nothing to advance to, and
  // no point holding a resource that will never fire.
  void _restartAutoplay() {
    _autoplayTimer?.cancel();
    if (widget.promotions.length <= 1) return;
    _autoplayTimer = Timer.periodic(_autoplayInterval, (_) {
      if (!_controller.hasClients) return;
      final next = (_page + 1) % widget.promotions.length;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _autoplayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  // First-cut CTA scope: ctaAction is a vendor id, resolved against the
  // already-loaded open-vendors list and opened via the existing
  // VendorMenuScreen route — no new navigation/deep-link architecture. A
  // vendor id that doesn't resolve (typo, closed/removed vendor) is a safe
  // no-op rather than a crash or a dead-end screen.
  void _handleCta(Promotion promotion, List<Vendor> vendors) {
    final vendorId = promotion.ctaAction;
    if (vendorId == null) return;
    for (final vendor in vendors) {
      if (vendor.id == vendorId) {
        Navigator.of(context).push(fadeSlideRoute(VendorMenuScreen(vendor: vendor)));
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final promotions = widget.promotions;
    final vendors = ref.watch(openVendorsProvider).valueOrNull ?? const <Vendor>[];

    return Column(
      children: [
        SizedBox(
          height: 150,
          child: PageView.builder(
            controller: _controller,
            itemCount: promotions.length,
            onPageChanged: (page) => setState(() => _page = page),
            itemBuilder: (context, index) {
              final promotion = promotions[index];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: _PromotionCard(
                  promotion: promotion,
                  onCtaTap: () => _handleCta(promotion, vendors),
                ),
              );
            },
          ),
        ),
        // Only meaningful with more than one page — matches this widget's
        // Home-carousel sibling, which likewise skips chrome that has
        // nothing to control (see StoreCarousel's always-shown arrow vs.
        // this deliberately-conditional row: here, unlike that arrow, a
        // single promotion truly has no "other page" to reach).
        if (promotions.length > 1) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < promotions.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _page ? 20 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _page ? VendorPalette.primaryCyan : VendorPalette.textMuted,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _PromotionCard extends StatelessWidget {
  const _PromotionCard({required this.promotion, required this.onCtaTap});

  final Promotion promotion;
  final VoidCallback onCtaTap;

  @override
  Widget build(BuildContext context) {
    final hasCta = promotion.ctaLabel != null && promotion.ctaAction != null;
    final hasText = promotion.title != null || promotion.description != null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: ColoredBox(
        color: VendorPalette.surfaceContainer,
        child: Stack(
          fit: StackFit.expand,
          children: [
            promotion.mediaType == PromotionMediaType.video
                ? _PromotionVideo(url: promotion.mediaUrl)
                : CachedNetworkImage(
                    imageUrl: promotion.mediaUrl,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => const ColoredBox(color: VendorPalette.surfaceContainer),
                    errorWidget: (context, url, error) => const ColoredBox(
                      color: VendorPalette.surfaceContainer,
                      child: Icon(Icons.image_not_supported_outlined, color: VendorPalette.textMuted),
                    ),
                  ),
            // Scrim so title/description/CTA stay legible over arbitrary
            // uploaded media — built from the palette's own background
            // color, not a new invented tone.
            if (hasText || hasCta)
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      VendorPalette.background.withValues(alpha: 0.85),
                    ],
                    stops: const [0.4, 1.0],
                  ),
                ),
              ),
            if (hasText || hasCta)
              Positioned(
                left: 20,
                right: 20,
                bottom: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (promotion.title != null)
                      Text(
                        promotion.title!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: VendorPalette.textPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    if (promotion.description != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        promotion.description!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: VendorPalette.textSecondary),
                      ),
                    ],
                    if (hasCta) ...[
                      const SizedBox(height: 8),
                      Material(
                        color: VendorPalette.primaryCyan,
                        borderRadius: AppRadius.extraLarge,
                        child: InkWell(
                          borderRadius: AppRadius.extraLarge,
                          onTap: onCtaTap,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Text(
                              promotion.ctaLabel!,
                              style: const TextStyle(
                                color: VendorPalette.background,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Muted, looping, autoplaying video for a video-type [Promotion]. Failure
/// at any point (bad URL, unsupported codec, network error) falls back to a
/// neutral placeholder instead of throwing — this carousel must never crash
/// because one uploaded clip is broken.
class _PromotionVideo extends StatefulWidget {
  const _PromotionVideo({required this.url});

  final String url;

  @override
  State<_PromotionVideo> createState() => _PromotionVideoState();
}

class _PromotionVideoState extends State<_PromotionVideo> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller = controller;
    try {
      await controller.initialize();
      // Muted by default, no autoplay audio — required regardless of the
      // uploaded clip's own audio track.
      await controller.setVolume(0);
      await controller.setLooping(true);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {});
      await controller.play();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_failed || controller == null || !controller.value.isInitialized) {
      return const ColoredBox(
        color: VendorPalette.surfaceContainer,
        child: Center(
          child: Icon(Icons.videocam_off_outlined, color: VendorPalette.textMuted),
        ),
      );
    }
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: controller.value.size.width,
        height: controller.value.size.height,
        child: VideoPlayer(controller),
      ),
    );
  }
}
