import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/discovery/menu_sections.dart';
import '../../../core/errors/error_messages.dart';
import '../../../core/providers/formatters_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/animated_async.dart';
import '../../../core/widgets/responsive_center.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/widgets/star_rating.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/city.dart';
import '../../../models/review.dart';
import '../../../models/vendor.dart';
import '../../../routing/page_transitions.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/cart_provider.dart';
import '../widgets/cart_add_flow.dart';
import '../widgets/floating_order_button.dart';
import '../widgets/menu_item_card.dart';
import '../widgets/most_ordered_section.dart';
import '../widgets/product_details_sheet.dart';
import '../widgets/store_header_action_button.dart';
import '../widgets/store_hero_background.dart';
import '../widgets/store_info_section.dart';
import '../widgets/store_promo_banner.dart';
import '../widgets/store_search_bar.dart';
import '../widgets/store_sticky_tabs.dart';
import 'cart_screen.dart';
import 'customer_home_screen.dart' show allCitiesProvider, firestoreServiceProvider;
import 'most_ordered_screen.dart';
import 'search_screen.dart';

final vendorMenuProvider =
    StreamProvider.autoDispose.family<List<MenuItem>, String>((ref, vendorId) {
  return ref.watch(firestoreServiceProvider).watchMenu(vendorId);
});

final vendorReviewsProvider =
    StreamProvider.autoDispose.family<List<Review>, String>((ref, vendorId) {
  return ref.watch(firestoreServiceProvider).watchVendorReviews(vendorId);
});

class VendorMenuScreen extends ConsumerStatefulWidget {
  const VendorMenuScreen({required this.vendor, this.heroImageUrl, super.key});

  final Vendor vendor;

  /// The specific product image the user tapped to get here (home feed,
  /// search, "View all") — takes priority over the vendor's own storefront
  /// photo as the hero background. Falls back to `vendor.imageUrl` when
  /// null (entry points not tied to a specific product).
  final String? heroImageUrl;

  @override
  ConsumerState<VendorMenuScreen> createState() => _VendorMenuScreenState();
}

