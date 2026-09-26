import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/business_constants.dart';
import '../../../core/providers/formatters_provider.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/animated_async.dart';
import '../../../core/widgets/language_toggle_button.dart';
import '../../../core/widgets/responsive_center.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/widgets/stat_card.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/driver.dart';
import '../../customer/screens/customer_home_screen.dart' show firestoreServiceProvider;

class DriverStats {
  const DriverStats({required this.deliveredCount});

  final int deliveredCount;

  double get earnings => deliveredCount * driverFeePerDelivery;
}

final driverStatsProvider =
    FutureProvider.autoDispose.family<DriverStats, String>((ref, driverId) async {
  final count = await ref.watch(firestoreServiceProvider).countDriverDeliveries(driverId);
  return DriverStats(deliveredCount: count);
});

final driverRatingProvider = StreamProvider.autoDispose.family<Driver, String>((ref, driverId) {
  return ref.watch(firestoreServiceProvider).watchDriver(driverId);
});

class DriverStatsScreen extends ConsumerWidget {
  const DriverStatsScreen({required this.driverId, super.key});

  final String driverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(driverStatsProvider(driverId));
    final driver = ref.watch(driverRatingProvider(driverId)).valueOrNull;
    final l10n = AppLocalizations.of(context)!;
    final currencyFormat = ref.watch(currencyFormatProvider);
    final countFormat = ref.watch(countFormatProvider);
    final averageRating = driver?.averageRating;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.driverStatsTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: const [LanguageToggleButton()],
      ),
      body: ResponsiveCenter(
        child: statsAsync.animatedWhen(
          data: (stats) => RefreshIndicator(
            onRefresh: () {
              ref.invalidate(driverStatsProvider(driverId));
              return ref.read(driverStatsProvider(driverId).future);
            },
            // One tile per row: three tiles side by side leave a phone's
            // earnings figure unreadably small.
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                Row(children: [
                  StatCard(
                    key: const ValueKey('driver_stat_delivered'),
                    label: l10n.deliveredOrdersLabel,
                    value: countFormat.format(stats.deliveredCount),
                    icon: Icons.local_shipping,
                  ),
                ]),
                const SizedBox(height: AppSpacing.md),
                Row(children: [
                  StatCard(
                    key: const ValueKey('driver_stat_earnings'),
                    label: l10n.totalEarningsLabel,
                    value: currencyFormat.format(stats.earnings),
                    icon: Icons.payments,
                  ),
                ]),
                const SizedBox(height: AppSpacing.md),
                Row(children: [
                  StatCard(
                    key: const ValueKey('driver_stat_rating'),
                    label: l10n.ratingStatLabel,
                    // Same one-decimal, Western-digit form as the app's
                    // star ratings (StarRatingDisplay).
                    value: averageRating == null ? l10n.notRatedYetLabel : averageRating.toStringAsFixed(1),
                    icon: Icons.star,
                  ),
                ]),
              ],
            ),
          ),
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: StatCardRowSkeleton(),
          ),
          error: (error, _) => ErrorState(
            error: error,
            onRetry: () => ref.invalidate(driverStatsProvider(driverId)),
          ),
        ),
      ),
    );
  }
}
