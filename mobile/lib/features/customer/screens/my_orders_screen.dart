import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/l10n/enum_labels.dart';
import '../../../core/providers/formatters_provider.dart';
import '../../../core/widgets/animated_async.dart';
import '../../../core/widgets/language_toggle_button.dart';
import '../../../core/widgets/responsive_center.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/widgets/staggered_list_item.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/order.dart';
import '../../../routing/page_transitions.dart';
import 'customer_home_screen.dart' show firestoreServiceProvider;
import 'order_tracking_screen.dart';

final customerOrdersProvider =
    StreamProvider.autoDispose.family<List<DeliveryOrder>, String>((ref, customerId) {
  return ref.watch(firestoreServiceProvider).watchCustomerOrders(customerId);
});

class MyOrdersScreen extends ConsumerWidget {
  const MyOrdersScreen({required this.customerId, super.key});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(customerOrdersProvider(customerId));
    final l10n = AppLocalizations.of(context)!;
    final currencyFormat = ref.watch(currencyFormatProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.myOrdersTitle),
        actions: const [LanguageToggleButton()],
      ),
      body: ResponsiveCenter(
        child: ordersAsync.animatedWhen(
          data: (orders) {
          if (orders.isEmpty) {
            return Center(child: Text(l10n.noOrdersMessage));
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final order = orders[index];
              return Card(
                child: ListTile(
                  title: Text(l10n.orderLabel(order.id)),
                  subtitle: Text(orderStatusLabel(context, order.status)),
                  trailing: Text(currencyFormat.format(order.total)),
                  onTap: () => Navigator.of(context)
                      .push(fadeSlideRoute(OrderTrackingScreen(orderId: order.id))),
                ),
              ).staggeredEntrance(index);
            },
          );
        },
        loading: () => const ListSkeletonLoader(),
        error: (error, _) =>
            Center(child: Text(localizedErrorMessage(context, error))),
        ),
      ),
    );
  }
}
