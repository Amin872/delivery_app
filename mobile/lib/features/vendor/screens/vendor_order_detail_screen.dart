import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/contact/phone_launcher.dart';
import '../../../core/l10n/enum_labels.dart';
import '../../../core/providers/formatters_provider.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/animated_async.dart';
import '../../../core/widgets/app_spinner.dart';
import '../../../core/widgets/responsive_center.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/order.dart';
import '../../../services/functions_service.dart' show ContactTarget;
import '../../driver/screens/driver_home_screen.dart' show functionsServiceProvider;
import '../widgets/vendor_order_actions.dart';
import 'vendor_dashboard_screen.dart' show vendorOrdersProvider;
import '../../../core/widgets/state_views.dart';

/// Everything a vendor needs to prepare one order: its items, the price
/// breakdown, and where it's going. Reads the order out of the same live
/// [vendorOrdersProvider] stream the dashboard list uses (no second
/// listener), so status changes made here or elsewhere show up immediately.
///
/// Shows no customer name or phone: orders carry no customer contact
/// snapshot, and a vendor can't read the customer's private users/{uid}
/// document.
class VendorOrderDetailScreen extends ConsumerWidget {
  const VendorOrderDetailScreen({
    required this.vendorId,
    required this.orderId,
    super.key,
  });

  final String vendorId;
  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final ordersAsync = ref.watch(vendorOrdersProvider(vendorId));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.orderDetailsTitle)),
      body: ResponsiveCenter(
        child: ordersAsync.animatedWhen(
          data: (orders) {
            final order = orders.where((o) => o.id == orderId).firstOrNull;
            if (order == null) {
              return Center(child: Text(l10n.orderNotFoundMessage));
            }
            return _OrderDetailBody(order: order);
          },
          loading: () => const ListSkeletonLoader(),
          error: (error, _) =>
              ErrorState(error: error),
        ),
      ),
    );
  }
}

class _OrderDetailBody extends ConsumerWidget {
  const _OrderDetailBody({required this.order});

  final DeliveryOrder order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final currencyFormat = ref.watch(currencyFormatProvider);
    final dateFormat = ref.watch(dateTimeFormatProvider);
    final hasCoordinates =
        order.deliveryLatitude != null && order.deliveryLongitude != null;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        _Section(
          title: l10n.orderLabel(order.id),
          children: [
            _InfoRow(
              label: l10n.orderStatusFieldLabel,
              value: orderStatusLabel(context, order.status),
            ),
            _InfoRow(
              label: l10n.orderPlacedAtLabel,
              value: dateFormat.format(order.createdAt),
            ),
          ],
        ),
        _Section(
          title: l10n.orderItemsTitle,
          children: [
            for (final item in order.items)
              Semantics(
                // Spelled out for screen readers instead of "2 × 5,000".
                label:
                    '${item.name}, ${l10n.quantityLabel} ${item.quantity}, '
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
                            Text(item.name, style: textTheme.titleSmall),
                            Text(
                              l10n.orderItemQuantityPrice(
                                item.quantity,
                                currencyFormat.format(item.unitPrice),
                              ),
                              style: textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      Text(
                        currencyFormat.format(item.unitPrice * item.quantity),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        _Section(
          children: [
            // effective* fall back for orders placed before the breakdown
            // existed (their total was the item subtotal, with no fee).
            _InfoRow(
              label: l10n.subtotalLabel,
              value: currencyFormat.format(order.effectiveSubtotal),
            ),
            _InfoRow(
              label: l10n.deliveryFeeLabel,
              value: currencyFormat.format(order.effectiveDeliveryFee),
            ),
            _InfoRow(
              label: l10n.totalLabel,
              value: currencyFormat.format(order.total),
              emphasized: true,
            ),
          ],
        ),
        _Section(
          title: l10n.deliveryTitle,
          children: [
            _InfoRow(
              label: l10n.deliveryAddressLabel,
              value: order.deliveryAddress,
            ),
            if (hasCoordinates)
              _InfoRow(
                label: l10n.deliveryLocationLabel,
                value:
                    '${order.deliveryLatitude!.toStringAsFixed(5)}, '
                    '${order.deliveryLongitude!.toStringAsFixed(5)}',
              ),
            if (order.deliveryInstructions?.isNotEmpty ?? false)
              _InfoRow(
                label: l10n.orderDeliveryInstructionsLabel,
                value: order.deliveryInstructions!,
              ),
            if (order.driverNote?.isNotEmpty ?? false)
              _InfoRow(
                label: l10n.orderDriverNoteLabel,
                value: order.driverNote!,
              ),
          ],
        ),
        // Phone numbers come only from the getOrderContact callable (the
        // server re-checks ownership and status); nothing here reads
        // another user's document.
        if (vendorCanCallCustomer(order) || vendorCanCallDriver(order))
          _Section(
            children: [
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  if (vendorCanCallCustomer(order))
                    _ContactButton(
                      key: const ValueKey('vendor_call_customer'),
                      orderId: order.id,
                      target: ContactTarget.customer,
                      label: l10n.callCustomerButton,
                    ),
                  if (vendorCanCallDriver(order))
                    _ContactButton(
                      key: const ValueKey('vendor_call_driver'),
                      orderId: order.id,
                      target: ContactTarget.driver,
                      label: l10n.callDriverButton,
                    ),
                ],
              ),
            ],
          ),
        const SizedBox(height: AppSpacing.sm),
        VendorOrderActions(order: order),
      ],
    );
  }
}

class _ContactButton extends ConsumerWidget {
  const _ContactButton({required this.orderId, required this.target, required this.label, super.key});

  final String orderId;
  final ContactTarget target;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PhoneCallAction(
      fetchPhone: () => ref.read(functionsServiceProvider).getOrderContact(orderId, target),
      builder: (context, onPressed, busy) => OutlinedButton.icon(
        onPressed: onPressed,
        icon: busy
            ? buttonSpinner(Theme.of(context).colorScheme.primary, size: 16)
            : const Icon(Icons.call_outlined),
        label: Text(label),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({this.title, required this.children});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Text(title!, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
            ],
            ...children,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final valueStyle = emphasized
        ? textTheme.titleMedium
        : textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: emphasized
                ? textTheme.titleMedium
                : textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(value, textAlign: TextAlign.end, style: valueStyle),
          ),
        ],
      ),
    );
  }
}
