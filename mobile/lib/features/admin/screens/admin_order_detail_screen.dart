import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/providers/formatters_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../core/widgets/animated_async.dart';
import '../../../core/widgets/app_network_image.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/app_spinner.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/language_toggle_button.dart';
import '../../../core/widgets/responsive_center.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/app_user.dart';
import '../../../models/approval_status.dart';
import '../../../models/driver.dart';
import '../../../models/order.dart';
import '../../../models/vendor.dart';
import '../../customer/screens/customer_home_screen.dart' show firestoreServiceProvider;
import '../../customer/widgets/price_breakdown.dart';
import '../../driver/screens/driver_home_screen.dart' show functionsServiceProvider;
import 'admin_drivers_screen.dart' show DriverRow, buildDriverRows;
import 'admin_users_screen.dart' show allUsersProvider;

final _orderProvider = StreamProvider.autoDispose.family<DeliveryOrder, String>((ref, orderId) {
  return ref.watch(firestoreServiceProvider).watchOrder(orderId);
});

final _userProvider = StreamProvider.autoDispose.family<AppUser, String>((ref, userId) {
  return ref.watch(firestoreServiceProvider).watchUser(userId);
});

final _vendorProvider = StreamProvider.autoDispose.family<Vendor, String>((ref, vendorId) {
  return ref.watch(firestoreServiceProvider).watchVendor(vendorId);
});

final _allDriversProvider = StreamProvider.autoDispose<List<Driver>>((ref) {
  return ref.watch(firestoreServiceProvider).watchAllDrivers();
});

// Mirrors ADMIN_CANCELLABLE_STATUSES / ADMIN_REASSIGNABLE_STATUSES in
// functions/src/orders.ts — the Cloud Function transaction is the actual
// enforcement point (see assertAdminCancellable/assertAdminReassignable
// there), this only controls which action this screen offers, so a stale
// button never does more than surface the same failed-precondition error
// the callable would throw anyway.
const _adminCancellableStatuses = {
  OrderStatus.pending,
  OrderStatus.accepted,
  OrderStatus.preparing,
  OrderStatus.readyForPickup,
};

const _adminReassignableStatuses = {
  OrderStatus.readyForPickup,
  OrderStatus.driverAssigned,
  OrderStatus.pickedUp,
};

/// Richer, admin-only order view — unlike the customer-facing
/// [OrderTrackingScreen] this reuses as its visual template, it adds two
/// interventions (force-cancel, reassign driver) gated by order status and
/// backed by the `adminCancelOrder`/`adminReassignDriver` callables.
class AdminOrderDetailScreen extends ConsumerStatefulWidget {
  const AdminOrderDetailScreen({required this.orderId, super.key});

  final String orderId;

  @override
  ConsumerState<AdminOrderDetailScreen> createState() => _AdminOrderDetailScreenState();
}

class _AdminOrderDetailScreenState extends ConsumerState<AdminOrderDetailScreen> {
  bool _cancelling = false;
  bool _reassigning = false;

