import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/formatters_provider.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/order.dart';
import '../../../routing/page_transitions.dart';
import '../screens/order_tracking_screen.dart';

/// Statuses a customer's order is still moving through — everything except
/// the two terminal ones. MyOrdersScreen's Active/Past split and
/// OrderHistoryScreen's past-only list both read this one definition.
bool isActiveCustomerOrder(DeliveryOrder order) =>
    order.status != OrderStatus.delivered && order.status != OrderStatus.cancelled;

/// One order in the customer's order lists (MyOrdersScreen,
/// OrderHistoryScreen): store name, when it was placed, a localized status
/// chip and the total. Tapping opens the existing OrderTrackingScreen.
/// Orders placed before the store name was saved on the order show a
/// generic "Order" title rather than their raw document id.
class CustomerOrderTile extends ConsumerWidget {
  const CustomerOrderTile({required this.order, super.key});

  final DeliveryOrder order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final currencyFormat = ref.watch(currencyFormatProvider);
    final dateFormat = ref.watch(dateTimeFormatProvider);
    final textTheme = Theme.of(context).textTheme;
    final vendorName = order.vendorName?.trim() ?? '';

    return Card(
      child: ListTile(
        title: Text(
          vendorName.isEmpty ? l10n.orderFallbackTitle : vendorName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(dateFormat.format(order.createdAt), style: textTheme.bodySmall),
            const SizedBox(height: 4),
            OrderStatusChip(status: order.status),
          ],
        ),
        trailing: Text(currencyFormat.format(order.total)),
        onTap: () => Navigator.of(context).push(fadeSlideRoute(OrderTrackingScreen(orderId: order.id))),
      ),
    );
  }
}
