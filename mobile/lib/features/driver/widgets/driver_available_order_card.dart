import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/display_formatters.dart';
import '../../../core/providers/formatters_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/adaptive_label_value.dart';
import '../../../core/widgets/app_spinner.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/order.dart';
import 'driver_order_summary.dart';

/// One unclaimed order in the driver's queue: its short reference, where
/// to collect it and where it's going, how many items, the cash total to
/// collect, and Accept on its own full-width line. Purely presentational —
/// accepting (and its busy state) is owned by DriverHomeScreen, which
/// passes [isAccepting] and [onAccept].
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
    final colorScheme = Theme.of(context).colorScheme;
    final currencyFormat = ref.watch(currencyFormatProvider);
    final secondary = AppColors.textSecondary(colorScheme);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.orderLabel(displayOrderId(order.id)), style: textTheme.titleMedium),
            DriverOrderLocations(order: order),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Icon(Icons.shopping_bag_outlined, size: AppSizes.iconSmall, color: secondary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    l10n.orderItemCount(orderItemQuantity(order)),
                    style: textTheme.bodySmall?.copyWith(color: secondary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            AdaptiveLabelValue(
              label: l10n.amountToCollectLabel,
              value: currencyFormat.format(order.total),
              style: textTheme.titleSmall,
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              key: ValueKey('driver_accept_${order.id}'),
              onPressed: isAccepting ? null : onAccept,
              child: isAccepting
                  ? buttonSpinner(colorScheme.onPrimary, size: AppSizes.iconSmall)
                  : Text(l10n.acceptButton),
            ),
          ],
        ),
      ),
    );
  }
}
