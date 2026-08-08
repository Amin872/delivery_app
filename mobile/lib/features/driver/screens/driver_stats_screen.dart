import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/business_constants.dart';
import '../../../core/errors/error_messages.dart';
import '../../../core/widgets/language_toggle_button.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/widgets/stat_card.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/driver.dart';
import '../../customer/screens/customer_home_screen.dart' show firestoreServiceProvider;

class DriverStats {
  const DriverStats({required this.deliveredCount});

  final int deliveredCount;

  double get earnings => deliveredCount * driverFeePerDelivery;
}

final driverStatsProvider = FutureProvider.family<DriverStats, String>((ref, driverId) async {
  final count = await ref.watch(firestoreServiceProvider).countDriverDeliveries(driverId);
  return DriverStats(deliveredCount: count);
});

final driverRatingProvider = StreamProvider.family<Driver, String>((ref, driverId) {
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
    final currencyFormat = NumberFormat.currency(
      locale: Localizations.localeOf(context).toString(),
      name: 'SYP',
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.driverStatsTitle),
        actions: const [LanguageToggleButton()],
      ),
      body: statsAsync.when(
        data: (stats) => RefreshIndicator(
          onRefresh: () {
            ref.invalidate(driverStatsProvider(driverId));
            return ref.read(driverStatsProvider(driverId).future);
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  StatCard(
                    label: l10n.deliveredOrdersLabel,
                    value: '${stats.deliveredCount}',
                    icon: Icons.local_shipping,
                  ),
                  const SizedBox(width: 12),
                  StatCard(
                    label: l10n.totalEarningsLabel,
                    value: currencyFormat.format(stats.earnings),
                    icon: Icons.payments,
                  ),
                  const SizedBox(width: 12),
                  StatCard(
                    label: l10n.ratingStatLabel,
                    value: driver == null || driver.ratingCount == 0
                        ? l10n.notRatedYetLabel
                        : driver.averageRating!.toStringAsFixed(1),
                    icon: Icons.star,
                  ),
                ],
              ),
            ],
          ),
        ),
        loading: () => const Padding(
          padding: EdgeInsets.all(16),
          child: StatCardRowSkeleton(),
        ),
        error: (error, _) =>
            Center(child: Text(localizedErrorMessage(context, error))),
      ),
    );
  }
}
