import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/discovery/vendor_carousels.dart';
import '../../../core/l10n/enum_labels.dart';
import '../../../core/providers/formatters_provider.dart';
import '../../../core/providers/preferences_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/responsive_center.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/city.dart';
import '../../../models/governorate.dart';
import '../../../models/neighborhood.dart';
import '../../../models/vendor.dart';
import '../../../routing/page_transitions.dart';
import '../../../services/firestore_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../notifications/screens/notifications_screen.dart';
import '../providers/cart_provider.dart';
import '../widgets/category_section.dart';
import '../widgets/customer_home_header.dart';
import '../widgets/home_floating_controls.dart';
import '../widgets/promo_banner_carousel.dart';
import '../widgets/store_carousel.dart';
import 'account_screen.dart';
import 'cart_screen.dart';
import 'search_screen.dart';
import 'store_list_screen.dart';
import 'vendor_menu_screen.dart';
import '../../../core/widgets/state_views.dart';

final firestoreServiceProvider =
    Provider<FirestoreService>((ref) => FirestoreService());

final openVendorsProvider = StreamProvider<List<Vendor>>((ref) {
  return ref.watch(firestoreServiceProvider).watchOpenVendors();
});

// Kept here (rather than moved) because `SearchScreen` imports it from this
// file for its own product-name search — the redesigned home feed below is
// store-first and no longer watches this stream itself, but the provider
// declaration is a shared dependency other screens still rely on.
final allMenuItemsProvider = StreamProvider<List<MenuItem>>((ref) {
  return ref.watch(firestoreServiceProvider).watchAllMenuItems();
});

// Single source for the canonical city list (see the Locations/City
// migration plan) — every city picker/dropdown across the app (Home,
// Personal Info, Vendor Dashboard, Admin Vendors) watches this same
// provider via `show allCitiesProvider` rather than each starting its own
// `watchCities()` stream, so there's only ever one live city-data source.
final allCitiesProvider = StreamProvider<List<CityOption>>((ref) {
  return ref.watch(firestoreServiceProvider).watchCities();
});

// Canonical governorate/neighbourhood lists (Phase 4 Location & Address
// Architecture) — same single-shared-provider reasoning as
// allCitiesProvider above. Consumed by LocationPickerScreen/
// EditAddressScreen's reverse-geocode matching (see
// core/location/location_matcher.dart's matchNeighborhoodLocation) and by
// AdminLocationsScreen's Governorates/Neighborhoods tabs — one live stream
// per collection, not one per screen.
final allGovernoratesProvider = StreamProvider<List<GovernorateOption>>((ref) {
  return ref.watch(firestoreServiceProvider).watchGovernorates();
});

final allNeighborhoodsProvider = StreamProvider<List<NeighborhoodOption>>((ref) {
  return ref.watch(firestoreServiceProvider).watchNeighborhoods();
});

class CustomerHomeScreen extends ConsumerStatefulWidget {
  const CustomerHomeScreen({super.key});

