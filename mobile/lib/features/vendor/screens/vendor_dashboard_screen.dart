import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/l10n/enum_labels.dart';
import '../../../core/widgets/language_toggle_button.dart';
import '../../../core/widgets/staggered_list_item.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/order.dart';
import '../../auth/providers/auth_provider.dart';
import '../../customer/screens/customer_home_screen.dart' show firestoreServiceProvider;
import 'menu_management_screen.dart';
import 'vendor_stats_screen.dart';

final vendorOrdersProvider =
    StreamProvider.family<List<DeliveryOrder>, String>((ref, vendorId) {
  return ref.watch(firestoreServiceProvider).watchVendorOrders(vendorId);
});

// Beyond `readyForPickup`, only the `acceptDelivery` callable (driver side)
// advances an order further — see the architecture note in CLAUDE.md — so
// the vendor is offered no action past that point.
OrderStatus? _nextVendorStatus(OrderStatus current) {
  switch (current) {
    case OrderStatus.pending:
      return OrderStatus.accepted;
    case OrderStatus.accepted:
      return OrderStatus.preparing;
    case OrderStatus.preparing:
      return OrderStatus.readyForPickup;
    default:
      return null;
  }
}

class VendorDashboardScreen extends ConsumerWidget {
  const VendorDashboardScreen({required this.vendorId, super.key});

  final String vendorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(vendorOrdersProvider(vendorId));
    final l10n = AppLocalizations.of(context)!;
    final currencyFormat = NumberFormat.currency(
      locale: Localizations.localeOf(context).toString(),
      name: 'SYP',
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.incomingOrdersTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: l10n.vendorStatsTitle,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => VendorStatsScreen(vendorId: vendorId)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.restaurant_menu),
            tooltip: l10n.menuManagementTitle,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => MenuManagementScreen(vendorId: vendorId)),
            ),
          ),
          const LanguageToggleButton(),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: l10n.signOutTooltip,
            onPressed: () => ref.read(authServiceProvider).signOut(),
          ),
        ],
      ),
      body: ordersAsync.when(
        data: (orders) {
          if (orders.isEmpty) {
            return Center(child: Text(l10n.noOrdersMessage));
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final order = orders[index];
              final next = _nextVendorStatus(order.status);
              return Card(
                child: ListTile(
                  title: Text(l10n.orderLabel(order.id)),
                  subtitle: Text(orderStatusLabel(context, order.status)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(currencyFormat.format(order.total)),
                      if (next != null) ...[
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () => ref
                              .read(firestoreServiceProvider)
                              .updateOrderStatus(order.id, next),
                          child:
                              Text(l10n.advanceStatusButtonLabel(orderStatusLabel(context, next))),
                        ),
                      ],
                    ],
                  ),
                ),
              ).staggeredEntrance(index);
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
