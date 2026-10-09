import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/display_formatters.dart';
import '../../../core/l10n/enum_labels.dart';
import '../../../core/paging/paged_list_controller.dart';
import '../../../core/providers/formatters_provider.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/staggered_list_item.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/order.dart';
import '../../../routing/page_transitions.dart';
import '../../customer/screens/customer_home_screen.dart' show firestoreServiceProvider;
import '../widgets/admin_actions.dart';
import '../widgets/admin_paged_list.dart';
import '../widgets/admin_scaffold.dart';
import 'admin_order_detail_screen.dart';

/// Every order, newest first, 25 per page with "Load more"; a status chip
/// filters on the server (the page restarts when it changes).
class AdminOrdersScreen extends ConsumerStatefulWidget {
  const AdminOrdersScreen({super.key});

  @override
  ConsumerState<AdminOrdersScreen> createState() => _AdminOrdersScreenState();
}

class _AdminOrdersScreenState extends ConsumerState<AdminOrdersScreen> {
  OrderStatus? _statusFilter;

  late final PagedListController<DeliveryOrder> _orders = PagedListController(
    idOf: (order) => order.id,
    fetchPage: (cursor) =>
        ref.read(firestoreServiceProvider).fetchOrdersPage(status: _statusFilter, after: cursor),
  );

  @override
  void initState() {
    super.initState();
    _orders.refresh();
  }

  @override
  void dispose() {
    _orders.dispose();
    super.dispose();
  }

  void _setStatusFilter(OrderStatus? status) {
    if (status == _statusFilter) return;
    setState(() => _statusFilter = status);
    _orders.refresh();
  }

  // The detail screen can cancel or reassign the order: re-read just that
  // order on return (dropping it if it no longer matches the status chip)
  // instead of reloading every page.
  Future<void> _openOrder(DeliveryOrder order) async {
    await Navigator.of(context).push(fadeSlideRoute(AdminOrderDetailScreen(orderId: order.id)));
    if (!mounted) return;
    try {
      final fresh = await ref.read(firestoreServiceProvider).fetchOrder(order.id);
      if (!mounted) return;
      if (fresh == null || (_statusFilter != null && fresh.status != _statusFilter)) {
        _orders.remove(order.id);
      } else {
        _orders.replace(fresh);
      }
    } catch (_) {
      // Keep the row as it was; the list stays usable and a refresh (status
      // chip) re-reads it.
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final currencyFormat = ref.watch(currencyFormatProvider);
    final dateFormat = ref.watch(dateTimeFormatProvider);

    // Inside the shared AdminScaffold (admin theme + nav), like every other
    // admin destination; the scaffold supplies the language toggle and
    // the responsive width.
    return AdminScaffold(
      title: l10n.adminOrdersTitle,
      selected: AdminDestination.orders,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: AdminFilterChipBar(
              chips: [
                ChoiceChip(
                  label: Text(l10n.allStatusesLabel),
                  selected: _statusFilter == null,
                  onSelected: (_) => _setStatusFilter(null),
                ),
                for (final status in OrderStatus.values)
                  ChoiceChip(
                    label: Text(orderStatusLabel(context, status)),
                    selected: _statusFilter == status,
                    onSelected: (_) => _setStatusFilter(status),
                  ),
              ],
            ),
          ),
          Expanded(
            child: AdminPagedList<DeliveryOrder>(
              controller: _orders,
              emptyMessage: l10n.noOrdersMessage,
              itemBuilder: (context, order, index) => Card(
                child: ListTile(
                  title: Text(l10n.orderLabel(displayOrderId(order.id))),
                  // The total sits on its own line rather than in
                  // `trailing`, where an eight-digit amount squeezed the
                  // title on a 320px phone.
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${orderStatusLabel(context, order.status)} · ${dateFormat.format(order.createdAt)}'),
                      Text(
                        currencyFormat.format(order.total),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  onTap: () => _openOrder(order),
                ),
              ).staggeredEntrance(index),
            ),
          ),
        ],
      ),
    );
  }
}
