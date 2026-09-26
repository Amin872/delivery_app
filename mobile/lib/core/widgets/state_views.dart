import 'package:flutter/material.dart';

import '../errors/error_messages.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../../l10n/app_localizations.dart';

/// Shared "nothing here" body for lists and screens: optional icon and
/// title above a centred message, optional action below. Centred in
/// whatever space its parent gives it (a list body, an Expanded, a
/// SliverFillRemaining); never scrolls by itself.
class EmptyState extends StatelessWidget {
  const EmptyState({required this.message, this.icon, this.title, this.action, super.key});

  final String message;
  final IconData? icon;
  final String? title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 40, color: AppColors.textMuted(colorScheme)),
              const SizedBox(height: AppSpacing.md),
            ],
            if (title != null) ...[
              Text(title!, style: textTheme.titleMedium, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.xs),
            ],
            Text(
              message,
              style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary(colorScheme)),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[
              const SizedBox(height: AppSpacing.lg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Shared error body: the localized message for [error] (never raw error
/// text — see [localizedErrorMessage]) and, when the screen can actually
/// retry, a Retry button wired to [onRetry]. No [onRetry] → no button.
class ErrorState extends StatelessWidget {
  const ErrorState({required this.error, this.onRetry, super.key});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: colorScheme.error),
            const SizedBox(height: AppSpacing.md),
            Text(
              localizedErrorMessage(context, error),
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(l10n.retryButton),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