class _VendorMenuScreenState extends ConsumerState<VendorMenuScreen> {
  final _scrollController = ScrollController();
  final List<GlobalKey> _sectionKeys = [];
  int _selectedTabIndex = 0;
  bool _isScrollingToSection = false;
  // Guards against stacking redundant post-frame callbacks when the
  // ScrollController's listener fires several times within one frame (e.g.
  // a fling generates a burst of position updates) — see _handleScroll.
  bool _scrollSpyScheduled = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  // Highlights whichever section's heading has scrolled up past the pinned
  // app bar + sticky tabs, without fighting a tap-triggered scroll already
  // in flight (see _isScrollingToSection in _scrollToSection).
  //
  // The actual measurement is deferred to a post-frame callback rather than
  // running inline here: ScrollController's listener fires synchronously as
  // soon as the scroll *offset* changes, which is before that frame's
  // layout/paint has run — so `RenderBox.localToGlobal` at this exact point
  // still reflects the *previous* frame's paint transform, not the new
  // scroll position. Reading it inline reliably returns a stale position
  // (confirmed live: every section reported its pre-scroll offset no matter
  // how far the user had actually scrolled), which silently freezes the
  // active tab. Waiting for the frame to finish is the standard fix.
  void _handleScroll() {
    if (_isScrollingToSection || _sectionKeys.isEmpty || _scrollSpyScheduled) return;
    _scrollSpyScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollSpyScheduled = false;
      if (!mounted || _isScrollingToSection || _sectionKeys.isEmpty) return;
      const threshold = 160.0;
      var nearestIndex = 0;
      for (var i = 0; i < _sectionKeys.length; i++) {
        final renderObject = _sectionKeys[i].currentContext?.findRenderObject();
        if (renderObject is! RenderBox || !renderObject.attached) continue;
        final top = renderObject.localToGlobal(Offset.zero).dy;
        if (top <= threshold) nearestIndex = i;
      }
      if (nearestIndex != _selectedTabIndex) {
        setState(() => _selectedTabIndex = nearestIndex);
      }
    });
  }

  Future<void> _scrollToSection(int index) async {
    setState(() {
      _selectedTabIndex = index;
      _isScrollingToSection = true;
    });
    final sectionContext = _sectionKeys[index].currentContext;
    if (sectionContext != null) {
      await Scrollable.ensureVisible(
        sectionContext,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
    if (mounted) setState(() => _isScrollingToSection = false);
  }

  Future<void> _addToCart(BuildContext context, WidgetRef ref, MenuItem item) {
    return addToCartWithVendorSwitchConfirm(
      context,
      ref,
      vendorId: widget.vendor.id,
      vendorName: widget.vendor.name,
      item: item,
    );
  }

  @override
  Widget build(BuildContext context) {
    final vendor = widget.vendor;
    final menuAsync = ref.watch(vendorMenuProvider(vendor.id));
    final cart = ref.watch(cartProvider);
    final l10n = AppLocalizations.of(context)!;
    final currencyFormat = ref.watch(currencyFormatProvider);
    final liveCities = ref.watch(allCitiesProvider).valueOrNull ?? const <CityOption>[];
    final currentUser = ref.watch(currentAppUserProvider).valueOrNull;
    final isFavorite = currentUser?.favoriteVendorIds.contains(vendor.id) ?? false;
    final heroImage = widget.heroImageUrl ?? vendor.imageUrl;
    // Responsive within a fixed 300–380dp band rather than one constant, so
    // the hero reads proportionally on both a small phone (iPhone SE) and a
    // tall one (Pro Max) instead of eating too much/little of either.
    final heroHeight = (MediaQuery.sizeOf(context).height * 0.40).clamp(300.0, 380.0);
    // Phase 4A: this screen gets its own fixed dark-navy/cyan palette
    // regardless of the app's own light/dark theme setting (see
    // `VendorPalette` for why) — scoped to `body` only, so `bottomNavigationBar`
    // (the cart bar) keeps using the app's real ambient theme untouched.
    final vendorTheme = VendorPalette.themeFrom(Theme.of(context));
    final colorScheme = vendorTheme.colorScheme;

    return Scaffold(
      backgroundColor: VendorPalette.background,
      // Stack (not `Scaffold.bottomNavigationBar`) so the order button
      // floats over the scrollable content with its own margin instead of
      // docking flush to the bottom edge and reserving full-width layout
      // space — see FloatingOrderButton.
      body: Stack(
        children: [
          Theme(
        data: vendorTheme,
        child: ResponsiveCenter(
          child: menuAsync.animatedWhen(
          data: (items) {
            final available = items.where((item) => item.available).toList();
            final sections = buildMenuSections(
              available,
              mostOrderedTitle: l10n.mostOrderedSectionTitle,
              defaultSectionTitle: l10n.defaultMenuSectionTitle,
            );
            // Uncapped, unlike the carousel's own (limit: 5) section items —
            // MostOrderedScreen's grid must show every qualifying item, not
            // just the handful the carousel has room for.
            final allMostOrdered = mostOrderedItems(available, limit: available.length);
            while (_sectionKeys.length < sections.length) {
              _sectionKeys.add(GlobalKey());
            }
            if (_sectionKeys.length > sections.length) {
              _sectionKeys.removeRange(sections.length, _sectionKeys.length);
            }
            if (_selectedTabIndex >= sections.length) {
              _selectedTabIndex = sections.isEmpty ? 0 : sections.length - 1;
            }
            final reviewsAsync = ref.watch(vendorReviewsProvider(vendor.id));

            return CustomScrollView(
              controller: _scrollController,
              // Bouncing (not the platform-default clamping) physics is what
              // lets the user overscroll past the top at all — required for
              // SliverAppBar's `stretch` to ever trigger.
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              // _handleScroll's scroll-spy reads each section heading's
              // GlobalKey.currentContext — which Flutter nulls out once that
              // RenderObject scrolls further than cacheExtent from the
              // viewport (default 250dp), silently freezing the active tab
              // on whichever section was last measured. A single vendor's
              // menu is bounded (unlike an infinite feed), so a generous
              // fixed cacheExtent is a safe, minimal trade-off that keeps
              // every section's heading mounted for the scroll-spy to read.
              cacheExtent: 5000,
              slivers: [
                SliverAppBar(
                  pinned: true,
                  stretch: true,
                  stretchTriggerOffset: 100,
                  expandedHeight: heroHeight,
                  backgroundColor: VendorPalette.background,
                  foregroundColor: VendorPalette.textPrimary,
                  // Explicit leading/title/actions (not the default
                  // auto-leading + a plain actions row) so back sits at the
                  // trailing "right" edge, the search pill is genuinely
                  // centered, and the heart sits at the opposite edge —
                  // AppBar mirrors leading/actions for RTL automatically, so
                  // this also does the right thing without any manual
                  // Directionality override.
                  leading: StoreHeaderActionButton(
                    icon: Icons.arrow_back,
                    tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  centerTitle: true,
                  title: StoreSearchBar(
                    onTap: () => Navigator.of(context).push(fadeSlideRoute(const SearchScreen())),
                  ),
                  actions: [
                    StoreHeaderActionButton(
                      icon: isFavorite ? Icons.favorite : Icons.favorite_border,
                      color: isFavorite ? colorScheme.error : VendorPalette.textPrimary,
                      tooltip: isFavorite ? l10n.unfavoriteTooltip : l10n.favoriteTooltip,
                      onPressed: currentUser == null
                          ? null
                          : () => ref
                              .read(firestoreServiceProvider)
                              .toggleFavoriteVendor(currentUser.id, vendor.id, !isFavorite),
                    ),
                  ],
                  flexibleSpace: FlexibleSpaceBar(
                    stretchModes: const [StretchMode.zoomBackground],
                    background: StoreHeroBackground(imageUrl: heroImage),
                  ),
                ),
                SliverToBoxAdapter(
                  child: StoreInfoSection(
                    vendor: vendor,
                    currencyFormat: currencyFormat,
                    liveCities: liveCities,
                  ),
                ),
                const SliverToBoxAdapter(child: StorePromoBanner()),
                if (sections.isNotEmpty)
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: StoreStickyTabsDelegate(
                      sections: sections,
                      selectedIndex: _selectedTabIndex,
                      onTap: _scrollToSection,
                    ),
                  ),
                if (available.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      child: Text(l10n.vendorMenuEmptyMessage),
                    ),
                  )
                else
                  for (var s = 0; s < sections.length; s++)
                    if (sections[s].isMostOrdered)
                      // Requirement: "Most ordered" reads as a horizontal
                      // carousel, not another vertical list — every other
                      // section below keeps the plain vertical MenuItemCard
                      // list. The KeyedSubtree (not a bare Padding, unlike
                      // the vertical branch) still gives scroll-spy a stable
                      // render object to measure: its top is the section
                      // heading's top either way, since the heading is
                      // MostOrderedSection's first child.
                      SliverToBoxAdapter(
                        child: KeyedSubtree(
                          key: _sectionKeys[s],
                          child: MostOrderedSection(
                            title: sections[s].title,
                            items: sections[s].items,
                            currencyFormat: currencyFormat,
                            onAddToCart: (item) => _addToCart(context, ref, item),
                            onTapItem: (item) => showProductDetailsSheet(
                              context,
                              vendorId: vendor.id,
                              vendorName: vendor.name,
                              item: item,
                            ),
                            onViewAll: () => Navigator.of(context).push(fadeSlideRoute(
                              MostOrderedScreen(
                                vendorId: vendor.id,
                                vendorName: vendor.name,
                                title: sections[s].title,
                                items: allMostOrdered,
                                currencyFormat: currencyFormat,
                              ),
                            )),
                          ),
                        ),
                      )
                    else
                      SliverMainAxisGroup(
                        slivers: [
                          SliverToBoxAdapter(
                            child: Padding(
                              key: _sectionKeys[s],
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                              child: Text(
                                sections[s].title,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                          ),
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                            sliver: SliverList.builder(
                              // Interleaved dividers (2*n-1 items, odd index =
                              // divider) rather than a `.separated` helper —
                              // `SliverList` has none — so the hairline
                              // between rows is drawn once here instead of
                              // inside every `MenuItemCard`, keeping the line
                              // consistently spanning the list's own content
                              // width.
                              itemCount: sections[s].items.length * 2 - 1,
                              itemBuilder: (context, index) {
                                if (index.isOdd) {
                                  return const Divider(height: 1, color: VendorPalette.divider);
                                }
                                final item = sections[s].items[index ~/ 2];
                                return MenuItemCard(
                                  item: item,
                                  currencyFormat: currencyFormat,
                                  onTap: () => showProductDetailsSheet(
                                    context,
                                    vendorId: vendor.id,
                                    vendorName: vendor.name,
                                    item: item,
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Divider(),
                        Text(l10n.reviewsTitle, style: Theme.of(context).textTheme.titleMedium),
                        reviewsAsync.animatedWhen(
                          data: (reviews) => reviews.isEmpty
                              ? Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  child: Text(l10n.noReviewsMessage),
                                )
                              : Column(
                                  children: [
                                    for (final review in reviews)
                                      ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        title: StarRatingDisplay(
                                          rating: review.vendorRating.toDouble(),
                                          size: 14,
                                        ),
                                        subtitle:
                                            review.comment == null ? null : Text(review.comment!),
                                      ),
                                  ],
                                ),
                          loading: () => const SizedBox.shrink(),
                          error: (_, __) => const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
          loading: () => const ListSkeletonLoader(),
          error: (error, _) => Center(child: Text(localizedErrorMessage(context, error))),
        ),
        ),
          ),
          // `MediaQuery.paddingOf(context).bottom` (not a wrapping
          // `SafeArea`) so the button sits just above the home-indicator
          // inset with its own extra margin on top, matching the reference's
          // visible gap beneath the button rather than butting against it.
          Positioned(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            bottom: MediaQuery.paddingOf(context).bottom + AppSpacing.lg,
            child: FloatingOrderButton(
              itemCount: cart.itemCount,
              totalLabel: currencyFormat.format(cart.total),
              onTap: () => Navigator.of(context).push(fadeSlideRoute(const CartScreen())),
            ),
          ),
        ],
      ),
    );
  }
}
