import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/l10n/enum_labels.dart';
import '../../../core/widgets/language_toggle_button.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/widgets/staggered_list_item.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/order.dart';
import '../../customer/screens/customer_home_screen.dart' show firestoreServiceProvider;
import '../../customer/screens/order_tracking_screen.dart';

final adminOrdersProvider =
    StreamProvider.family<List<DeliveryOrder>, OrderStatus?>((ref, status) {
  return ref.watch(firestoreServiceProvider).watchAllOrders(status: status);
});

class AdminOrdersScreen extends ConsumerStatefulWidget {
  const AdminOrdersScreen({super.key});

  @override
  ConsumerState<AdminOrdersScreen> createState() => _AdminOrdersScreenState();
}

class _AdminOrdersScreenState extends ConsumerState<AdminOrdersScreen> {
  OrderStatus? _statusFilter;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ordersAsync = ref.watch(adminOrdersProvider(_statusFilter));
    final locale = Localizations.localeOf(context).toString();
    final currencyFormat = NumberFormat.currency(locale: locale, name: 'SYP');
    final dateFormat = DateFormat.yMd(locale).add_Hm();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.adminOrdersTitle),
        actions: const [LanguageToggleButton()],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(l10n.allStatusesLabel),
                    selected: _statusFilter == null,
                    onSelected: (_) => setState(() => _statusFilter = null),
                  ),
                ),
                for (final status in OrderStatus.values)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(orderStatusLabel(context, status)),
                      selected: _statusFilter == status,
                      onSelected: (_) => setState(() => _statusFilter = status),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ordersAsync.when(
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
                        subtitle: Text(
                          '${orderStatusLabel(context, order.status)} · ${dateFormat.format(order.createdAt)}',
                        ),
                        trailing: Text(currencyFormat.format(order.total)),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => OrderTrackingScreen(orderId: order.id)),
                        ),
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
        ],
      ),
    );
  }
}
