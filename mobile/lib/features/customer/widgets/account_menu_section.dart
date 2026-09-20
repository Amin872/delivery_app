import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';

/// One "قسم" (section) on [AccountScreen] — a titled, rounded card holding
/// a stack of [AccountMenuItem] rows with a subtle divider between each.
/// New sections/items are added by callers, not by this widget — it stays a
/// dumb layout container so the account screen can keep growing without
/// touching this file. A blank/empty [title] (the sign-out row's own
/// section) renders with no header, just the card.
class AccountMenuSection extends StatelessWidget {
  const AccountMenuSection({required this.title, required this.items, super.key});

  final String title;
  final List<AccountMenuItem> items;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm, left: 4, right: 4),
              child: Text(
                title,
                style: textTheme.titleSmall?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ),
          Container(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer,
              borderRadius: AppRadius.large,
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  items[i],
                  if (i != items.length - 1)
                    Divider(
                      height: 1,
                      indent: 56,
                      endIndent: AppSpacing.lg,
                      color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.04, end: 0, curve: Curves.easeOut);
  }
}

/// A single tappable row inside an [AccountMenuSection] — an icon in a
/// tinted circle, a label with an optional [subtitle], and either a default
/// chevron or a caller-supplied [trailing] widget (e.g. a toggle/switch).
/// Wrapped in [MergeSemantics] so assistive tech announces the whole row —
/// icon, label, subtitle, trailing value — as one coherent, tappable node
/// instead of several disjoint ones.
class AccountMenuItem extends StatelessWidget {
  const AccountMenuItem({
    required this.icon,
    required this.label,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.iconColor,
    this.labelColor,
    super.key,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Color? iconColor;
  final Color? labelColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final resolvedIconColor = iconColor ?? colorScheme.primary;

    return MergeSemantics(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 28),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: resolvedIconColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 18, color: resolvedIconColor),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: textTheme.bodyLarge?.copyWith(color: labelColor),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
                trailing ?? Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
