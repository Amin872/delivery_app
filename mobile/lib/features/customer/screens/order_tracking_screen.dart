import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/contact/phone_launcher.dart';
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
import '../../../core/widgets/staggered_list_item.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/order.dart';
import '../../../models/review.dart';
import '../../../services/functions_service.dart' show ContactTarget;
import '../../auth/providers/auth_provider.dart';
import '../../driver/screens/driver_home_screen.dart' show functionsServiceProvider;
import '../widgets/driver_tracking_map.dart';
import '../widgets/price_breakdown.dart';
import '../widgets/rate_order_dialog.dart';
import 'customer_home_screen.dart' show firestoreServiceProvider;

final orderTrackingProvider =
    StreamProvider.autoDispose.family<DeliveryOrder, String>((ref, orderId) {
  return ref.watch(firestoreServiceProvider).watchOrder(orderId);
});

final reviewForOrderProvider = StreamProvider.autoDispose.family<Review?, String>((ref, orderId) {
  return ref.watch(firestoreServiceProvider).watchReviewForOrder(orderId);
});

// `cancelled` is shown as a standalone terminal state rather than a stage in
// this progression, since an order can be cancelled from any earlier status.
const _trackedStatuses = [
  OrderStatus.pending,
  OrderStatus.accepted,
  OrderStatus.preparing,
  OrderStatus.readyForPickup,
  OrderStatus.driverAssigned,
  OrderStatus.pickedUp,
  OrderStatus.delivering,
  OrderStatus.delivered,
];

class OrderTrackingScreen extends ConsumerStatefulWidget {
  const OrderTrackingScreen({required this.orderId, super.key});

  final String orderId;

  @override
  ConsumerState<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends ConsumerState<OrderTrackingScreen> {
  bool _cancelling = false;

  Future<void> _rateOrder(DeliveryOrder order) async {
    final submitted = await showDialog<bool>(
      context: context,
      builder: (_) => RateOrderDialog(order: order),
    );
    if (submitted == true && mounted) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        buildAppSnackBar(Theme.of(context).colorScheme, l10n.reviewSubmittedMessage),
      );
    }
  }

  Future<void> _confirmCancel(DeliveryOrder order) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(context, message: l10n.cancelOrderConfirmMessage);
    if (confirmed != true) return;
    if (!mounted) return;

    HapticFeedback.lightImpact();
    setState(() => _cancelling = true);
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
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final orderAsync = ref.watch(orderTrackingProvider(widget.orderId));
    final l10n = AppLocalizations.of(context)!;
    final vendorTheme = VendorPalette.themeFrom(Theme.of(context));

    return Theme(
      data: vendorTheme,
      child: Scaffold(
        backgroundColor: VendorPalette.background,
        appBar: AppBar(
          backgroundColor: VendorPalette.background,
          foregroundColor: VendorPalette.textPrimary,
          title: Text(l10n.orderTrackingTitle),
          actions: const [LanguageToggleButton()],
        ),
        body: ResponsiveCenter(
          child: orderAsync.animatedWhen(
            data: (order) {
          final currentIndex = order.status == OrderStatus.cancelled
              ? -1
              : _trackedStatuses.indexOf(order.status);
          final colorScheme = vendorTheme.colorScheme;
          // Live tracking only becomes visible to the customer once the
          // driver is actually en route (IN_DELIVERY / delivering) — not at
          // driverAssigned/pickedUp, when the driver is still stationary at
          // the vendor. See Phase 4 requirement #13.
          final showDriverMap = order.driverId != null && order.status == OrderStatus.delivering;
          final canCancel = order.status == OrderStatus.pending &&
              order.customerId == ref.watch(currentAppUserProvider).valueOrNull?.id;
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              if (showDriverMap)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: DriverTrackingMap(order: order),
                ),
              // The one customer → driver call action. Shown for the whole
              // server contact window (driverAssigned/pickedUp/delivering
              // with a driver), independent of the map and of whether a
              // driver position has arrived. The number comes only from
              // the getOrderContact callable, fetched on tap.
              if (customerCanCallDriver(order))
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: PhoneCallAction(
                    key: const ValueKey('customer_call_driver'),
                    fetchPhone: () => ref
                        .read(functionsServiceProvider)
                        .getOrderContact(order.id, ContactTarget.driver),
                    builder: (context, onPressed, busy) => OutlinedButton.icon(
                      onPressed: onPressed,
                      icon: busy
                          ? buttonSpinner(colorScheme.primary, size: 16)
                          : const Icon(Icons.call),
                      label: Text(l10n.callDriverButton),
                    ),
                  ),
                ),
              if (order.status == OrderStatus.cancelled)
                ListTile(
                  leading: Icon(Icons.cancel, color: colorScheme.error),
                  title: Text(orderStatusLabel(context, OrderStatus.cancelled)),
                )
              else
                for (var i = 0; i < _trackedStatuses.length; i++)
                  IntrinsicHeight(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Column(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: i <= currentIndex
                                      ? colorScheme.primary
                                      : colorScheme.surfaceContainerHighest,
                                  shape: BoxShape.circle,
                                ),
                                child: i <= currentIndex
                                    ? Icon(Icons.check, color: colorScheme.onPrimary, size: 18)
                                    : Icon(Icons.circle, color: colorScheme.outline, size: 8),
                              ),
                              if (i != _trackedStatuses.length - 1)
                                Expanded(
                                  child: Container(
                                    width: 2,
                                    color: i < currentIndex
                                        ? colorScheme.primary
                                        : colorScheme.outlineVariant,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 6, bottom: 20),
                              child: Text(
                                orderStatusLabel(context, _trackedStatuses[i]),
                                style: i == currentIndex
                                    ? const TextStyle(fontWeight: FontWeight.bold)
                                    : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ).staggeredEntrance(i),
              const Divider(),
              _OrderSummary(order: order),
              Card(
                child: ListTile(
                  title: Text(l10n.deliveryAddressLabel),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(order.deliveryAddress),
                      if (order.deliveryInstructions?.trim().isNotEmpty ?? false)
                        _LabeledLine(
                          label: l10n.orderDeliveryInstructionsLabel,
                          value: order.deliveryInstructions!.trim(),
                        ),
                      if (order.driverNote?.trim().isNotEmpty ?? false)
                        _LabeledLine(
                          label: l10n.orderDriverNoteLabel,
                          value: order.driverNote!.trim(),
                        ),
                    ],
                  ),
                ),
              ),
              if (order.proofImageUrl != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.proofOfDeliveryLabel, style: vendorTheme.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: AppRadius.medium,
                        child: Image.network(order.proofImageUrl!, height: 200, fit: BoxFit.cover),
                      ),
                    ],
                  ),
                ),
              if (order.status == OrderStatus.delivered)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ref.watch(reviewForOrderProvider(order.id)).animatedWhen(
                        data: (review) => review == null
                            ? OutlinedButton(
                                onPressed: () => _rateOrder(order),
                                child: Text(l10n.rateOrderButton),
                              )
                            : Row(
                                children: [
                                  Icon(Icons.check_circle_outline, color: colorScheme.primary),
                                  const SizedBox(width: 8),
                                  Text(l10n.orderRatedMessage),
                                ],
                              ),
                        loading: () => const SizedBox.shrink(),
                        error: (_, __) => const SizedBox.shrink(),
                      ),
                ),
              if (canCancel)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: colorScheme.error),
                    onPressed: _cancelling ? null : () => _confirmCancel(order),
                    child: _cancelling
                        ? buttonSpinner(colorScheme.error, size: 16)
                        : Text(l10n.cancelOrderButton),
                  ),
                ),
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

