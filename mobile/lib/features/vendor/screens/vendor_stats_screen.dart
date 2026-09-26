import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/formatters_provider.dart';
import '../../../core/stats/menu_item_tally.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/animated_async.dart';
import '../../../core/widgets/language_toggle_button.dart';
import '../../../core/widgets/responsive_center.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/widgets/stat_card.dart';
import '../../../core/widgets/staggered_list_item.dart';
import '../../../core/widgets/state_views.dart';
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

final vendorStatsProvider =
    FutureProvider.autoDispose.family<VendorStats, String>((ref, vendorId) async {
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
    final currencyFormat = ref.watch(currencyFormatProvider);
    final countFormat = ref.watch(countFormatProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.vendorStatsTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: const [LanguageToggleButton()],
      ),
      body: ResponsiveCenter(
        child: statsAsync.animatedWhen(
          data: (stats) => RefreshIndicator(
            onRefresh: () {
              ref.invalidate(vendorStatsProvider(vendorId));
              return ref.read(vendorStatsProvider(vendorId).future);
            },
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                // One tile per row: a phone is too narrow for a sales total
                // and an order count side by side at larger text sizes.
                Row(children: [
                  StatCard(
                    key: const ValueKey('vendor_stat_orders'),
                    label: l10n.totalOrdersLabel,
                    value: countFormat.format(stats.orderCount),
                    icon: Icons.receipt_long,
                  ),
                ]),
                const SizedBox(height: AppSpacing.md),
                Row(children: [
                  StatCard(
                    key: const ValueKey('vendor_stat_sales'),
                    label: l10n.totalSalesLabel,
                    value: currencyFormat.format(stats.salesTotal),
                    icon: Icons.payments,
                  ),
                ]),
                const SizedBox(height: AppSpacing.xl),
                Semantics(
                  header: true,
                  child: Text(l10n.topItemsTitle, style: Theme.of(context).textTheme.titleMedium),
                ),
                const SizedBox(height: AppSpacing.xs),
                if (stats.topItems.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    child: Text(l10n.noCompletedOrdersMessage),
                  )
                else
                  for (final (index, entry) in stats.topItems.indexed)
                    Card(
                      child: ListTile(
                        title: Text(entry.key),
                        trailing: Text(
                          countFormat.format(entry.value),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                    ).staggeredEntrance(index),
              ],
            ),
          ),
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Column(
              children: [
                StatCardRowSkeleton(),
                SizedBox(height: AppSpacing.xl),
                Expanded(child: ListSkeletonLoader(itemCount: 5)),
              ],
            ),
          ),
          error: (error, _) => ErrorState(
            error: error,
            onRetry: () => ref.invalidate(vendorStatsProvider(vendorId)),
          ),
        ),
      ),
    );
  }
}
