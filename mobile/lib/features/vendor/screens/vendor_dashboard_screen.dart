import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/l10n/enum_labels.dart';
import '../../../core/providers/formatters_provider.dart';
import '../../../core/widgets/animated_async.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/app_spinner.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/language_toggle_button.dart';
import '../../../core/widgets/responsive_center.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/widgets/staggered_list_item.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/order.dart';
import '../../../routing/page_transitions.dart';
import '../../auth/providers/auth_provider.dart';
import '../../customer/screens/customer_home_screen.dart' show firestoreServiceProvider;
import 'menu_management_screen.dart' show MenuManagementScreen, storageServiceProvider;
import 'vendor_stats_screen.dart';

final vendorOrdersProvider =
    StreamProvider.autoDispose.family<List<DeliveryOrder>, String>((ref, vendorId) {
  return ref.watch(firestoreServiceProvider).watchVendorOrders(vendorId);
});

// Beyond `readyForPickup`, only the `acceptDelivery` callable (driver side)
// advances an order further — see the architecture note in CLAUDE.md — so
// the vendor is offered no action past that point.
OrderStatus? _nextVendorStatus(OrderStatus current) {
  switch (current) {
    case OrderStatus.pending:
      return OrderStatus.accepted;
    case OrderStatus.accepted:
      return OrderStatus.preparing;
    case OrderStatus.preparing:
      return OrderStatus.readyForPickup;
    default:
      return null;
  }
}

// A vendor can only cancel while the order is still theirs to fulfill —
// once it's readyForPickup a driver may already be browsing it, and once
// picked up it's out of the vendor's hands entirely.
bool _vendorCanCancel(OrderStatus status) {
  return status == OrderStatus.pending ||
      status == OrderStatus.accepted ||
      status == OrderStatus.preparing;
}

class VendorDashboardScreen extends ConsumerStatefulWidget {
  const VendorDashboardScreen({required this.vendorId, super.key});

  final String vendorId;

  @override
  ConsumerState<VendorDashboardScreen> createState() => _VendorDashboardScreenState();
}

class _VendorDashboardScreenState extends ConsumerState<VendorDashboardScreen> {
  final _cancellingOrderIds = <String>{};
  bool _uploadingStorefrontImage = false;

  Future<void> _changeStorefrontImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    if (!mounted) return;

    setState(() => _uploadingStorefrontImage = true);
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    try {
      final imageUrl = await ref
          .read(storageServiceProvider)
          .uploadVendorImage(widget.vendorId, File(picked.path), 'storefront.jpg');
      await ref.read(firestoreServiceProvider).updateVendorImage(widget.vendorId, imageUrl);
      messenger.showSnackBar(buildAppSnackBar(colorScheme, l10n.storefrontImageUpdatedMessage));
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(
          buildAppSnackBar(colorScheme, localizedErrorMessage(context, error), isError: true),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingStorefrontImage = false);
    }
  }

  Future<void> _confirmCancel(DeliveryOrder order) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(context, message: l10n.cancelOrderConfirmMessage);
    if (confirmed != true) return;
    if (!mounted) return;

    HapticFeedback.lightImpact();
    setState(() => _cancellingOrderIds.add(order.id));
    final messenger = ScaffoldMessenger.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    try {
      await ref.read(firestoreServiceProvider).cancelOrder(order.id);
      messenger.showSnackBar(buildAppSnackBar(colorScheme, l10n.orderCancelledMessage));
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(
          buildAppSnackBar(colorScheme, localizedErrorMessage(context, error), isError: true),
        );
      }
    } finally {
      if (mounted) setState(() => _cancellingOrderIds.remove(order.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final vendorId = widget.vendorId;
    final ordersAsync = ref.watch(vendorOrdersProvider(vendorId));
    final l10n = AppLocalizations.of(context)!;
    final currencyFormat = ref.watch(currencyFormatProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.incomingOrdersTitle),
        actions: [
          IconButton(
            icon: _uploadingStorefrontImage
                ? buttonSpinner(Theme.of(context).colorScheme.onSurface, size: 16)
                : const Icon(Icons.photo_camera_outlined),
            tooltip: l10n.changeStorefrontPhotoTooltip,
            onPressed: _uploadingStorefrontImage ? null : _changeStorefrontImage,
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: l10n.vendorStatsTitle,
            onPressed: () =>
                Navigator.of(context).push(fadeSlideRoute(VendorStatsScreen(vendorId: vendorId))),
          ),
          IconButton(
            icon: const Icon(Icons.restaurant_menu),
            tooltip: l10n.menuManagementTitle,
            onPressed: () => Navigator.of(context)
                .push(fadeSlideRoute(MenuManagementScreen(vendorId: vendorId))),
          ),
          const LanguageToggleButton(),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: l10n.signOutTooltip,
            onPressed: () => ref.read(authServiceProvider).signOut(),
          ),
        ],
      ),
      body: ResponsiveCenter(
        child: ordersAsync.animatedWhen(
          data: (orders) {
          if (orders.isEmpty) {
            return Center(child: Text(l10n.noOrdersMessage));
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final order = orders[index];
              final next = _nextVendorStatus(order.status);
              final isCancelling = _cancellingOrderIds.contains(order.id);
              return Card(
                child: ListTile(
                  title: Text(l10n.orderLabel(order.id)),
                  subtitle: Text(orderStatusLabel(context, order.status)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(currencyFormat.format(order.total)),
                      if (_vendorCanCancel(order.status))
                        IconButton(
                          icon: const Icon(Icons.cancel_outlined),
                          tooltip: l10n.cancelOrderButton,
                          color: Theme.of(context).colorScheme.error,
                          onPressed: isCancelling ? null : () => _confirmCancel(order),
                        ),
                      if (next != null) ...[
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            ref
                                .read(firestoreServiceProvider)
                                .updateOrderStatus(order.id, next);
                          },
                          child:
                              Text(l10n.advanceStatusButtonLabel(orderStatusLabel(context, next))),
                        ),
                      ],
                    ],
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
    );
  }
}