  @override
  ConsumerState<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends ConsumerState<CustomerHomeScreen> {
  // Restaurants by default — the home feed is primarily a restaurant feed;
  // every other vertical is reached by picking a different category. There
  // is no "All" state anymore (see `category_section.dart`'s `HomeCategoryId`),
  // so this is never null.
  HomeCategoryId _selectedCategory = HomeCategoryId.restaurants;

  // Owned here (not by CategoryCollapsingHeaderDelegate, which is a cheap
  // descriptor recreated on every rebuild) so horizontal scroll position
  // survives category-selection rebuilds. Kept loosely in sync with each
  // other below so switching between the large-card and compact-pill
  // layouts roughly preserves the user's place in the category list.
  final _categoryBigScrollController = ScrollController();
  final _categoryPillScrollController = ScrollController();
  bool _syncingCategoryScroll = false;

  @override
  void initState() {
    super.initState();
    _categoryBigScrollController.addListener(
      () => _syncCategoryScroll(_categoryBigScrollController, _categoryPillScrollController),
    );
    _categoryPillScrollController.addListener(
      () => _syncCategoryScroll(_categoryPillScrollController, _categoryBigScrollController),
    );
  }

  @override
  void dispose() {
    _categoryBigScrollController.dispose();
    _categoryPillScrollController.dispose();
    super.dispose();
  }

  void _syncCategoryScroll(ScrollController from, ScrollController to) {
    if (_syncingCategoryScroll) return;
    if (!from.hasClients || !to.hasClients) return;
    final fromMax = from.position.maxScrollExtent;
    final toMax = to.position.maxScrollExtent;
    if (fromMax <= 0 || toMax <= 0) return;
    final fraction = (from.offset / fromMax).clamp(0.0, 1.0);
    _syncingCategoryScroll = true;
    to.jumpTo(fraction * toMax);
    _syncingCategoryScroll = false;
  }

  Future<void> _openCityPicker(String current) {
    final l10n = AppLocalizations.of(context)!;
    // Enabled, order-sorted live cities — falling back to the five legacy
    // ids (see models/city.dart) if the live collection is empty/hasn't
    // loaded, so the picker is never left with nothing to show.
    final liveCities = ref.read(allCitiesProvider).valueOrNull ?? const <CityOption>[];
    final visible = visibleCities(liveCities);
    final cityIds = visible.isNotEmpty ? visible.map((c) => c.id).toList() : legacyCityIds;
    return showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(l10n.selectCityTitle, style: Theme.of(sheetContext).textTheme.titleMedium),
            ),
            for (final cityId in cityIds)
              ListTile(
                title: Text(cityLabel(sheetContext, cityId, liveCities)),
                trailing: cityId == current
                    ? Icon(Icons.check, color: Theme.of(sheetContext).colorScheme.primary)
                    : null,
                onTap: () {
                  ref.read(selectedCityProvider.notifier).setCity(cityId);
                  Navigator.of(sheetContext).pop();
                },
              ),
          ],
        ),
      ),
    );
  }

  void _openStoreVendor(Vendor vendor) {
    Navigator.of(context).push(fadeSlideRoute(VendorMenuScreen(vendor: vendor)));
  }

  void _openStoreList(String title, List<Vendor> vendors) {
    Navigator.of(context).push(fadeSlideRoute(StoreListScreen(title: title, vendors: vendors)));
  }

  /// Builds the ordered, dynamic list of carousel sections: curated ones
  /// first, then one plain section per remaining category (pharmacy is
  /// covered by Selfcare already, so it's skipped here to avoid a
  /// duplicate row). Each section is a real vendor-level rule from
  /// `core/discovery/vendor_carousels.dart` — store-first, matching the
  /// redesigned `StoreCarousel`/`StoreCard`. Empty sections are dropped
  /// before returning — adding a new section later is a one-line addition
  /// to this list.
  List<CarouselSection> _buildSections(BuildContext context, List<Vendor> pool) {
    final l10n = AppLocalizations.of(context)!;

    final sections = [
      CarouselSection(
        title: l10n.fastestDeliveryCarouselTitle,
        vendors: fastestDeliveryVendors(pool),
      ),
      CarouselSection(
        title: l10n.dealsNearYouCarouselTitle,
        vendors: dealVendors(pool),
      ),
      CarouselSection(
        title: l10n.selfcareCarouselTitle,
        vendors: selfcareVendors(pool),
      ),
      CarouselSection(
        title: l10n.popularNowCarouselTitle,
        vendors: popularVendors(pool),
      ),
      for (final category in VendorCategory.values)
        if (category != VendorCategory.pharmacy)
          CarouselSection(
            title: vendorCategoryLabel(context, category),
            vendors: vendorsInCategory(pool, category),
          ),
    ];

    return sections.where((s) => s.vendors.isNotEmpty).toList();
  }

  @override
  Widget build(BuildContext context) {
    final vendorsAsync = ref.watch(openVendorsProvider);
    final l10n = AppLocalizations.of(context)!;
    final customerId = ref.watch(currentAppUserProvider).valueOrNull?.id;
    final currencyFormat = ref.watch(currencyFormatProvider);
    final selectedCity = ref.watch(selectedCityProvider);
    final liveCities = ref.watch(allCitiesProvider).valueOrNull ?? const <CityOption>[];
    final cart = ref.watch(cartProvider);
    // Phase: home-page redesign — this screen now carries the same fixed
    // dark-navy/cyan palette as VendorMenuScreen/MostOrderedScreen instead
    // of the app's ambient light/dark theme, per the reference design.
    final vendorTheme = VendorPalette.themeFrom(Theme.of(context));

    return Theme(
      data: vendorTheme,
      child: Scaffold(
        backgroundColor: VendorPalette.background,
        body: Stack(
          children: [
            Column(
              children: [
                CustomerHomeHeader(
                  locationLabel: cityLabel(context, selectedCity, liveCities),
                  onLocationTap: () => _openCityPicker(selectedCity),
                  onNotificationsTap: () =>
                      Navigator.of(context).push(fadeSlideRoute(const NotificationsScreen())),
                  onAccountTap: customerId == null
                      ? null
                      : () => Navigator.of(context)
                          .push(fadeSlideRoute(AccountScreen(customerId: customerId))),
                ),
                Expanded(
                  child: ResponsiveCenter(
                    child: _buildBody(context, vendorsAsync, l10n, currencyFormat, selectedCity),
                  ),
                ),
              ],
            ),
            // Stack overlay (not Scaffold.floatingActionButton/
            // bottomNavigationBar) so both controls float with their own
            // margin above content, matching the reference and the same
            // pattern VendorMenuScreen's FloatingOrderButton established.
            // The bag button uses the Stack's own `Alignment.centerLeft` (a
            // literal physical position, not RTL start/end — same reasoning
            // as the header's bell/account buttons) and is otherwise
            // unpositioned; the search pill is wrapped in its own
            // `Align(Alignment.center)`, which overrides the Stack-level
            // alignment for just that child, so it centers horizontally in
            // the app's width independently of where the bag button sits —
            // the two are positioned completely independently of each
            // other. The pill's width (~35% of the screen width) and height
            // are unchanged from before.
            Positioned(
              left: AppSpacing.lg,
              right: AppSpacing.lg,
              bottom: MediaQuery.paddingOf(context).bottom + AppSpacing.lg,
              child: SizedBox(
                height: HomeFloatingSearchBar.height,
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    HomeFloatingBagButton(
                      itemCount: cart.itemCount,
                      onTap: () => Navigator.of(context).push(fadeSlideRoute(const CartScreen())),
                    ),
                    Align(
                      alignment: Alignment.center,
                      child: SizedBox(
                        width: MediaQuery.sizeOf(context).width * 0.35,
                        height: HomeFloatingSearchBar.height,
                        child: HomeFloatingSearchBar(
                          onTap: () =>
                              Navigator.of(context).push(fadeSlideRoute(const SearchScreen())),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AsyncValue<List<Vendor>> vendorsAsync,
    AppLocalizations l10n,
    NumberFormat currencyFormat,
    String selectedCity,
  ) {
    late final Widget child;
    late final String stateKey;
    if (vendorsAsync.isLoading) {
      child = const ListSkeletonLoader();
      stateKey = 'loading';
    } else if (vendorsAsync.hasError) {
      child = ErrorState(error: vendorsAsync.error!);
      stateKey = 'error';
    } else {
      final vendors = vendorsAsync.value!;
      // The selected entry's `vendorCategory` is null for verticals that
      // have no backing `VendorCategory` yet (see `HomeCategoryEntry`'s
      // doc) — the pool is honestly empty for those rather than falling
      // back to "show everything", since there's no more "All" state.
      final selectedVendorCategory =
          homeCategories.firstWhere((e) => e.id == _selectedCategory).vendorCategory;
      final pool = selectedVendorCategory == null
          ? const <Vendor>[]
          : vendors
              .where((v) => v.category == selectedVendorCategory && v.city == selectedCity)
              .toList();
      final sections = _buildSections(context, pool);

      child = CustomScrollView(
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: CategoryCollapsingHeaderDelegate(
              selected: _selectedCategory,
              onSelected: (category) => setState(() => _selectedCategory = category),
              bigController: _categoryBigScrollController,
              pillController: _categoryPillScrollController,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.sm)),
          const SliverToBoxAdapter(child: PromoBannerCarousel()),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.sm)),
          if (sections.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                child: Center(
                  child: Text(
                    l10n.noProductsInCategoryMessage,
                    style: const TextStyle(color: VendorPalette.textSecondary),
                  ),
                ),
              ),
            )
          else
            SliverList.builder(
              itemCount: sections.length,
              itemBuilder: (context, index) {
                final section = sections[index];
                return StoreCarousel(
                  section: section,
                  currencyFormat: currencyFormat,
                  onTapStore: _openStoreVendor,
                  onViewAll: () => _openStoreList(section.title, section.vendors),
                );
              },
            ),
          // Clears the floating search/bag row so the last carousel's cards
          // are never hidden behind it.
          SliverToBoxAdapter(
            child: SizedBox(
              height: HomeFloatingSearchBar.height + AppSpacing.lg * 2 +
                  MediaQuery.paddingOf(context).bottom,
            ),
          ),
        ],
      );
      stateKey = 'data';
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: KeyedSubtree(key: ValueKey(stateKey), child: child),
    );
  }
}
