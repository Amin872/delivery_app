import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/enum_labels.dart';
import '../../../core/providers/formatters_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/order.dart';
import '../../../routing/page_transitions.dart';
import '../screens/order_tracking_screen.dart';

/// Statuses a customer's order is still moving through — everything except
/// the two terminal ones. MyOrdersScreen's Active/Past split and
/// OrderHistoryScreen's past-only list both read this one definition.
bool isActiveCustomerOrder(DeliveryOrder order) =>
    order.status != OrderStatus.delivered && order.status != OrderStatus.cancelled;

// `delivered` reuses the app's centralized success token (AppColors.success)
// instead of a one-off green, so this status color stays in sync with the
// rest of the app.
Color _statusColor(ColorScheme colorScheme, OrderStatus status) {
  switch (status) {
    case OrderStatus.delivered:
      return AppColors.success(colorScheme);
    case OrderStatus.cancelled:
      return colorScheme.error;
    default:
      return colorScheme.primary;
  }
}

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
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final statusColor = _statusColor(colorScheme, order.status);
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                orderStatusLabel(context, order.status),
                style: textTheme.labelSmall?.copyWith(color: statusColor, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        trailing: Text(currencyFormat.format(order.total)),
        onTap: () => Navigator.of(context).push(fadeSlideRoute(OrderTrackingScreen(orderId: order.id))),
      ),
    );
  }
}
