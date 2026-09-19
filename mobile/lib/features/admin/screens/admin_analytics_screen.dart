import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/providers/formatters_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/animated_async.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/widgets/stat_card.dart';
import '../../../l10n/app_localizations.dart';
import '../../customer/screens/customer_home_screen.dart' show firestoreServiceProvider;
import '../widgets/admin_scaffold.dart';

class MarketplaceStats {
  const MarketplaceStats({
    required this.userCount,
    required this.vendorCount,
    required this.driverCount,
    required this.orderCount,
    required this.deliveredSalesTotal,
  });

  final int userCount;
  final int vendorCount;
  final int driverCount;
  final int orderCount;
  final double deliveredSalesTotal;
}

/// Marketplace-wide totals for AdminAnalyticsScreen — every value comes
/// from a server-side Firestore `.count()`/`.aggregate(sum(...))` query
/// (see the matching methods in `FirestoreService`), never a full-collection
/// download, mirroring the same aggregation pattern
/// `VendorStatsScreen`/`DriverStatsScreen` already use at vendor/driver
/// scope. The five queries are independent of each other, so they run
/// concurrently rather than sequentially.
final marketplaceStatsProvider = FutureProvider.autoDispose<MarketplaceStats>((ref) async {
  final service = ref.watch(firestoreServiceProvider);
  final results = await Future.wait([
    service.countAllUsers(),
    service.countAllVendors(),
    service.countAllDrivers(),
    service.countAllOrders(),
    service.sumAllDeliveredSales(),
  ]);
  return MarketplaceStats(
    userCount: results[0] as int,
    vendorCount: results[1] as int,
    driverCount: results[2] as int,
    orderCount: results[3] as int,
    deliveredSalesTotal: results[4] as double,
  );
});

const _analyticsGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [VendorPalette.primaryCyan, VendorPalette.secondaryCyan],
);

/// Read-only marketplace-wide dashboard — total users/vendors/drivers/
/// orders and delivered revenue. Deliberately five numbers, not more:
/// nothing here is a metric the existing data model can't answer reliably
/// today (no `createdAt` range filter exists yet, so no time-windowed
/// "this week" stats — see ADMIN_AUDIT_REPORT.md's Analytics section).
class AdminAnalyticsScreen extends ConsumerWidget {
  const AdminAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final statsAsync = ref.watch(marketplaceStatsProvider);
    final currencyFormat = ref.watch(currencyFormatProvider);

    return AdminScaffold(
      title: l10n.adminNavAnalytics,
      selected: AdminDestination.analytics,
      body: statsAsync.animatedWhen(
        data: (stats) => RefreshIndicator(
          onRefresh: () {
            ref.invalidate(marketplaceStatsProvider);
            return ref.read(marketplaceStatsProvider.future);
          },
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            children: [
              Row(
                children: [
                  StatCard(
                    label: l10n.totalUsersLabel,
                    value: '${stats.userCount}',
                    icon: Icons.people_outline,
                    gradient: _analyticsGradient,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  StatCard(
                    label: l10n.totalVendorsLabel,
                    value: '${stats.vendorCount}',
                    icon: Icons.storefront_outlined,
                    gradient: _analyticsGradient,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  StatCard(
                    label: l10n.totalDriversLabel,
                    value: '${stats.driverCount}',
                    icon: Icons.two_wheeler_outlined,
                    gradient: _analyticsGradient,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  StatCard(
                    label: l10n.totalOrdersLabel,
                    value: '${stats.orderCount}',
                    icon: Icons.receipt_long_outlined,
                    gradient: _analyticsGradient,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  StatCard(
                    label: l10n.totalSalesLabel,
                    value: currencyFormat.format(stats.deliveredSalesTotal),
                    icon: Icons.payments_outlined,
                    gradient: _analyticsGradient,
                  ),
                ],
              ),
            ],
          ),
        ),
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Column(
            children: [
              StatCardRowSkeleton(),
              SizedBox(height: AppSpacing.md),
              StatCardRowSkeleton(),
            ],
          ),
        ),
        error: (error, _) => Center(
          child: Text(
            localizedErrorMessage(context, error),
            style: const TextStyle(color: VendorPalette.textSecondary),
          ),
        ),
      ),
    );
  }
}
