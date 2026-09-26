import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/l10n/enum_labels.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/app_spinner.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/order.dart';
import '../../customer/screens/customer_home_screen.dart'
    show firestoreServiceProvider;

// The vendor's order status machine — the single place both the dashboard
// list and VendorOrderDetailScreen take it from. Must match
// firestore.rules' isVendorStatusTransition exactly: anything past
// readyForPickup belongs to the acceptDelivery/advanceDelivery/admin
// callables, so the vendor is offered no action beyond that point.
OrderStatus? nextVendorStatus(OrderStatus current) {
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
bool vendorCanCancel(OrderStatus status) {
  return status == OrderStatus.pending ||
      status == OrderStatus.accepted ||
      status == OrderStatus.preparing;
}

// The dashboard's Active/Completed split: only the two terminal statuses
// count as completed (the same split as the customer's order lists), so an
// order stays under Active while it is still on its way to the customer.
bool isActiveVendorOrder(OrderStatus status) {
  return status != OrderStatus.delivered && status != OrderStatus.cancelled;
}

/// The vendor's advance/cancel actions for one order. [compact] renders a
/// single row (cancel icon + advance button) for a vendor order card;
/// otherwise stacked full-width buttons for the detail screen. While either
/// action is in flight both are disabled, so a double tap can't send a
/// second write.
/// Renders nothing when the order has no vendor action left.
class VendorOrderActions extends ConsumerStatefulWidget {
  const VendorOrderActions({
    required this.order,
    this.compact = false,
    super.key,
  });

  final DeliveryOrder order;
  final bool compact;

  @override
  ConsumerState<VendorOrderActions> createState() => _VendorOrderActionsState();
}

class _VendorOrderActionsState extends ConsumerState<VendorOrderActions> {
  bool _advancing = false;
  bool _cancelling = false;

  bool get _busy => _advancing || _cancelling;

  Future<void> _advance(OrderStatus next) async {
    if (_busy) return;
    HapticFeedback.lightImpact();
    setState(() => _advancing = true);
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    try {
      await ref
          .read(firestoreServiceProvider)
          .updateOrderStatus(widget.order.id, next);
    } catch (_) {
      messenger.showSnackBar(
        buildAppSnackBar(
          colorScheme,
          l10n.orderStatusUpdateFailedMessage,
          isError: true,
        ),
      );
    } finally {
      if (mounted) setState(() => _advancing = false);
    }
  }

  Future<void> _cancel() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      message: l10n.cancelOrderConfirmMessage,
    );
    if (confirmed != true) return;
    if (!mounted) return;

    HapticFeedback.lightImpact();
    setState(() => _cancelling = true);
    final messenger = ScaffoldMessenger.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    try {
      await ref.read(firestoreServiceProvider).cancelOrder(widget.order.id);
      messenger.showSnackBar(
        buildAppSnackBar(colorScheme, l10n.orderCancelledMessage),
      );
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(
          buildAppSnackBar(
            colorScheme,
            localizedErrorMessage(context, error),
            isError: true,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final next = nextVendorStatus(widget.order.status);
    final canCancel = vendorCanCancel(widget.order.status);
    if (next == null && !canCancel) return const SizedBox.shrink();

    final advanceLabel = next == null
        ? null
        : l10n.advanceStatusButtonLabel(orderStatusLabel(context, next));

    if (widget.compact) {
      // Needs a bounded width (a card, not a ListTile trailing slot): the
      // advance button takes all the room the cancel icon leaves, and its
      // label may wrap to a second line rather than being cut off.
      return Row(
        children: [
          if (canCancel)
            IconButton(
              icon: _cancelling
                  ? buttonSpinner(colorScheme.error, size: AppSizes.iconSmall)
                  : const Icon(Icons.cancel_outlined),
              tooltip: l10n.cancelOrderButton,
              color: colorScheme.error,
              onPressed: _busy ? null : _cancel,
            ),
          if (next != null) ...[
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: FilledButton(
                onPressed: _busy ? null : () => _advance(next),
                child: _advancing
                    ? buttonSpinner(colorScheme.onPrimary, size: AppSizes.iconSmall)
                    : Text(advanceLabel!, maxLines: 2, textAlign: TextAlign.center),
              ),
            ),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (next != null)
          FilledButton(
            onPressed: _busy ? null : () => _advance(next),
            child: _advancing
                ? buttonSpinner(colorScheme.onPrimary, size: AppSizes.iconSmall)
                : Text(advanceLabel!),
          ),
        if (next != null && canCancel) const SizedBox(height: AppSpacing.sm),
        if (canCancel)
          OutlinedButton.icon(
            onPressed: _busy ? null : _cancel,
            style: OutlinedButton.styleFrom(foregroundColor: colorScheme.error),
            icon: _cancelling
                ? buttonSpinner(colorScheme.error, size: AppSizes.iconSmall)
                : const Icon(Icons.cancel_outlined),
            label: Text(l10n.cancelOrderButton),
          ),
      ],
    );
  }
}
