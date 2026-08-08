import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/l10n/enum_labels.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/app_spinner.dart';
import '../../../core/widgets/image_picker_avatar.dart';
import '../../../core/widgets/language_toggle_button.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/widgets/staggered_list_item.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/order.dart';
import '../../../services/functions_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../customer/screens/customer_home_screen.dart' show firestoreServiceProvider;
import '../../vendor/screens/menu_management_screen.dart' show storageServiceProvider;
import '../providers/driver_location_provider.dart';
import 'driver_stats_screen.dart';

final availableOrdersProvider = StreamProvider<List<DeliveryOrder>>((ref) {
  return ref.watch(firestoreServiceProvider).watchAvailableOrdersForDrivers();
});

// Null when the signed-in driver has no delivery currently in flight — see
// FirestoreService.watchActiveDriverOrder. Also what keeps
// driverLocationSyncProvider fed with "is this driver mid-delivery?".
final activeDriverOrderProvider = StreamProvider.family<DeliveryOrder?, String>((ref, driverId) {
  return ref.watch(firestoreServiceProvider).watchActiveDriverOrder(driverId);
});

final functionsServiceProvider =
    Provider<FunctionsService>((ref) => FunctionsService());

// The only two forward steps a driver can drive themselves — anything past
// "delivering" (or before "pickedUp") has no client-facing next action.
// Mirrors `DRIVER_PROGRESSION` in functions/src/orders.ts, which is what
// actually enforces this — this is only used to decide whether to show the
// advance button.
OrderStatus? _nextDriverStatus(OrderStatus current) {
  switch (current) {
    case OrderStatus.pickedUp:
      return OrderStatus.delivering;
    case OrderStatus.delivering:
      return OrderStatus.delivered;
    default:
      return null;
  }
}

class DriverHomeScreen extends ConsumerStatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  ConsumerState<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends ConsumerState<DriverHomeScreen> {
  final _acceptingOrderIds = <String>{};
  bool _advancing = false;
  File? _proofImage;

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

  Future<void> _advance(DeliveryOrder order, {required bool needsProof}) async {
    setState(() => _advancing = true);
    final messenger = ScaffoldMessenger.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    try {
      String? proofImageUrl;
      if (needsProof && _proofImage != null) {
        proofImageUrl = await ref
            .read(storageServiceProvider)
            .uploadOrderProof(order.id, _proofImage!);
      }
      await ref
          .read(functionsServiceProvider)
          .advanceDelivery(order.id, proofImageUrl: proofImageUrl);
      if (mounted) setState(() => _proofImage = null);
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(
          buildAppSnackBar(colorScheme, localizedErrorMessage(context, error), isError: true),
        );
      }
    } finally {
      if (mounted) setState(() => _advancing = false);
    }
  }

  Widget _buildActiveDeliveryCard(BuildContext context, DeliveryOrder order) {
    final l10n = AppLocalizations.of(context)!;
    final next = _nextDriverStatus(order.status);
    // Only the final hop (delivering -> delivered) asks for a photo — the
    // driver hasn't reached the customer yet on the step before it.
    final needsProof = next == OrderStatus.delivered;
    final canAdvance = next != null && (!needsProof || _proofImage != null);
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            title: Text(l10n.orderLabel(order.id)),
            subtitle: Text(
              '${orderStatusLabel(context, order.status)} · ${order.deliveryAddress}',
            ),
          ),
          if (needsProof)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  ImagePickerAvatar(
                    radius: 28,
                    localFile: _proofImage,
                    onPicked: (file) => setState(() => _proofImage = file),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(l10n.proofOfDeliveryHint)),
                ],
              ),
            ),
          if (next != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: FilledButton(
                onPressed:
                    (_advancing || !canAdvance) ? null : () => _advance(order, needsProof: needsProof),
                child: _advancing
                    ? buttonSpinner(Theme.of(context).colorScheme.onPrimary, size: 16)
                    : Text(l10n.advanceStatusButtonLabel(orderStatusLabel(context, next))),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(availableOrdersProvider);
    final l10n = AppLocalizations.of(context)!;
    final driverId = ref.watch(currentAppUserProvider).valueOrNull?.id;

    // Side effect only: while this screen is alive and the driver has an
    // active delivery, streams device position to drivers/{uid} so the
    // customer's tracking screen can show it live. See
    // driver_location_provider.dart.
    if (driverId != null) ref.watch(driverLocationSyncProvider(driverId));

    final activeOrder =
        driverId == null ? null : ref.watch(activeDriverOrderProvider(driverId)).valueOrNull;

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
      body: Column(
        children: [
          if (activeOrder != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: _buildActiveDeliveryCard(context, activeOrder),
            ),
          Expanded(
            child: ordersAsync.when(
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
          ),
        ],
      ),
    );
  }
}
