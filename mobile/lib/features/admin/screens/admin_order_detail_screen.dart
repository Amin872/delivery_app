import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/l10n/enum_labels.dart';
import '../../../core/providers/formatters_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/animated_async.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/app_spinner.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/language_toggle_button.dart';
import '../../../core/widgets/responsive_center.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/app_user.dart';
import '../../../models/driver.dart';
import '../../../models/order.dart';
import '../../../models/vendor.dart';
import '../../customer/screens/customer_home_screen.dart' show firestoreServiceProvider;
import '../../driver/screens/driver_home_screen.dart' show functionsServiceProvider;
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
    final selected = await showModalBottomSheet<_DriverOption>(
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
                  Row(
                    children: [
                      _StatusChip(status: order.status),
                      const Spacer(),
                      Text(
                        dateFormat.format(order.createdAt),
                        style: const TextStyle(color: VendorPalette.textSecondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _InfoCard(children: [
                    _InfoRow(label: l10n.totalLabel, value: currencyFormat.format(order.total)),
                    _InfoRow(label: l10n.deliveryAddressLabel, value: order.deliveryAddress),
                  ]),
                  const SizedBox(height: AppSpacing.md),
                  _InfoCard(children: [
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
                  const SizedBox(height: AppSpacing.lg),
                  Text(l10n.itemsLabel, style: vendorTheme.textTheme.titleSmall),
                  const SizedBox(height: AppSpacing.sm),
                  _InfoCard(
                    children: [
                      for (final item in order.items)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                          child: Row(
                            children: [
                              Expanded(child: Text('${item.quantity}× ${item.name}')),
                              Text(currencyFormat.format(item.unitPrice * item.quantity)),
                            ],
                          ),
                        ),
                    ],
                  ),
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
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = switch (status) {
      OrderStatus.delivered => AppColors.success(colorScheme),
      OrderStatus.cancelled => colorScheme.error,
      _ => VendorPalette.primaryCyan,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: AppRadius.pill),
      child: Text(
        orderStatusLabel(context, status),
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: VendorPalette.surfaceContainer,
        borderRadius: AppRadius.large,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: VendorPalette.textSecondary)),
          const Spacer(),
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

class _DriverOption {
  const _DriverOption({required this.driverId, required this.name, required this.isAvailable});

  final String driverId;
  final String name;
  final bool isAvailable;
}

/// Bottom sheet listing every driver account, joined from `drivers`
/// (availability) and `users` (identity, filtered to `role == driver`) —
/// see [FirestoreService.watchAllDrivers]'s doc comment for why the join is
/// client-side rather than a new denormalized field. [currentDriverId] is
/// accepted for future use (e.g. highlighting who's currently assigned) but
/// doesn't filter the list — reassigning to the same driver is harmless.
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
      final driversById = {for (final driver in driversAsync.value!) driver.id: driver};
      final options = usersAsync.value!
          .where((user) => user.role == UserRole.driver && driversById.containsKey(user.id))
          .map((user) => _DriverOption(
                driverId: user.id,
                name: user.displayName,
                isAvailable: driversById[user.id]!.isAvailable,
              ))
          .toList()
        ..sort((a, b) => b.isAvailable == a.isAvailable ? 0 : (b.isAvailable ? 1 : -1));

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
    final colorScheme = Theme.of(context).colorScheme;
    final color = isAvailable ? AppColors.success(colorScheme) : VendorPalette.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: AppRadius.pill),
      child: Text(
        isAvailable ? l10n.driverAvailableStatusLabel : l10n.driverUnavailableStatusLabel,
        style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }
}
