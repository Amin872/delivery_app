import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/l10n/enum_labels.dart';
import '../../../core/providers/formatters_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/animated_async.dart';
import '../../../core/widgets/responsive_center.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/widgets/staggered_list_item.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/order.dart';
import '../../../routing/page_transitions.dart';
import 'my_orders_screen.dart' show customerOrdersProvider;
import 'order_tracking_screen.dart';

const _historyStatuses = {OrderStatus.delivered, OrderStatus.cancelled};

// Same reasoning as MyOrdersScreen's own `_statusColor` — a delivered order
// uses the app's centralized AppColors.success token rather than a
// one-off hardcoded green, so this stays in sync with the rest of the app.
Color _statusColor(ColorScheme colorScheme, OrderStatus status) {
  return status == OrderStatus.cancelled ? colorScheme.error : AppColors.success(colorScheme);
}

/// "الطلبات السابقة" — the finished subset (delivered/cancelled) of the same
/// real order stream [customerOrdersProvider] already exposes for
/// MyOrdersScreen, filtered client-side rather than a second Firestore
/// query, since it's the same small per-customer order list either way.
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
    final currencyFormat = ref.watch(currencyFormatProvider);
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
              final history = orders.where((o) => _historyStatuses.contains(o.status)).toList();
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
                  final colorScheme = Theme.of(context).colorScheme;
                  final statusColor = _statusColor(colorScheme, order.status);
                  return Card(
                    child: ListTile(
                      title: Text(l10n.orderLabel(order.id)),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            orderStatusLabel(context, order.status),
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: statusColor, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      trailing: Text(currencyFormat.format(order.total)),
                      onTap: () => Navigator.of(context)
                          .push(fadeSlideRoute(OrderTrackingScreen(orderId: order.id))),
                    ),
                  ).staggeredEntrance(index);
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
