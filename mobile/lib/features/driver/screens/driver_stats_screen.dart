import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/business_constants.dart';
import '../../../core/errors/error_messages.dart';
import '../../../core/widgets/language_toggle_button.dart';
import '../../../l10n/app_localizations.dart';
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

class DriverStatsScreen extends ConsumerWidget {
  const DriverStatsScreen({required this.driverId, super.key});

  final String driverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(driverStatsProvider(driverId));
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
            children: [
              ListTile(
                title: Text(l10n.deliveredOrdersLabel),
                trailing: Text('${stats.deliveredCount}'),
              ),
              ListTile(
                title: Text(l10n.totalEarningsLabel),
                trailing: Text(currencyFormat.format(stats.earnings)),
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
