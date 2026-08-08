import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/stats/menu_item_tally.dart';
import '../../../core/widgets/language_toggle_button.dart';
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
            children: [
              ListTile(
                title: Text(l10n.totalOrdersLabel),
                trailing: Text('${stats.orderCount}'),
              ),
              ListTile(
                title: Text(l10n.totalSalesLabel),
                trailing: Text(currencyFormat.format(stats.salesTotal)),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(l10n.topItemsTitle, style: Theme.of(context).textTheme.titleMedium),
              ),
              if (stats.topItems.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(l10n.noCompletedOrdersMessage),
                )
              else
                for (final entry in stats.topItems)
                  ListTile(
                    title: Text(entry.key),
                    trailing: Text('${entry.value}'),
                  ),
            ],
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text(localizedErrorMessage(context, error))),
      ),
    );
  }
}
