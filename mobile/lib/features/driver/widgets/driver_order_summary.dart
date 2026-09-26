import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/enum_labels.dart';
import '../../../core/providers/formatters_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/adaptive_label_value.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/city.dart';
import '../../../models/coordinates.dart';
import '../../../models/driver.dart';
import '../../../models/order.dart';
import '../../customer/screens/customer_home_screen.dart' show allCitiesProvider;

// Presentational pieces shared by the driver's available-order and
// active-delivery cards. Everything comes from the order document itself
// (createOrder's vendor snapshot and price breakdown) — no per-order vendor
// lookups. Snapshot fields are null on orders placed before Phase 21, so
// each row is simply omitted when its data is missing.

/// Total quantity across the order's lines ("3 items" for 2 + 1).
int orderItemQuantity(DeliveryOrder order) =>
    order.items.fold(0, (sum, item) => sum + item.quantity);

enum DriverStopKind { pickup, dropOff }

/// Where the driver is heading next on [order]: the vendor's pickup point
/// until the order is picked up, then the customer's drop-off. [coordinates]
/// is null when that stop has no pin (vendor never set one, or a legacy
/// order) — callers then hide navigation and the estimate.
typedef DriverNextStop = ({DriverStopKind kind, Coordinates? coordinates});

DriverNextStop? driverNextStop(DeliveryOrder order) {
  switch (order.status) {
    case OrderStatus.driverAssigned:
      return (kind: DriverStopKind.pickup, coordinates: order.pickupCoordinates);
    case OrderStatus.pickedUp:
    case OrderStatus.delivering:
      return (kind: DriverStopKind.dropOff, coordinates: order.deliveryCoordinates);
    default:
      return null;
  }
}

/// How old the driver's last published position may be and still count as
/// "where the driver is now" for an estimate.
const driverPositionMaxAge = Duration(minutes: 10);

/// The driver's own last published position (drivers/{uid}.lastKnownLocation,
/// written by the existing GPS pipeline while pickedUp/delivering), or null
/// when there is none or it's older than [driverPositionMaxAge].
Coordinates? recentDriverPosition(DriverLocation? location, DateTime now) {
  if (location == null) return null;
  if (now.difference(location.updatedAt) > driverPositionMaxAge) return null;
  return Coordinates(latitude: location.latitude, longitude: location.longitude);
}

/// Store, pickup and drop-off lines for one order.
class DriverOrderLocations extends ConsumerWidget {
  const DriverOrderLocations({required this.order, super.key});

  final DeliveryOrder order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final cities = ref.watch(allCitiesProvider).valueOrNull ?? const <CityOption>[];
    final vendorName = order.vendorName;
    final pickupAddress = order.pickupAddress;
    final cityId = order.cityId;
    final dropOff = (cityId == null || cityId.isEmpty)
        ? order.deliveryAddress
        : '${order.deliveryAddress} · ${cityLabel(context, cityId, cities)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (vendorName != null && vendorName.isNotEmpty)
          _InfoLine(icon: Icons.storefront_outlined, label: l10n.orderStoreLabel, text: vendorName),
        if (pickupAddress != null && pickupAddress.isNotEmpty)
          _InfoLine(icon: Icons.trip_origin, label: l10n.pickupLocationTitle, text: pickupAddress),
        _InfoLine(icon: Icons.place_outlined, label: l10n.deliveryAddressLabel, text: dropOff),
      ],
    );
  }
}

/// The order's lines: each item's name across the full width, then
/// "quantity × unit price" and the line total on the next line — side by
/// side when they fit, the total moving under it when they don't (large
/// amounts, 1.3x text), so neither the name nor an amount is ever squeezed.
class DriverOrderItems extends ConsumerWidget {
  const DriverOrderItems({required this.order, super.key});

  final DeliveryOrder order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final secondary = AppColors.textSecondary(Theme.of(context).colorScheme);
    final currencyFormat = ref.watch(currencyFormatProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in order.items)
          Semantics(
            label: '${item.name}, ${l10n.quantityLabel} ${item.quantity}, '
                '${l10n.unitPriceLabel} ${currencyFormat.format(item.unitPrice)}, '
                '${currencyFormat.format(item.unitPrice * item.quantity)}',
            excludeSemantics: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(item.name, style: textTheme.bodyMedium),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: AppSpacing.md,
                    children: [
                      Text(
                        l10n.orderItemQuantityPrice(item.quantity, currencyFormat.format(item.unitPrice)),
                        style: textTheme.bodySmall?.copyWith(color: secondary),
                      ),
                      // One line always: shrinks (never wraps mid-number) in the
                      // rare case it is wider than the whole card.
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          currencyFormat.format(item.unitPrice * item.quantity),
                          style: textTheme.bodyMedium,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Subtotal, delivery fee and the cash total to collect. Uses the
/// effective* getters so legacy orders (total only) still read correctly.
/// Each label and amount share a line when they fit and stack when they
/// don't; an amount is never wrapped mid-number.
class DriverOrderTotals extends ConsumerWidget {
  const DriverOrderTotals({required this.order, super.key});

  final DeliveryOrder order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final currencyFormat = ref.watch(currencyFormatProvider);

    Widget amountRow(String label, double amount, {bool emphasized = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: AdaptiveLabelValue(
            label: label,
            value: currencyFormat.format(amount),
            style: emphasized ? textTheme.titleSmall : textTheme.bodySmall,
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        amountRow(l10n.subtotalLabel, order.effectiveSubtotal),
        amountRow(l10n.deliveryFeeLabel, order.effectiveDeliveryFee),
        amountRow(l10n.amountToCollectLabel, order.total, emphasized: true),
      ],
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.label, required this.text});

  final IconData icon;
  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '$label: $text',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Tooltip(message: label, child: Icon(icon, size: AppSizes.iconSmall, color: colorScheme.onSurfaceVariant)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}
