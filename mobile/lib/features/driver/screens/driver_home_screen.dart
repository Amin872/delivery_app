import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/location/navigation_launcher.dart';
import '../../../core/providers/preferences_provider.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/responsive_center.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/widgets/staggered_list_item.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_badge.dart';
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

/// A proof photo and the order it was taken for. Proof is only ever
/// uploaded for that same order.
typedef _Proof = ({File file, String orderId});

class DriverHomeScreen extends ConsumerStatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  ConsumerState<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends ConsumerState<DriverHomeScreen> {
  final _acceptingOrderIds = <String>{};
  bool _advancing = false;
  _Proof? _proof;
  // The value the availability switch shows while its write is in flight;
  // null otherwise (the switch then follows the driver doc).
  bool? _pendingAvailability;

  File? _proofFor(DeliveryOrder order) => _proof?.orderId == order.id ? _proof!.file : null;

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
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    File? proofFile;
    if (needsProof) {
      // Never upload a photo taken for another order.
      final proof = _proof;
      if (proof == null || proof.orderId != order.id) {
        setState(() => _proof = null);
        messenger.showSnackBar(buildAppSnackBar(colorScheme, l10n.proofStaleMessage, isError: true));
        return;
      }
      proofFile = proof.file;
      // Delivered is final: confirm first (UI only — the server still
      // decides whether the step is allowed).
      final confirmed = await showConfirmDialog(
        context,
        title: l10n.confirmDeliveredTitle,
        message: l10n.confirmDeliveredMessage,
      );
      if (confirmed != true || !mounted) return;
    }

    HapticFeedback.lightImpact();
    setState(() => _advancing = true);
    try {
      String? proofImageUrl;
      if (proofFile != null) {
        proofImageUrl = await ref.read(storageServiceProvider).uploadOrderProof(order.id, proofFile);
      }
      await ref.read(functionsServiceProvider).advanceDelivery(order.id, proofImageUrl: proofImageUrl);
      if (mounted) setState(() => _proof = null);
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

  // Awaited, with the switch held at the new value (and disabled) while
  // the write runs; a failure puts it back and says why.
  Future<void> _setAvailability(String driverId, bool value) async {
    HapticFeedback.selectionClick();
    final messenger = ScaffoldMessenger.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    setState(() => _pendingAvailability = value);
    try {
      await ref.read(firestoreServiceProvider).setDriverAvailability(driverId, value);
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(
          buildAppSnackBar(colorScheme, localizedErrorMessage(context, error), isError: true),
        );
      }
    } finally {
      if (mounted) setState(() => _pendingAvailability = null);
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

  void _onMoreAction(_DriverMoreAction action, String? driverId) {
    switch (action) {
      case _DriverMoreAction.stats:
        if (driverId != null) {
          Navigator.of(context).push(fadeSlideRoute(DriverStatsScreen(driverId: driverId)));
        }
      case _DriverMoreAction.language:
        ref.read(localeProvider.notifier).toggle();
      case _DriverMoreAction.signOut:
        ref.read(authServiceProvider).signOut();
    }
  }

  Widget _buildActiveDeliveryCard(BuildContext context, DeliveryOrder order, Coordinates? driverPosition) {
    final next = _nextDriverStatus(order.status);
    // Only the final hop (delivering -> delivered) asks for a photo — the
    // driver hasn't reached the customer yet on the step before it.
    final needsProof = next == OrderStatus.delivered;
    final proofFile = _proofFor(order);
    final canAdvance = next != null && (!needsProof || proofFile != null);
    // Laid out at its full height: the whole screen scrolls (see build), so
    // the proof picker and the advance button are never clipped away.
    return DriverActiveDeliveryCard(
      order: order,
      nextStatus: next,
      needsProof: needsProof,
      canAdvance: canAdvance,
      advancing: _advancing,
      proofImage: proofFile,
      onProofPicked: (file) => setState(() => _proof = (file: file, orderId: order.id)),
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
    if (driverId != null) {
      ref.watch(driverLocationSyncProvider(driverId));
      // A proof photo belongs to one order: drop it as soon as the active
      // order becomes a different one (or none).
      ref.listen(activeDriverOrderProvider(driverId), (_, next) {
        final proof = _proof;
        if (proof != null && next.valueOrNull?.id != proof.orderId && !next.isLoading) {
          setState(() => _proof = null);
        }
      });
    }

    final activeAsync = driverId == null ? null : ref.watch(activeDriverOrderProvider(driverId));
    final activeOrder = activeAsync?.valueOrNull;
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

    final title = switch ((driverSelf, activeOrder)) {
      (_, DeliveryOrder()) => l10n.activeDeliveryTitle,
      (null, _) => l10n.driverHomeTitle,
      (Driver(approvalStatus: ApprovalStatus.pending), _) => l10n.driverPendingApprovalTitle,
      (Driver(approvalStatus: ApprovalStatus.rejected), _) => l10n.driverNotApprovedTitle,
      _ when !isOnline => l10n.driverOfflineTitle,
      _ => l10n.availableDeliveriesTitle,
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (driverSelf != null && isApproved)
            Tooltip(
              message: l10n.driverAvailableTooltip,
              child: Switch(
                key: const ValueKey('driver_available_switch'),
                value: _pendingAvailability ?? driverSelf.isAvailable,
                onChanged: _pendingAvailability != null ? null : (value) => _setAvailability(driverId!, value),
              ),
            ),
          PopupMenuButton<_DriverMoreAction>(
            key: const ValueKey('driver_more_menu'),
            tooltip: l10n.driverMoreActionsTooltip,
            onSelected: (action) => _onMoreAction(action, driverId),
            itemBuilder: (context) => [
              _moreItem(_DriverMoreAction.stats, Icons.bar_chart, l10n.driverStatsTitle, enabled: driverId != null),
              const PopupMenuDivider(),
              _moreItem(_DriverMoreAction.language, Icons.translate, l10n.languageToggleTooltip),
              _moreItem(_DriverMoreAction.signOut, Icons.logout, l10n.signOutTooltip),
            ],
          ),
        ],
      ),
      // One scroll for the whole screen: the active delivery (full height,
      // when there is one) comes first and the queue follows it as more
      // slivers of the same scroll — never a nested list squeezed into
      // whatever viewport space the card leaves over.
      body: ResponsiveCenter(
        child: CustomScrollView(
          slivers: [
            if (activeOrder != null)
              SliverPadding(
                padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.sm, AppSpacing.sm, AppSpacing.sm, 0),
                sliver: SliverToBoxAdapter(
                  child: _buildActiveDeliveryCard(
                    context,
                    activeOrder,
                    // The driver's own last published GPS fix (same pipeline
                    // that feeds the customer's map) — no second GPS stream.
                    recentDriverPosition(driverSelf?.lastKnownLocation, DateTime.now()),
                  ),
                ),
              )
            else if (activeAsync != null && activeAsync.hasError && !activeAsync.isLoading)
              // Reading the active delivery failed: say so (with a retry)
              // rather than silently showing no delivery.
              SliverToBoxAdapter(
                key: const ValueKey('driver_active_error'),
                child: ErrorState(
                  error: activeAsync.error!,
                  onRetry: () => ref.invalidate(activeDriverOrderProvider(driverId!)),
                ),
              ),
            if (driverSelfAsync == null || driverSelf == null)
              (driverSelfAsync?.hasError ?? false)
                  ? _statusSliver(ErrorState(
                      key: const ValueKey('driver_self_error'),
                      error: driverSelfAsync!.error!,
                      onRetry: () => ref.invalidate(driverSelfProvider(driverId!)),
                    ))
                  : const _SkeletonSliver()
            else if (!isApproved)
              _statusSliver(_DriverStatusView.approval(driverSelf.approvalStatus))
            else if (isOnline)
              _buildAvailableOrders(context)
            else
              _statusSliver(const _DriverStatusView.offline()),
          ],
        ),
      ),
    );
  }

