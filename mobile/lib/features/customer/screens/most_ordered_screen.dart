import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// intl exports its own conflicting `TextDirection`, unused here but kept
// hidden for consistency with the other Most Ordered files that need it.
import 'package:intl/intl.dart' hide TextDirection;

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/vendor.dart';
import '../providers/cart_provider.dart';
import '../widgets/cart_add_flow.dart';
import '../widgets/floating_order_button.dart';
import '../widgets/most_ordered_card.dart';
import '../widgets/product_details_sheet.dart';
import 'cart_screen.dart';
import '../../../routing/page_transitions.dart';

/// Full "Most ordered" grid — opened from the trailing arrow at the end of
/// VendorMenuScreen's horizontal carousel (`MostOrderedSection`). Shows
/// every qualifying item, not just the handful the carousel has room for,
/// in a 2-column grid using the exact same `MostOrderedCard` component —
/// same image ratio, footer, "+" badge, colors — so this is a different
/// layout of the same card, never a second card design.
class MostOrderedScreen extends ConsumerWidget {
  const MostOrderedScreen({
    required this.vendorId,
    required this.vendorName,
    required this.title,
    required this.items,
    required this.currencyFormat,
    super.key,
  });

  final String vendorId;
  final String vendorName;
  final String title;
  final List<MenuItem> items;
  final NumberFormat currencyFormat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    // Same fixed dark-navy/cyan palette as VendorMenuScreen (Phase 4A) —
    // this page is a drill-down of that screen's own "Most ordered"
    // section, so it must carry the same look rather than falling back to
    // the app's ambient light/dark theme.
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
        // Stack (not `Scaffold.bottomNavigationBar`) so the order button
        // floats over the grid with its own margin, matching
        // VendorMenuScreen's floating button rather than reverting to the
        // old docked bar for this drill-down page.
        body: Stack(
          children: [
            SafeArea(
              top: false,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const crossAxisSpacing = AppSpacing.sm;
                  final cardWidth =
                      (constraints.maxWidth - AppSpacing.lg * 2 - crossAxisSpacing) / 2;
                  final cardHeight =
                      cardWidth / mostOrderedImageAspectRatio + mostOrderedFooterHeight;

                  return GridView.builder(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: crossAxisSpacing,
                      mainAxisSpacing: AppSpacing.sm,
                      childAspectRatio: cardWidth / cardHeight,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return MostOrderedCard(
                        item: item,
                        currencyFormat: currencyFormat,
                        onAddToCart: () => addToCartWithVendorSwitchConfirm(
                          context,
                          ref,
                          vendorId: vendorId,
                          vendorName: vendorName,
                          item: item,
                        ),
                        onTap: () => showProductDetailsSheet(
                          context,
                          vendorId: vendorId,
                          vendorName: vendorName,
                          item: item,
                        ),
                      );
                    },
                  );
                },
              ),
            ),
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
      ),
    );
  }
}
