import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/location/navigation_launcher.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/animated_async.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/language_toggle_button.dart';
import '../../../core/widgets/responsive_center.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/widgets/staggered_list_item.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/approval_status.dart';
import '../../../models/coordinates.dart';
import '../../../models/driver.dart';
import '../../../models/order.dart';
import '../../../routing/page_transitions.dart';
import '../../../services/functions_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../customer/screens/customer_home_screen.dart' show firestoreServiceProvider;
import '../../vendor/screens/menu_management_screen.dart' show storageServiceProvider;
import '../providers/driver_location_provider.dart';
import '../widgets/driver_active_delivery_card.dart';
import '../widgets/driver_available_order_card.dart';
import '../widgets/driver_order_summary.dart' show recentDriverPosition;
import 'driver_stats_screen.dart';

final availableOrdersProvider = StreamProvider<List<DeliveryOrder>>((ref) {
  return ref.watch(firestoreServiceProvider).watchAvailableOrdersForDrivers();
});

// Null when the signed-in driver has no delivery currently in flight — see
// FirestoreService.watchActiveDriverOrder. Also what keeps
// driverLocationSyncProvider fed with "is this driver mid-delivery?".
final activeDriverOrderProvider = StreamProvider.autoDispose.family<DeliveryOrder?, String>((ref, driverId) {
  return ref.watch(firestoreServiceProvider).watchActiveDriverOrder(driverId);
});

final driverSelfProvider = StreamProvider.autoDispose.family<Driver, String>((ref, driverId) {
  return ref.watch(firestoreServiceProvider).watchDriver(driverId);
});

final functionsServiceProvider = Provider<FunctionsService>((ref) => FunctionsService());