  // Fills the rest of the viewport below the active card (or the whole
  // viewport without one), and grows past it when its content needs more.
  static Widget _statusSliver(Widget child) => SliverFillRemaining(hasScrollBody: false, child: child);

  // The unclaimed readyForPickup queue. Only built (and so only queried) for
  // an approved driver — firestore.rules denies the query to anyone else.
  Widget _buildAvailableOrders(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ref.watch(availableOrdersProvider).when(
          data: (orders) {
            if (orders.isEmpty) {
              return _statusSliver(
                EmptyState(icon: Icons.delivery_dining_outlined, message: l10n.noDeliveriesMessage),
              );
            }
            return SliverPadding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              sliver: SliverList.builder(
                itemCount: orders.length,
                itemBuilder: (context, index) {
                  final order = orders[index];
                  return DriverAvailableOrderCard(
                    key: ValueKey('driver_queue_${order.id}'),
                    order: order,
                    isAccepting: _acceptingOrderIds.contains(order.id),
                    onAccept: () => _accept(order),
                  ).staggeredEntrance(index);
                },
              ),
            );
          },
          loading: () => const _SkeletonSliver(),
          error: (error, _) => _statusSliver(ErrorState(
            key: const ValueKey('driver_queue_error'),
            error: error,
            onRetry: () => ref.invalidate(availableOrdersProvider),
          )),
        );
  }
}

enum _DriverMoreAction { stats, language, signOut }

PopupMenuItem<_DriverMoreAction> _moreItem(
  _DriverMoreAction action,
  IconData icon,
  String label, {
  bool enabled = true,
}) {
  return PopupMenuItem(
    value: action,
    enabled: enabled,
    child: Row(
      children: [
        Icon(icon, size: AppSizes.iconLarge),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: Text(label)),
      ],
    ),
  );
}

/// Loading placeholder for the area below the active card. The skeleton is
/// its own (non-interactive) list, so it takes whatever viewport space is
/// left rather than adding scroll extent.
class _SkeletonSliver extends StatelessWidget {
  const _SkeletonSliver();

  @override
  Widget build(BuildContext context) => const SliverFillRemaining(child: ListSkeletonLoader());
}

enum _DriverStatusKind { pending, rejected, offline }

/// Shown instead of the delivery queue when the driver can't take new work:
/// not approved yet, rejected, or switched offline. The AppBar already
/// names the state, so this is the shared [EmptyState] with the
/// explanation (and, for approval, the status badge).
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
    return switch (kind) {
      _DriverStatusKind.pending => EmptyState(
          key: const ValueKey('driver_approval_pending'),
          icon: Icons.hourglass_top_outlined,
          message: l10n.driverPendingApprovalMessage,
          action: const ApprovalStatusBadge(status: ApprovalStatus.pending),
        ),
      _DriverStatusKind.rejected => EmptyState(
          key: const ValueKey('driver_approval_rejected'),
          icon: Icons.block_outlined,
          message: l10n.driverRejectedMessage,
          action: const ApprovalStatusBadge(status: ApprovalStatus.rejected),
        ),
      _DriverStatusKind.offline => EmptyState(
          key: const ValueKey('driver_offline'),
          icon: Icons.power_settings_new,
          message: l10n.driverOfflineMessage,
        ),
    };
  }
}
