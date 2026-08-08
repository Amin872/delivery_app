import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/l10n/enum_labels.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/language_toggle_button.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/widgets/staggered_list_item.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/order.dart';
import '../widgets/driver_tracking_map.dart';
import 'customer_home_screen.dart' show firestoreServiceProvider;

final orderTrackingProvider = StreamProvider.family<DeliveryOrder, String>((ref, orderId) {
  return ref.watch(firestoreServiceProvider).watchOrder(orderId);
});

// `cancelled` is shown as a standalone terminal state rather than a stage in
// this progression, since an order can be cancelled from any earlier status.
const _trackedStatuses = [
  OrderStatus.pending,
  OrderStatus.accepted,
  OrderStatus.preparing,
  OrderStatus.readyForPickup,
  OrderStatus.pickedUp,
  OrderStatus.delivering,
  OrderStatus.delivered,
];

class OrderTrackingScreen extends ConsumerWidget {
  const OrderTrackingScreen({required this.orderId, super.key});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orderAsync = ref.watch(orderTrackingProvider(orderId));
    final l10n = AppLocalizations.of(context)!;
    final currencyFormat = NumberFormat.currency(
      locale: Localizations.localeOf(context).toString(),
      name: 'SYP',
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.orderTrackingTitle),
        actions: const [LanguageToggleButton()],
      ),
      body: orderAsync.when(
        data: (order) {
          final currentIndex = order.status == OrderStatus.cancelled
              ? -1
              : _trackedStatuses.indexOf(order.status);
          final colorScheme = Theme.of(context).colorScheme;
          final showDriverMap = order.driverId != null &&
              (order.status == OrderStatus.pickedUp ||
                  order.status == OrderStatus.delivering);
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              if (showDriverMap)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: DriverTrackingMap(driverId: order.driverId!),
                ),
              if (order.status == OrderStatus.cancelled)
                ListTile(
                  leading: Icon(Icons.cancel, color: colorScheme.error),
                  title: Text(orderStatusLabel(context, OrderStatus.cancelled)),
                )
              else
                for (var i = 0; i < _trackedStatuses.length; i++)
                  ListTile(
                    leading: i <= currentIndex
                        ? Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              gradient: AppGradients.primary(colorScheme),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.check, color: colorScheme.onPrimary, size: 18),
                          )
                        : Icon(Icons.radio_button_unchecked, color: colorScheme.outline),
                    title: Text(
                      orderStatusLabel(context, _trackedStatuses[i]),
                      style: i == currentIndex ? const TextStyle(fontWeight: FontWeight.bold) : null,
                    ),
                  ).staggeredEntrance(i),
              const Divider(),
              Card(
                child: ListTile(
                  title: Text(l10n.totalLabel),
                  trailing: Text(currencyFormat.format(order.total)),
                ),
              ),
              Card(
                child: ListTile(
                  title: Text(l10n.deliveryAddressLabel),
                  subtitle: Text(order.deliveryAddress),
                ),
              ),
            ],
          );
        },
        loading: () => const ListSkeletonLoader(),
        error: (error, _) =>
            Center(child: Text(localizedErrorMessage(context, error))),
      ),
    );
  }
}