/// What was ordered: store, when, the lines and the amounts the server
/// charged. Every field it reads is on DeliveryOrder already; the ones
/// added over time (vendorName, subtotal, deliveryFee) are optional, so a
/// legacy order shows what it has — no store line, and the
/// `effective*` fallbacks for the amounts. The pickup address stays
/// driver-facing and is deliberately not shown here.
class _OrderSummary extends ConsumerWidget {
  const _OrderSummary({required this.order});

  final DeliveryOrder order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final currencyFormat = ref.watch(currencyFormatProvider);
    final dateFormat = ref.watch(dateTimeFormatProvider);
    final vendorName = order.vendorName?.trim() ?? '';

    return Card(
      key: const ValueKey('order_summary'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.orderDetailsTitle, style: textTheme.titleMedium),
                  if (vendorName.isNotEmpty)
                    _LabeledLine(label: l10n.vendorLabel, value: vendorName),
                  _LabeledLine(
                    label: l10n.orderPlacedAtLabel,
                    value: dateFormat.format(order.createdAt),
                  ),
                  if (order.items.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(l10n.orderItemsTitle, style: textTheme.labelLarge),
                    for (final item in order.items)
                      Semantics(
                        // Spelled out for screen readers instead of "2 × 5,000".
                        label: '${item.name}, ${l10n.quantityLabel} ${item.quantity}, '
                            '${l10n.unitPriceLabel} ${currencyFormat.format(item.unitPrice)}, '
                            '${currencyFormat.format(item.unitPrice * item.quantity)}',
                        excludeSemantics: true,
                        child: Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xs),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item.name, style: textTheme.bodyMedium),
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
                              Text(currencyFormat.format(item.unitPrice * item.quantity)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
            const Divider(height: AppSpacing.xl),
            PriceBreakdown(
              subtotal: order.effectiveSubtotal,
              deliveryFee: order.effectiveDeliveryFee,
              total: order.total,
            ),
          ],
        ),
      ),
    );
  }
}

/// "Label: value" as one line of secondary text, read out as one phrase.
class _LabeledLine extends StatelessWidget {
  const _LabeledLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: label,
              style: textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const TextSpan(text: '  '),
            TextSpan(text: value, style: textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
