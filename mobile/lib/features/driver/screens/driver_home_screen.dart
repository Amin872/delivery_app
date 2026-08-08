import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/app_spinner.dart';
import '../../../core/widgets/language_toggle_button.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/widgets/staggered_list_item.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/order.dart';
import '../../../services/functions_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../customer/screens/customer_home_screen.dart' show firestoreServiceProvider;
import 'driver_stats_screen.dart';

final availableOrdersProvider = StreamProvider<List<DeliveryOrder>>((ref) {
  return ref.watch(firestoreServiceProvider).watchAvailableOrdersForDrivers();
});

final functionsServiceProvider =
    Provider<FunctionsService>((ref) => FunctionsService());

class DriverHomeScreen extends ConsumerStatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  ConsumerState<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends ConsumerState<DriverHomeScreen> {
  final _acceptingOrderIds = <String>{};

  Future<void> _accept(DeliveryOrder order) async {
    setState(() => _acceptingOrderIds.add(order.id));
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    try {
      await ref.read(functionsServiceProvider).acceptDelivery(order.id);
      messenger.showSnackBar(buildAppSnackBar(colorScheme, l10n.orderAcceptedMessage));
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(
          buildAppSnackBar(colorScheme, localizedErrorMessage(context, error), isError: true),
        );
      }
    } finally {
      if (mounted) setState(() => _acceptingOrderIds.remove(order.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(availableOrdersProvider);
    final l10n = AppLocalizations.of(context)!;
    final driverId = ref.watch(currentAppUserProvider).valueOrNull?.id;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.availableDeliveriesTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: l10n.driverStatsTitle,
            onPressed: driverId == null
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => DriverStatsScreen(driverId: driverId)),
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
            return Center(child: Text(l10n.noDeliveriesMessage));
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final order = orders[index];
              final isAccepting = _acceptingOrderIds.contains(order.id);
              return Card(
                child: ListTile(
                  title: Text(l10n.orderLabel(order.id)),
                  subtitle: Text(order.deliveryAddress),
                  trailing: FilledButton(
                    onPressed: isAccepting ? null : () => _accept(order),
                    child: isAccepting
                        ? buttonSpinner(Theme.of(context).colorScheme.onPrimary, size: 16)
                        : Text(l10n.acceptButton),
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
    );
  }
}
