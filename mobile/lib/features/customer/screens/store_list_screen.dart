import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/formatters_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/responsive_center.dart';
import '../../../models/vendor.dart';
import '../../../routing/page_transitions.dart';
import '../widgets/store_card.dart';
import 'vendor_menu_screen.dart';

/// "مشاهدة الكل" destination for one CustomerHomeScreen carousel section —
/// store-first, matching the redesigned main feed (see `StoreCarousel`).
/// [vendors] is passed in directly rather than re-queried: the home screen
/// already holds the same pool in memory. Same fixed dark-navy/cyan palette
/// as `MostOrderedScreen`'s own drill-down page, and the same 2-column
/// `GridView` + aspect-ratio-for-width formula, reused from `StoreCard`
/// rather than re-derived here.
class StoreListScreen extends ConsumerWidget {
  const StoreListScreen({required this.title, required this.vendors, super.key});

  final String title;
  final List<Vendor> vendors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currencyFormat = ref.watch(currencyFormatProvider);
    final vendorTheme = VendorPalette.themeFrom(Theme.of(context));

    return Theme(
      data: vendorTheme,
      child: Scaffold(
        backgroundColor: VendorPalette.background,
        appBar: AppBar(
          backgroundColor: VendorPalette.background,
          foregroundColor: VendorPalette.textPrimary,
          title: Text(title),
        ),
        body: ResponsiveCenter(
          child: LayoutBuilder(
            builder: (context, constraints) {
              const crossAxisSpacing = AppSpacing.sm;
              final cardWidth =
                  (constraints.maxWidth - AppSpacing.lg * 2 - crossAxisSpacing) / 2;
              final cardHeight = cardWidth / storeCardImageAspectRatio + storeCardBodyHeight;

              return GridView.builder(
                padding: const EdgeInsets.all(AppSpacing.lg),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: crossAxisSpacing,
                  mainAxisSpacing: AppSpacing.sm,
                  childAspectRatio: cardWidth / cardHeight,
                ),
                itemCount: vendors.length,
                itemBuilder: (context, index) {
                  final vendor = vendors[index];
                  return StoreCard(
                    vendor: vendor,
                    currencyFormat: currencyFormat,
                    onTap: () =>
                        Navigator.of(context).push(fadeSlideRoute(VendorMenuScreen(vendor: vendor))),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
