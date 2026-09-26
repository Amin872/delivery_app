import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/contact/phone_launcher.dart';
import '../../../core/format/display_formatters.dart';
import '../../../core/providers/formatters_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/adaptive_label_value.dart';
import '../../../core/widgets/animated_async.dart';
import '../../../core/widgets/app_spinner.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/responsive_center.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/order.dart';
import '../../../services/functions_service.dart' show ContactTarget;
import '../../driver/screens/driver_home_screen.dart' show functionsServiceProvider;
import '../widgets/vendor_order_actions.dart';
import 'vendor_dashboard_screen.dart' show vendorOrdersProvider;

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
      appBar: AppBar(
        title: Text(l10n.orderDetailsTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: ResponsiveCenter(
        child: ordersAsync.animatedWhen(
          data: (orders) {
            final order = orders.where((o) => o.id == orderId).firstOrNull;
            if (order == null) {
              return EmptyState(icon: Icons.receipt_long_outlined, message: l10n.orderNotFoundMessage);
            }
            return _OrderDetailBody(order: order);
          },
          loading: () => const ListSkeletonLoader(),
          error: (error, _) => ErrorState(error: error),
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
    final secondary = AppColors.textSecondary(Theme.of(context).colorScheme);
    final currencyFormat = ref.watch(currencyFormatProvider);
    final dateFormat = ref.watch(dateTimeFormatProvider);
    final hasCoordinates = order.deliveryLatitude != null && order.deliveryLongitude != null;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        // The chip drops under the reference when both don't fit.
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            Text(l10n.orderLabel(displayOrderId(order.id)), style: textTheme.titleLarge),
            OrderStatusChip(status: order.status),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        InfoCard(children: [
          _DetailField(label: l10n.orderPlacedAtLabel, value: dateFormat.format(order.createdAt)),
        ]),
        _SectionTitle(l10n.orderItemsTitle),
        InfoCard(children: [
          for (final item in order.items)
            Semantics(
              // Spelled out for screen readers instead of "2 × 5,000".
              label: '${item.name}, ${l10n.quantityLabel} ${item.quantity}, '
                  '${l10n.unitPriceLabel} ${currencyFormat.format(item.unitPrice)}, '
                  '${currencyFormat.format(item.unitPrice * item.quantity)}',
              excludeSemantics: true,
              // The name gets the full width; "quantity × unit price" and the
              // line total share the next line when they fit, and the total
              // moves under it when they don't (large amounts, 1.3x text).
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(item.name, style: textTheme.titleSmall),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: AppSpacing.md,
                      children: [
                        Text(
                          l10n.orderItemQuantityPrice(item.quantity, currencyFormat.format(item.unitPrice)),
                          style: textTheme.bodySmall?.copyWith(color: secondary),
                        ),
                        Text(currencyFormat.format(item.unitPrice * item.quantity), style: textTheme.bodyMedium),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ]),
        const SizedBox(height: AppSpacing.md),
        InfoCard(children: [
          // effective* fall back for orders placed before the breakdown
          // existed (their total was the item subtotal, with no fee).
          _AmountRow(label: l10n.subtotalLabel, amount: currencyFormat.format(order.effectiveSubtotal)),
          _AmountRow(label: l10n.deliveryFeeLabel, amount: currencyFormat.format(order.effectiveDeliveryFee)),
          const Divider(height: AppSpacing.lg),
          _AmountRow(label: l10n.totalLabel, amount: currencyFormat.format(order.total), emphasized: true),
        ]),
        _SectionTitle(l10n.deliveryTitle),
        InfoCard(children: [
          _DetailField(label: l10n.deliveryAddressLabel, value: order.deliveryAddress),
          if (hasCoordinates)
            _DetailField(
              label: l10n.deliveryLocationLabel,
              value: formatCoordinates(order.deliveryLatitude!, order.deliveryLongitude!),
            ),
          if (order.deliveryInstructions?.isNotEmpty ?? false)
            _DetailField(label: l10n.orderDeliveryInstructionsLabel, value: order.deliveryInstructions!),
          if (order.driverNote?.isNotEmpty ?? false)
            _DetailField(label: l10n.orderDriverNoteLabel, value: order.driverNote!),
        ]),
        // Phone numbers come only from the getOrderContact callable (the
        // server re-checks ownership and status); nothing here reads
        // another user's document.
        if (vendorCanCallCustomer(order) || vendorCanCallDriver(order)) ...[
          const SizedBox(height: AppSpacing.md),
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
        const SizedBox(height: AppSpacing.lg),
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
            ? buttonSpinner(Theme.of(context).colorScheme.primary, size: AppSizes.iconSmall)
            : const Icon(Icons.call_outlined),
        label: Text(label),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: AppSpacing.xl, bottom: AppSpacing.sm),
      child: Semantics(
        header: true,
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      ),
    );
  }
}

/// A label above its value — for free text (addresses, notes) that must
/// wrap in full rather than share a line with its label.
class _DetailField extends StatelessWidget {
  const _DetailField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary(Theme.of(context).colorScheme)),
          ),
          Text(value, style: textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// A price-breakdown line: label and amount side by side when they fit,
/// stacked otherwise — the amount is never wrapped or cut.
class _AmountRow extends StatelessWidget {
  const _AmountRow({required this.label, required this.amount, this.emphasized = false});

  final String label;
  final String amount;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: AdaptiveLabelValue(
        label: label,
        value: amount,
        style: emphasized ? textTheme.titleMedium : textTheme.bodyMedium,
      ),
    );
  }
}