  Future<void> _confirmCancel(DeliveryOrder order) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.cancelOrderButton,
      message: l10n.cancelOrderConfirmMessage,
      isDestructive: true,
    );
    if (confirmed != true || !mounted) return;

    HapticFeedback.lightImpact();
    setState(() => _cancelling = true);
    final messenger = ScaffoldMessenger.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    try {
      await ref.read(functionsServiceProvider).adminCancelOrder(order.id);
      if (mounted) {
        messenger.showSnackBar(buildAppSnackBar(colorScheme, l10n.orderCancelledMessage));
      }
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(
          buildAppSnackBar(colorScheme, localizedErrorMessage(context, error), isError: true),
        );
      }
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  Future<void> _pickAndReassignDriver(DeliveryOrder order) async {
    final selected = await showModalBottomSheet<DriverRow>(
      context: context,
      backgroundColor: VendorPalette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.largeValue)),
      ),
      isScrollControlled: true,
      builder: (context) => _DriverPickerSheet(currentDriverId: order.driverId),
    );
    if (selected == null || !mounted) return;

    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.reassignDriverButton,
      message: l10n.confirmReassignMessage(selected.name),
    );
    if (confirmed != true || !mounted) return;

    HapticFeedback.lightImpact();
    setState(() => _reassigning = true);
    final messenger = ScaffoldMessenger.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    try {
      await ref.read(functionsServiceProvider).adminReassignDriver(order.id, selected.driverId);
      if (mounted) {
        messenger.showSnackBar(buildAppSnackBar(colorScheme, l10n.orderReassignedMessage));
      }
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(
          buildAppSnackBar(colorScheme, localizedErrorMessage(context, error), isError: true),
        );
      }
    } finally {
      if (mounted) setState(() => _reassigning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final orderAsync = ref.watch(_orderProvider(widget.orderId));
    final currencyFormat = ref.watch(currencyFormatProvider);
    final dateFormat = ref.watch(dateTimeFormatProvider);
    final vendorTheme = VendorPalette.themeFrom(Theme.of(context));

    return Theme(
      data: vendorTheme,
      child: Scaffold(
        backgroundColor: VendorPalette.background,
        appBar: AppBar(
          backgroundColor: VendorPalette.background,
          foregroundColor: VendorPalette.textPrimary,
          title: Text(l10n.orderLabel(widget.orderId)),
          actions: const [LanguageToggleButton()],
        ),
        body: ResponsiveCenter(
          child: orderAsync.animatedWhen(
            data: (order) {
              final colorScheme = vendorTheme.colorScheme;
              final canCancel = _adminCancellableStatuses.contains(order.status);
              final canReassign = _adminReassignableStatuses.contains(order.status);
              return ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  // Wraps onto two lines when the chip and date don't fit side
                  // by side (narrow screens, large text).
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      _StatusChip(status: order.status),
                      Text(
                        dateFormat.format(order.createdAt),
                        style: const TextStyle(color: VendorPalette.textSecondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  InfoCard(children: [
                    ref.watch(_userProvider(order.customerId)).animatedWhen(
                          data: (customer) =>
                              _InfoRow(label: l10n.customerLabel, value: customer.displayName),
                          loading: () => _InfoRow(label: l10n.customerLabel, value: l10n.loadingLabel),
                          error: (_, __) => _InfoRow(label: l10n.customerLabel, value: order.customerId),
                        ),
                    ref.watch(_vendorProvider(order.vendorId)).animatedWhen(
                          data: (vendor) => _InfoRow(label: l10n.vendorLabel, value: vendor.name),
                          loading: () => _InfoRow(label: l10n.vendorLabel, value: l10n.loadingLabel),
                          error: (_, __) => _InfoRow(label: l10n.vendorLabel, value: order.vendorId),
                        ),
                    order.driverId == null
                        ? _InfoRow(
                            label: l10n.assignedDriverLabel, value: l10n.noDriverAssignedMessage)
                        : ref.watch(_userProvider(order.driverId!)).animatedWhen(
                              data: (driver) => _InfoRow(
                                  label: l10n.assignedDriverLabel, value: driver.displayName),
                              loading: () =>
                                  _InfoRow(label: l10n.assignedDriverLabel, value: l10n.loadingLabel),
                              error: (_, __) => _InfoRow(
                                  label: l10n.assignedDriverLabel, value: order.driverId!),
                            ),
                  ]),
                  _SectionTitle(l10n.itemsLabel),
                  InfoCard(
                    key: const ValueKey('admin_order_items'),
                    children: [
                      // Same line layout as VendorOrderDetailScreen: name,
                      // "quantity × unit price", line total.
                      for (final item in order.items)
                        Semantics(
                          // Spelled out for screen readers instead of "2 × 5,000".
                          label: '${item.name}, ${l10n.quantityLabel} ${item.quantity}, '
                              '${l10n.unitPriceLabel} ${currencyFormat.format(item.unitPrice)}, '
                              '${currencyFormat.format(item.unitPrice * item.quantity)}',
                          excludeSemantics: true,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.name,
                                        style: const TextStyle(
                                          color: VendorPalette.textPrimary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        l10n.orderItemQuantityPrice(
                                          item.quantity,
                                          currencyFormat.format(item.unitPrice),
                                        ),
                                        style: const TextStyle(color: VendorPalette.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Flexible(
                                  child: Text(
                                    currencyFormat.format(item.unitPrice * item.quantity),
                                    textAlign: TextAlign.end,
                                    style: const TextStyle(color: VendorPalette.textPrimary),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (order.items.isNotEmpty) const Divider(color: VendorPalette.divider),
                      // effective* fall back for orders placed before the
                      // breakdown existed (their total was the item
                      // subtotal, with no fee).
                      PriceBreakdown(
                        subtotal: order.effectiveSubtotal,
                        deliveryFee: order.effectiveDeliveryFee,
                        total: order.total,
                        rowPadding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                      ),
                    ],
                  ),
                  if (_hasText(order.vendorName) || _hasText(order.pickupAddress)) ...[
                    // The pickup snapshot taken when the order was placed —
                    // only the store name and address, nothing about the owner.
                    _SectionTitle(l10n.pickupLocationTitle),
                    InfoCard(key: const ValueKey('admin_order_pickup'), children: [
                      if (_hasText(order.vendorName))
                        _InfoRow(label: l10n.vendorLabel, value: order.vendorName!.trim()),
                      if (_hasText(order.pickupAddress))
                        _InfoRow(label: l10n.pickupAddressFieldLabel, value: order.pickupAddress!.trim()),
                    ]),
                  ],
                  _SectionTitle(l10n.deliveryTitle),
                  InfoCard(key: const ValueKey('admin_order_delivery'), children: [
                    _InfoRow(label: l10n.deliveryAddressLabel, value: order.deliveryAddress),
                    // Coordinates as data only — the admin area has no map.
                    if (order.deliveryCoordinates != null)
                      _InfoRow(
                        label: l10n.deliveryLocationLabel,
                        value: '${order.deliveryCoordinates!.latitude.toStringAsFixed(5)}, '
                            '${order.deliveryCoordinates!.longitude.toStringAsFixed(5)}',
                      ),
                    if (_hasText(order.deliveryInstructions))
                      _InfoRow(
                        label: l10n.orderDeliveryInstructionsLabel,
                        value: order.deliveryInstructions!.trim(),
                      ),
                    if (_hasText(order.driverNote))
                      _InfoRow(label: l10n.orderDriverNoteLabel, value: order.driverNote!.trim()),
                  ]),
                  if (_hasText(order.proofImageUrl)) ...[
                    _SectionTitle(l10n.proofOfDeliveryLabel),
                    AppNetworkImage(
                      key: const ValueKey('admin_order_proof'),
                      imageUrl: order.proofImageUrl!,
                      height: 200,
                      borderRadius: AppRadius.large,
                    ),
                  ],
                  if (canCancel || canReassign) ...[
                    const SizedBox(height: AppSpacing.xl),
                    if (canReassign)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: OutlinedButton.icon(
                          onPressed: _reassigning ? null : () => _pickAndReassignDriver(order),
                          icon: _reassigning
                              ? buttonSpinner(colorScheme.primary, size: 16)
                              : const Icon(Icons.sync_alt),
                          label: Text(l10n.reassignDriverButton),
                        ),
                      ),
                    if (canCancel)
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: colorScheme.error),
                        onPressed: _cancelling ? null : () => _confirmCancel(order),
                        icon: _cancelling
                            ? buttonSpinner(colorScheme.error, size: 16)
                            : const Icon(Icons.cancel_outlined),
                        label: Text(l10n.cancelOrderButton),
                      ),
                  ],
                ],
              );
            },
            loading: () => const ListSkeletonLoader(),
            error: (error, _) => Center(
              child: Text(
                localizedErrorMessage(context, error),
                style: const TextStyle(color: VendorPalette.textSecondary),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final OrderStatus status;

  @override
  Widget build(BuildContext context) => OrderStatusChip(status: status);
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      // Label and value both wrap rather than overflow on a narrow screen.
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(child: Text(label, style: const TextStyle(color: VendorPalette.textSecondary))),
          const SizedBox(width: AppSpacing.md),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(color: VendorPalette.textPrimary, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Drivers an admin may reassign an order to: approved driver accounts only
/// (the adminReassignDriver callable rejects anyone else), available
/// drivers first. Reuses [buildDriverRows]'s drivers/users join; pending,
/// rejected, and legacy drivers with no approvalStatus (which parse as
/// pending) are left out.
List<DriverRow> reassignmentCandidates(List<Driver> drivers, List<AppUser> users) {
  return buildDriverRows(drivers, users)
      .where((row) => row.approvalStatus == ApprovalStatus.approved)
      .toList()
    ..sort((a, b) => b.isAvailable == a.isAvailable ? 0 : (b.isAvailable ? 1 : -1));
}

/// Bottom sheet listing the drivers an order can be reassigned to (see
/// [reassignmentCandidates]), joined from `drivers` (availability/approval)
/// and `users` (identity) — see [FirestoreService.watchAllDrivers]'s doc
/// comment for why the join is client-side rather than a new denormalized
/// field. [currentDriverId] is accepted for future use (e.g. highlighting
/// who's currently assigned) but doesn't filter the list — reassigning to
/// the same driver is harmless.
class _DriverPickerSheet extends ConsumerWidget {
  const _DriverPickerSheet({this.currentDriverId});

  final String? currentDriverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final driversAsync = ref.watch(_allDriversProvider);
    final usersAsync = ref.watch(allUsersProvider);

    Widget body;
    if (driversAsync.isLoading || usersAsync.isLoading) {
      body = SizedBox(
        height: 160,
        child: Center(child: screenSpinner(context)),
      );
    } else if (driversAsync.hasError) {
      body = Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Text(localizedErrorMessage(context, driversAsync.error!)),
      );
    } else if (usersAsync.hasError) {
      body = Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Text(localizedErrorMessage(context, usersAsync.error!)),
      );
    } else {
      final options = reassignmentCandidates(driversAsync.value!, usersAsync.value!);

      body = options.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(AppSpacing.xxxl),
              child: Center(child: Text(l10n.noDriversFoundMessage)),
            )
          : Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: VendorPalette.surfaceElevated,
                      child: Text(
                        option.name.isNotEmpty ? option.name[0].toUpperCase() : '?',
                        style: const TextStyle(color: VendorPalette.textPrimary),
                      ),
                    ),
                    title: Text(option.name),
                    trailing: _AvailabilityBadge(isAvailable: option.isAvailable),
                    onTap: () => Navigator.of(context).pop(option),
                  );
                },
              ),
            );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Text(l10n.selectDriverTitle, style: Theme.of(context).textTheme.titleMedium),
            ),
            const SizedBox(height: AppSpacing.sm),
            body,
          ],
        ),
      ),
    );
  }
}

class _AvailabilityBadge extends StatelessWidget {
  const _AvailabilityBadge({required this.isAvailable});

  final bool isAvailable;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return StatusBadge(
      label: isAvailable ? l10n.driverAvailableStatusLabel : l10n.driverUnavailableStatusLabel,
      tone: isAvailable ? StatusTone.success : StatusTone.neutral,
    );
  }
}

bool _hasText(String? value) => value != null && value.trim().isNotEmpty;

/// Heading above one of the detail cards, with the spacing that separates
/// the sections.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.sm),
      child: Semantics(
        header: true,
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      ),
    );
  }
}
