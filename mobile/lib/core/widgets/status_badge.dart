import 'package:flutter/material.dart';

import '../l10n/enum_labels.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../../models/approval_status.dart';
import '../../models/order.dart';

/// Semantic meaning of a badge. Colours come from the unified palette:
/// green/orange/red/blue are only ever used through these tones.
enum StatusTone { neutral, primary, info, success, warning, error }

Color statusToneColor(ColorScheme colorScheme, StatusTone tone) => switch (tone) {
      StatusTone.neutral => AppColors.textSecondary(colorScheme),
      StatusTone.primary => colorScheme.primary,
      StatusTone.info => AppColors.info(colorScheme),
      StatusTone.success => AppColors.success(colorScheme),
      StatusTone.warning => AppColors.warning(colorScheme),
      StatusTone.error => colorScheme.error,
    };

/// The one pill-shaped status label: tinted fill, coloured text, optional
/// leading icon. Single line, ellipsised, direction-aware padding — safe in
/// a Wrap, a Row, a ListTile subtitle or trailing.
class StatusBadge extends StatelessWidget {
  const StatusBadge({required this.label, required this.tone, this.icon, super.key});

  final String label;
  final StatusTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = statusToneColor(colorScheme, tone);
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w600);
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: AppRadius.pill),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: AppSpacing.xs),
          ],
          Flexible(
            child: Text(label, style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

/// Single source of truth for how each order status reads visually.
/// Waiting on the vendor → warning; moving through fulfilment → primary;
/// finished → success; cancelled → error. Labels stay [orderStatusLabel].
StatusTone orderStatusTone(OrderStatus status) => switch (status) {
      OrderStatus.pending => StatusTone.warning,
      OrderStatus.accepted ||
      OrderStatus.preparing ||
      OrderStatus.readyForPickup ||
      OrderStatus.driverAssigned ||
      OrderStatus.pickedUp ||
      OrderStatus.delivering =>
        StatusTone.primary,
      OrderStatus.delivered => StatusTone.success,
      OrderStatus.cancelled => StatusTone.error,
    };

/// An order's localized status as a [StatusBadge].
class OrderStatusChip extends StatelessWidget {
  const OrderStatusChip({required this.status, super.key});

  final OrderStatus status;

  @override
  Widget build(BuildContext context) =>
      StatusBadge(label: orderStatusLabel(context, status), tone: orderStatusTone(status));
}

/// Vendor/driver approval (pending / approved / rejected) — one mapping for
/// both roles, which share the enum and the labels.
StatusTone approvalStatusTone(ApprovalStatus status) => switch (status) {
      ApprovalStatus.approved => StatusTone.success,
      ApprovalStatus.pending => StatusTone.warning,
      ApprovalStatus.rejected => StatusTone.error,
    };

class ApprovalStatusBadge extends StatelessWidget {
  const ApprovalStatusBadge({required this.status, super.key});

  final ApprovalStatus status;

  @override
  Widget build(BuildContext context) =>
      StatusBadge(label: vendorApprovalStatusLabel(context, status), tone: approvalStatusTone(status));
}
