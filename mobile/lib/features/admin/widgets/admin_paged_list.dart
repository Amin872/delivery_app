import 'package:flutter/material.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/paging/paged_list_controller.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_spinner.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/app_localizations.dart';

/// A scrolling list driven by a [PagedListController]: skeleton while the
/// first page loads, the shared error state (with Retry) if it fails, the
/// shared empty state when nothing matches, and otherwise the records with
/// an explicit "Load more" footer while more exist. A failed "Load more"
/// keeps every record shown and offers its own Retry in the footer.
class AdminPagedList<T> extends StatelessWidget {
  const AdminPagedList({
    required this.controller,
    required this.itemBuilder,
    required this.emptyMessage,
    this.padding = const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    super.key,
  });

  final PagedListController<T> controller;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final String emptyMessage;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.hasLoaded) {
          final error = controller.error;
          if (error != null && !controller.isLoading) {
            return ErrorState(error: error, onRetry: controller.retry);
          }
          return const ListSkeletonLoader();
        }
        final items = controller.items;
        if (items.isEmpty && !controller.hasMore) {
          return EmptyState(message: emptyMessage);
        }
        return ListView.builder(
          padding: padding,
          itemCount: items.length + 1,
          itemBuilder: (context, index) {
            if (index < items.length) return itemBuilder(context, items[index], index);
            return _LoadMoreFooter(controller: controller);
          },
        );
      },
    );
  }
}

class _LoadMoreFooter extends StatelessWidget {
  const _LoadMoreFooter({required this.controller});

  final PagedListController<Object?> controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final Widget child;
    if (controller.isLoadingMore) {
      child = SizedBox(
        key: const ValueKey('admin_load_more_busy'),
        height: AppSizes.minTapTarget,
        child: Center(child: buttonSpinner(colorScheme.primary)),
      );
    } else if (controller.error != null) {
      child = Column(
        key: const ValueKey('admin_load_more_error'),
        children: [
          Text(
            localizedErrorMessage(context, controller.error!),
            textAlign: TextAlign.center,
            style: TextStyle(color: colorScheme.error),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: controller.retry,
            icon: const Icon(Icons.refresh),
            label: Text(l10n.retryButton),
          ),
        ],
      );
    } else if (controller.hasMore) {
      child = OutlinedButton(
        key: const ValueKey('admin_load_more'),
        onPressed: controller.loadMore,
        child: Text(l10n.loadMoreButton),
      );
    } else {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Center(child: child),
    );
  }
}
