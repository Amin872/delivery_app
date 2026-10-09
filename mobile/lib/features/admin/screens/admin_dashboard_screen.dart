import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/approval_status.dart';
import '../../../models/vendor.dart';
import '../../customer/screens/customer_home_screen.dart' show firestoreServiceProvider;
import '../widgets/admin_scaffold.dart';
import 'admin_drivers_screen.dart' show allDriversProvider;

final pendingVendorsProvider = StreamProvider<List<Vendor>>((ref) {
  return ref.watch(firestoreServiceProvider).watchPendingVendors();
});

/// Admin's landing page — reached at the app's single `/` route once
/// `_RoleGate` resolves an admin user (see `routing/app_router.dart`). Kept
/// deliberately simple: real (not fabricated) pending-approval counts for
/// vendors and drivers plus quick access to Orders and Promotions. Approval
/// itself lives in [AdminVendorsScreen] / the driver detail screen — this
/// screen only shows the counts and a way to get there, through the same
/// [navigateToAdminDestination] the admin nav uses.
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final pendingCount = ref.watch(pendingVendorsProvider).whenData((vendors) => vendors.length);
    // Counted client-side from the same drivers stream AdminDriversScreen
    // lists (no extra query). A legacy driver doc without approvalStatus
    // parses as pending there too, so both screens agree.
    final pendingDriverCount = ref
        .watch(allDriversProvider)
        .whenData((drivers) => drivers.where((driver) => driver.approvalStatus == ApprovalStatus.pending).length);

    // Real, live counts — never shown as a number until one has actually
    // loaded (so never a fabricated "0"), and a failed stream says so
    // (with a retry) instead of "Loading…" forever.
    // A retry reloads with the old error still attached, so "failed" means
    // errored and not currently reloading.
    bool failed(AsyncValue<int> count) => count.hasError && !count.isLoading;
    String countSubtitle(AsyncValue<int> count, String Function(int) label) {
      if (failed(count)) return l10n.countLoadFailedLabel;
      final value = count.valueOrNull;
      return value == null || count.hasError ? l10n.loadingLabel : label(value);
    }

    return AdminScaffold(
      title: l10n.adminDashboardTitle,
      selected: AdminDestination.dashboard,
      body: ListView(
        children: [
          _QuickAccessCard(
            key: const ValueKey('dashboard_pending_vendors'),
            icon: Icons.storefront_outlined,
            title: l10n.vendorApprovalsTitle,
            subtitle: countSubtitle(pendingCount, l10n.pendingApprovalsCountLabel),
            onRetry: failed(pendingCount) ? () => ref.invalidate(pendingVendorsProvider) : null,
            onTap: () => navigateToAdminDestination(context, AdminDestination.dashboard, AdminDestination.vendors),
          ),
          const SizedBox(height: AppSpacing.md),
          _QuickAccessCard(
            key: const ValueKey('dashboard_pending_drivers'),
            icon: Icons.two_wheeler_outlined,
            title: l10n.driverApprovalsTitle,
            subtitle: countSubtitle(pendingDriverCount, l10n.pendingDriverApprovalsCountLabel),
            onRetry: failed(pendingDriverCount) ? () => ref.invalidate(allDriversProvider) : null,
            onTap: () => navigateToAdminDestination(context, AdminDestination.dashboard, AdminDestination.drivers),
          ),
          const SizedBox(height: AppSpacing.md),
          _QuickAccessCard(
            icon: Icons.receipt_long_outlined,
            title: l10n.adminOrdersTitle,
            subtitle: l10n.adminOrdersSubtitle,
            onTap: () => navigateToAdminDestination(context, AdminDestination.dashboard, AdminDestination.orders),
          ),
          const SizedBox(height: AppSpacing.md),
          _QuickAccessCard(
            icon: Icons.campaign_outlined,
            title: l10n.adminPromotionsTitle,
            subtitle: l10n.adminPromotionsSubtitle,
            onTap: () => navigateToAdminDestination(context, AdminDestination.dashboard, AdminDestination.promotions),
          ),
        ],
      ),
    );
  }
}

class _QuickAccessCard extends StatelessWidget {
  const _QuickAccessCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.onRetry,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  // Set when the card's count failed to load: the subtitle reads as an
  // error and a Retry button replaces the chevron.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: VendorPalette.surfaceContainer,
      borderRadius: AppRadius.large,
      child: InkWell(
        borderRadius: AppRadius.large,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: VendorPalette.surfaceElevated, shape: BoxShape.circle),
                child: Icon(icon, color: VendorPalette.primaryCyan),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(color: VendorPalette.textPrimary, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: onRetry == null ? VendorPalette.textSecondary : colorScheme.error),
                    ),
                  ],
                ),
              ),
              if (onRetry != null)
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: AppLocalizations.of(context)!.retryButton,
                  onPressed: onRetry,
                )
              else
                Transform.flip(
                  flipX: Directionality.of(context) != TextDirection.rtl,
                  child: const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: VendorPalette.textMuted,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
