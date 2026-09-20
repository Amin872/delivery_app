import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/formatters_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/responsive_center.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/vendor.dart';
import '../../../routing/page_transitions.dart';
import '../widgets/product_card.dart';
import 'customer_home_screen.dart' show openVendorsProvider, allMenuItemsProvider;
import 'vendor_menu_screen.dart';

/// Reached via the floating search action button on CustomerHomeScreen —
/// the only search entry point in the app (see the redesign plan's point on
/// the bottom-right floating action button). Repurposes the previous
/// session's product feed (`allMenuItemsProvider`/`ProductCard`), which no
/// longer renders directly on the home screen, into real client-side search
/// over both vendor names and product names — no fabricated results, just a
/// substring filter over data the app already fetches.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final vendorsAsync = ref.watch(openVendorsProvider);
    final menuItemsAsync = ref.watch(allMenuItemsProvider);
    final currencyFormat = ref.watch(currencyFormatProvider);

    final vendors = vendorsAsync.valueOrNull ?? const <Vendor>[];
    final menuItems = menuItemsAsync.valueOrNull ?? const <MenuItem>[];
    final vendorById = {for (final v in vendors) v.id: v};

    final query = _query.trim().toLowerCase();
    final matchingVendors = query.isEmpty
        ? const <Vendor>[]
        : vendors.where((v) => v.name.toLowerCase().contains(query)).toList();
    final matchingProducts = query.isEmpty
        ? const <MenuItem>[]
        : menuItems
            .where((item) => item.available && vendorById.containsKey(item.vendorId))
            .where((item) => item.name.toLowerCase().contains(query))
            .toList();
    final hasResults = matchingVendors.isNotEmpty || matchingProducts.isNotEmpty;
    final vendorTheme = VendorPalette.themeFrom(Theme.of(context));
    final textTheme = vendorTheme.textTheme;

    return Theme(
      data: vendorTheme,
      child: Scaffold(
        backgroundColor: VendorPalette.background,
        appBar: AppBar(
          backgroundColor: VendorPalette.background,
          foregroundColor: VendorPalette.textPrimary,
          title: Text(l10n.searchScreenTitle),
        ),
        body: ResponsiveCenter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _controller,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: l10n.searchFieldHint,
                    prefixIcon: const Icon(Icons.search),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
                const SizedBox(height: 16),
                if (query.isNotEmpty && !hasResults)
                  Expanded(
                    child: Center(
                      child: Text(
                        l10n.noSearchResultsMessage,
                        style: const TextStyle(color: VendorPalette.textSecondary),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView(
                      children: [
                        if (matchingVendors.isNotEmpty) ...[
                          Text(l10n.searchStoresSectionLabel, style: textTheme.titleMedium),
                          const SizedBox(height: 8),
                          for (final vendor in matchingVendors)
                            Card(
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundImage:
                                      vendor.imageUrl != null ? NetworkImage(vendor.imageUrl!) : null,
                                  child: vendor.imageUrl == null
                                      ? const Icon(Icons.storefront_outlined)
                                      : null,
                                ),
                                title: Text(vendor.name),
                                onTap: () => Navigator.of(context)
                                    .push(fadeSlideRoute(VendorMenuScreen(vendor: vendor))),
                              ),
                            ),
                          const SizedBox(height: 16),
                        ],
                        if (matchingProducts.isNotEmpty) ...[
                          Text(l10n.searchProductsSectionLabel, style: textTheme.titleMedium),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              for (final item in matchingProducts)
                                ProductCard(
                                  item: item,
                                  vendorName: vendorById[item.vendorId]!.name,
                                  currencyFormat: currencyFormat,
                                  onTap: () => Navigator.of(context).push(fadeSlideRoute(
                                    VendorMenuScreen(
                                      vendor: vendorById[item.vendorId]!,
                                      heroImageUrl: item.imageUrl,
                                    ),
                                  )),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
