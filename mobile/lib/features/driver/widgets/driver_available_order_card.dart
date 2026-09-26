import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/formatters_provider.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_spinner.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/order.dart';
import 'driver_order_summary.dart';

/// One unclaimed order in the driver's queue: where to collect it, where
/// it's going, how many items, and the cash total to collect. Purely
/// presentational — accepting (and its busy state) is owned by
/// DriverHomeScreen, which passes [isAccepting] and [onAccept].
class DriverAvailableOrderCard extends ConsumerWidget {
  const DriverAvailableOrderCard({
    required this.order,
    required this.isAccepting,
    required this.onAccept,
    super.key,
  });

  final DeliveryOrder order;
  final bool isAccepting;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final currencyFormat = ref.watch(currencyFormatProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(l10n.orderLabel(order.id), style: textTheme.titleSmall)),
                const SizedBox(width: AppSpacing.sm),
                FilledButton(
                  onPressed: isAccepting ? null : onAccept,
                  child: isAccepting
                      ? buttonSpinner(Theme.of(context).colorScheme.onPrimary, size: 16)
                      : Text(l10n.acceptButton, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            DriverOrderLocations(order: order),
            const SizedBox(height: AppSpacing.sm),
            // The amount (label + value) is the flexible side, aligned to the
            // end: the label is long in Arabic, so it wraps instead of
            // pushing the Row past the card's width.
            Row(
              children: [
                Text(
                  l10n.orderItemCount(orderItemQuantity(order)),
                  style: textTheme.bodySmall,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('${l10n.amountToCollectLabel}: ', style: textTheme.bodySmall),
                      Text(currencyFormat.format(order.total), style: textTheme.titleSmall),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
