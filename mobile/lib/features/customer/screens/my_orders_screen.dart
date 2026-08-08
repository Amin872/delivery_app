import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/l10n/enum_labels.dart';
import '../../../core/widgets/language_toggle_button.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/order.dart';
import 'customer_home_screen.dart' show firestoreServiceProvider;
import 'order_tracking_screen.dart';

final customerOrdersProvider =
    StreamProvider.family<List<DeliveryOrder>, String>((ref, customerId) {
  return ref.watch(firestoreServiceProvider).watchCustomerOrders(customerId);
});

class MyOrdersScreen extends ConsumerWidget {
  const MyOrdersScreen({required this.customerId, super.key});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(customerOrdersProvider(customerId));
    final l10n = AppLocalizations.of(context)!;
    final currencyFormat = NumberFormat.currency(
      locale: Localizations.localeOf(context).toString(),
      name: 'SYP',
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.myOrdersTitle),
        actions: const [LanguageToggleButton()],
      ),
      body: ordersAsync.when(
        data: (orders) {
          if (orders.isEmpty) {
            return Center(child: Text(l10n.noOrdersMessage));
          }
          return ListView.builder(
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final order = orders[index];
              return ListTile(
                title: Text(l10n.orderLabel(order.id)),
                subtitle: Text(orderStatusLabel(context, order.status)),
                trailing: Text(currencyFormat.format(order.total)),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => OrderTrackingScreen(orderId: order.id)),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text(localizedErrorMessage(context, error))),
      ),
    );
  }
}
