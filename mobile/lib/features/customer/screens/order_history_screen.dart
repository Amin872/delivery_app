import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/animated_async.dart';
import '../../../core/widgets/responsive_center.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/widgets/staggered_list_item.dart';
import '../../../l10n/app_localizations.dart';
import '../widgets/customer_order_tile.dart';
import 'my_orders_screen.dart' show customerOrdersProvider;

/// "الطلبات السابقة" — the finished subset (delivered/cancelled) of the same
/// real order stream [customerOrdersProvider] already exposes for
/// MyOrdersScreen, filtered client-side rather than a second Firestore
/// query, since it's the same small per-customer order list either way.
/// Rows are the same [CustomerOrderTile] MyOrdersScreen uses.
///
/// Same [VendorPalette] theme as MyOrdersScreen/AccountScreen — see that
/// screen's doc for why this used to be a separate ambient-themed screen.
class OrderHistoryScreen extends ConsumerWidget {
  const OrderHistoryScreen({required this.customerId, super.key});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(customerOrdersProvider(customerId));
    final l10n = AppLocalizations.of(context)!;
    final vendorTheme = VendorPalette.themeFrom(Theme.of(context));

    return Theme(
      data: vendorTheme,
      child: Scaffold(
        backgroundColor: VendorPalette.background,
        appBar: AppBar(
          backgroundColor: VendorPalette.background,
          foregroundColor: VendorPalette.textPrimary,
          title: Text(l10n.orderHistoryTitle),
        ),
        body: ResponsiveCenter(
          child: ordersAsync.animatedWhen(
            data: (orders) {
              final history = orders.where((o) => !isActiveCustomerOrder(o)).toList();
              if (history.isEmpty) {
                return Center(
                  child: Text(
                    l10n.noOrdersMessage,
                    style: const TextStyle(color: VendorPalette.textSecondary),
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: history.length,
                itemBuilder: (context, index) {
                  final order = history[index];
                  return CustomerOrderTile(key: ValueKey('order_${order.id}'), order: order)
                      .staggeredEntrance(index);
                },
              );
            },
            loading: () => const ListSkeletonLoader(),
            error: (error, _) => Center(
              child: Text(
                localizedErrorMessage(context, error),
                style: const TextStyle(color: VendorPalette.textSecondary),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
