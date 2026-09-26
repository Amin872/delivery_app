import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/display_formatters.dart';
import '../../../core/providers/formatters_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/adaptive_label_value.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/order.dart';
import 'vendor_order_actions.dart';

/// One order in the vendor's dashboard list. Everything stacks vertically
/// so nothing competes for a row's width: the short order reference and
/// its status chip on top, then when it was placed, how many items and
/// where it's going, then the total, and the vendor's actions on their own
/// full-width line. Tapping the card opens [onTap] (the order detail).
///
/// Only shows fields already on the order document — no customer lookup.
class VendorOrderCard extends ConsumerWidget {
  const VendorOrderCard({required this.order, required this.onTap, super.key});

  final DeliveryOrder order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final currencyFormat = ref.watch(currencyFormatProvider);
    final dateFormat = ref.watch(dateTimeFormatProvider);
    final secondary = AppColors.textSecondary(colorScheme);
    final metaStyle = textTheme.bodySmall?.copyWith(color: secondary);
    final itemCount = order.items.fold<int>(0, (sum, item) => sum + item.quantity);
    final hasActions = nextVendorStatus(order.status) != null || vendorCanCancel(order.status);

    Widget meta(IconData icon, String text) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: AppSizes.iconSmall, color: secondary),
            const SizedBox(width: AppSpacing.xs),
            Flexible(child: Text(text, style: metaStyle, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
        );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Side by side when both fit; the chip drops under the
              // reference on narrow screens / large text instead of
              // squeezing it.
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  Text(l10n.orderLabel(displayOrderId(order.id)), style: textTheme.titleMedium),
                  OrderStatusChip(status: order.status),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.xs,
                children: [
                  meta(Icons.schedule, dateFormat.format(order.createdAt)),
                  meta(Icons.shopping_bag_outlined, l10n.orderItemCount(itemCount)),
                ],
              ),
              if (order.deliveryAddress.trim().isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                meta(Icons.location_on_outlined, order.deliveryAddress.trim()),
              ],
              const SizedBox(height: AppSpacing.md),
              AdaptiveLabelValue(
                label: l10n.totalLabel,
                value: currencyFormat.format(order.total),
                style: textTheme.titleSmall,
              ),
              if (hasActions) ...[
                const SizedBox(height: AppSpacing.md),
                VendorOrderActions(order: order, compact: true),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
