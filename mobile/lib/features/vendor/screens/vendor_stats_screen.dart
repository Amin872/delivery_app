import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/stats/menu_item_tally.dart';
import '../../../core/widgets/language_toggle_button.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/widgets/stat_card.dart';
import '../../../core/widgets/staggered_list_item.dart';
import '../../../l10n/app_localizations.dart';
import '../../customer/screens/customer_home_screen.dart' show firestoreServiceProvider;

class VendorStats {
  const VendorStats({
    required this.orderCount,
    required this.salesTotal,
    required this.topItems,
  });

  final int orderCount;
  final double salesTotal;
  final List<MapEntry<String, int>> topItems;
}

final vendorStatsProvider = FutureProvider.family<VendorStats, String>((ref, vendorId) async {
  final service = ref.watch(firestoreServiceProvider);
  final orderCount = await service.countVendorOrders(vendorId);
  final salesTotal = await service.sumVendorDeliveredSales(vendorId);
  final recentDelivered = await service.fetchRecentDeliveredOrders(vendorId);

  final tally = tallyMenuItemQuantities(recentDelivered).entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  return VendorStats(
    orderCount: orderCount,
    salesTotal: salesTotal,
    topItems: tally.take(5).toList(),
  );
});

class VendorStatsScreen extends ConsumerWidget {
  const VendorStatsScreen({required this.vendorId, super.key});

  final String vendorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(vendorStatsProvider(vendorId));
    final l10n = AppLocalizations.of(context)!;
    final currencyFormat = NumberFormat.currency(
      locale: Localizations.localeOf(context).toString(),
      name: 'SYP',
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.vendorStatsTitle),
        actions: const [LanguageToggleButton()],
      ),
      body: statsAsync.when(
        data: (stats) => RefreshIndicator(
          onRefresh: () {
            ref.invalidate(vendorStatsProvider(vendorId));
            return ref.read(vendorStatsProvider(vendorId).future);
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  StatCard(
                    label: l10n.totalOrdersLabel,
                    value: '${stats.orderCount}',
                    icon: Icons.receipt_long,
                  ),
                  const SizedBox(width: 12),
                  StatCard(
                    label: l10n.totalSalesLabel,
                    value: currencyFormat.format(stats.salesTotal),
                    icon: Icons.payments,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(l10n.topItemsTitle, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              if (stats.topItems.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(l10n.noCompletedOrdersMessage),
                )
              else
                for (final (index, entry) in stats.topItems.indexed)
                  Card(
                    child: ListTile(
                      title: Text(entry.key),
                      trailing: Text('${entry.value}'),
                    ),
                  ).staggeredEntrance(index),
            ],
          ),
        ),
        loading: () => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const StatCardRowSkeleton(),
              const SizedBox(height: 20),
              Expanded(child: const ListSkeletonLoader(itemCount: 5)),
            ],
          ),
        ),
        error: (error, _) =>
            Center(child: Text(localizedErrorMessage(context, error))),
      ),
    );
  }
}
