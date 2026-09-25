import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/formatters_provider.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';

/// Subtotal / delivery fee / total rows — the one price breakdown, shared by
/// CartScreen (a pre-order estimate from the cart and
/// the vendor's current fee) and OrderTrackingScreen (the amounts the
/// server actually charged) and AdminOrderDetailScreen (the same charged
/// amounts, for admins). A zero fee reads as "Free delivery"; a null
/// [deliveryFee] or [total] (still loading) reads as "—".
class PriceBreakdown extends ConsumerWidget {
  const PriceBreakdown({
    required this.subtotal,
    required this.deliveryFee,
    required this.total,
    this.rowPadding = const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
    super.key,
  });

  final double subtotal;
  final double? deliveryFee;
  final double? total;

  /// Around each row. The default suits a bare list; a caller that already
  /// pads its card (AdminOrderDetailScreen) passes vertical-only padding.
  final EdgeInsetsGeometry rowPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final currencyFormat = ref.watch(currencyFormatProvider);
    final fee = deliveryFee;

    Widget row(String label, String value, {TextStyle? style}) {
      return Padding(
        padding: rowPadding,
        // Both sides may wrap: Syrian-pound amounts get long, and at a
        // narrow width with large text a fixed-width amount would overflow.
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(label, style: style)),
            const SizedBox(width: AppSpacing.sm),
            Flexible(child: Text(value, style: style, textAlign: TextAlign.end)),
          ],
        ),
      );
    }

    return Column(
      children: [
        row(l10n.subtotalLabel, currencyFormat.format(subtotal), style: textTheme.bodyMedium),
        row(
          l10n.deliveryFeeLabel,
          fee == null ? '—' : (fee == 0 ? l10n.freeDeliveryLabel : currencyFormat.format(fee)),
          style: textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.xs),
        row(
          l10n.totalLabel,
          total == null ? '—' : currencyFormat.format(total),
          style: textTheme.titleMedium,
        ),
      ],
    );
  }
}