// The only two forward steps a driver can drive themselves — anything past
// "delivering" (or before "pickedUp") has no client-facing next action.
// Mirrors `DRIVER_PROGRESSION` in functions/src/orders.ts, which is what
// actually enforces this — this is only used to decide whether to show the
// advance button.
OrderStatus? _nextDriverStatus(OrderStatus current) {
  switch (current) {
    case OrderStatus.driverAssigned:
      return OrderStatus.pickedUp;
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
    HapticFeedback.lightImpact();
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
    HapticFeedback.lightImpact();
    setState(() => _advancing = true);
    final messenger = ScaffoldMessenger.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    try {
      String? proofImageUrl;
      if (needsProof && _proofImage != null) {
        proofImageUrl = await ref.read(storageServiceProvider).uploadOrderProof(order.id, _proofImage!);
      }
      await ref.read(functionsServiceProvider).advanceDelivery(order.id, proofImageUrl: proofImageUrl);
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

  Future<void> _navigateTo(Coordinates destination) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final opened = await launchDirections(destination);
    if (!opened) {
      messenger.showSnackBar(buildAppSnackBar(colorScheme, l10n.navigationFailedMessage, isError: true));
    }
  }

  Widget _buildActiveDeliveryCard(BuildContext context, DeliveryOrder order, Coordinates? driverPosition) {
    final next = _nextDriverStatus(order.status);
    // Only the final hop (delivering -> delivered) asks for a photo — the
    // driver hasn't reached the customer yet on the step before it.
    final needsProof = next == OrderStatus.delivered;
    final canAdvance = next != null && (!needsProof || _proofImage != null);
    // Laid out at its full height: the whole screen scrolls (see build), so
    // the proof picker and the advance button are never clipped away.
    return DriverActiveDeliveryCard(
      order: order,
      nextStatus: next,
      needsProof: needsProof,
      canAdvance: canAdvance,
      advancing: _advancing,
      proofImage: _proofImage,
      onProofPicked: (file) => setState(() => _proofImage = file),
      onAdvance: () => _advance(order, needsProof: needsProof),
      driverPosition: driverPosition,
      onNavigate: _navigateTo,
      fetchCustomerPhone: () =>
          ref.read(functionsServiceProvider).getOrderContact(order.id, ContactTarget.customer),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final driverId = ref.watch(currentAppUserProvider).valueOrNull?.id;

    // Side effect only: while this screen is alive and the driver has an
    // active delivery, streams device position to drivers/{uid} so the
    // customer's tracking screen can show it live. See
    // driver_location_provider.dart.
    if (driverId != null) ref.watch(driverLocationSyncProvider(driverId));

    final activeOrder = driverId == null ? null : ref.watch(activeDriverOrderProvider(driverId)).valueOrNull;
    final driverSelfAsync = driverId == null ? null : ref.watch(driverSelfProvider(driverId));
    final driverSelf = driverSelfAsync?.valueOrNull;
    // Approval gate. Only an admin-approved driver sees the unclaimed queue
    // and the availability switch (firestore.rules and acceptDelivery
    // enforce the same thing server-side). The active-delivery card stays
    // for everyone, so a driver whose approval is revoked mid-delivery can
    // still finish it. Stats, language and sign-out remain in every state.
    final isApproved = driverSelf?.approvalStatus == ApprovalStatus.approved;
    // Availability gate (approved drivers only). Offline hides the queue
    // (and never subscribes to it); acceptDelivery enforces the same thing
    // server-side. The switch and any active delivery stay, so the driver
    // can come back online or finish what they already hold.
    final isOnline = driverSelf?.isAvailable ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.availableDeliveriesTitle),
        actions: [
          if (driverSelf != null && isApproved)
            Tooltip(
              message: l10n.driverAvailableTooltip,
              child: Switch(
                key: const ValueKey('driver_available_switch'),
                value: driverSelf.isAvailable,
                onChanged: (value) {
                  HapticFeedback.selectionClick();
                  ref.read(firestoreServiceProvider).setDriverAvailability(driverId!, value);
                },
              ),
            ),
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: l10n.driverStatsTitle,
            onPressed: driverId == null
                ? null
                : () => Navigator.of(context).push(fadeSlideRoute(DriverStatsScreen(driverId: driverId))),
          ),
          const LanguageToggleButton(),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: l10n.signOutTooltip,
            onPressed: () => ref.read(authServiceProvider).signOut(),
          ),
        ],
      ),
      // One scroll for the whole screen: the active delivery (full height,
      // when there is one) scrolls away above the queue, which fills the
      // rest of the viewport exactly as it would on its own.
      body: ResponsiveCenter(
        child: CustomScrollView(
          slivers: [
            if (activeOrder != null)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                sliver: SliverToBoxAdapter(
                  child: _buildActiveDeliveryCard(
                    context,
                    activeOrder,
                    // The driver's own last published GPS fix (same pipeline
                    // that feeds the customer's map) — no second GPS stream.
                    recentDriverPosition(driverSelf?.lastKnownLocation, DateTime.now()),
                  ),
                ),
              ),
            SliverFillRemaining(
              child: driverSelfAsync == null || driverSelf == null
                  ? (driverSelfAsync?.hasError ?? false)
                        ? Center(child: Text(localizedErrorMessage(context, driverSelfAsync!.error!)))
                        : const ListSkeletonLoader()
                  : !isApproved
                  ? _DriverStatusView.approval(driverSelf.approvalStatus)
                  : isOnline
                  ? _buildAvailableOrders(context)
                  : const _DriverStatusView.offline(),
            ),
          ],
        ),
      ),
    );
  }

  // The unclaimed readyForPickup queue. Only built (and so only queried) for
  // an approved driver — firestore.rules denies the query to anyone else.
  Widget _buildAvailableOrders(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ref
        .watch(availableOrdersProvider)
        .animatedWhen(
          data: (orders) {
            if (orders.isEmpty) {
              return Center(child: Text(l10n.noDeliveriesMessage));
            }
            return ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: orders.length,
              itemBuilder: (context, index) {
                final order = orders[index];
                return DriverAvailableOrderCard(
                  order: order,
                  isAccepting: _acceptingOrderIds.contains(order.id),
                  onAccept: () => _accept(order),
                ).staggeredEntrance(index);
              },
            );
          },
          loading: () => const ListSkeletonLoader(),
          error: (error, _) => Center(child: Text(localizedErrorMessage(context, error))),
        );
  }
}

enum _DriverStatusKind { pending, rejected, offline }

/// Shown instead of the delivery queue when the driver can't take new work:
/// not approved yet, rejected (Phase 24), or switched offline (Phase 25).
class _DriverStatusView extends StatelessWidget {
  const _DriverStatusView._(this.kind);

  /// For a driver who isn't approved (pending or rejected).
  factory _DriverStatusView.approval(ApprovalStatus status) => _DriverStatusView._(
    status == ApprovalStatus.rejected ? _DriverStatusKind.rejected : _DriverStatusKind.pending,
  );

  const _DriverStatusView.offline() : kind = _DriverStatusKind.offline;

  final _DriverStatusKind kind;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final (key, icon, iconColor, title, message) = switch (kind) {
      _DriverStatusKind.pending => (
        'driver_approval_pending',
        Icons.hourglass_top_outlined,
        colorScheme.primary,
        l10n.vendorPendingApprovalTitle,
        l10n.driverPendingApprovalMessage,
      ),
      _DriverStatusKind.rejected => (
        'driver_approval_rejected',
        Icons.block_outlined,
        colorScheme.error,
        l10n.driverRejectedTitle,
        l10n.driverRejectedMessage,
      ),
      _DriverStatusKind.offline => (
        'driver_offline',
        Icons.power_settings_new,
        colorScheme.onSurfaceVariant,
        l10n.driverOfflineTitle,
        l10n.driverOfflineMessage,
      ),
    };

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          key: ValueKey(key),
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: iconColor),
            const SizedBox(height: AppSpacing.lg),
            Text(title, style: textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
