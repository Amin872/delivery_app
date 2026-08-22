import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/language_toggle_button.dart';
import '../../../core/widgets/responsive_center.dart';
import '../../../l10n/app_localizations.dart';
import '../../../routing/page_transitions.dart';
import '../../auth/providers/auth_provider.dart';
import '../screens/admin_orders_screen.dart';
import '../screens/admin_promotions_screen.dart';
import '../screens/admin_users_screen.dart';
import '../screens/admin_vendors_screen.dart';

/// Every destination the admin nav (sidebar/drawer) can reach. Dashboard,
/// Vendors, Orders, and Promotions have a real screen behind them today —
/// everything else opens [AdminScaffold] again with a "coming soon" body,
/// so later phases (see ADMIN_AUDIT_REPORT.md) can wire in a real screen one
/// destination at a time without touching this enum's shape or the nav
/// list itself.
enum AdminDestination {
  dashboard,
  users,
  vendors,
  drivers,
  orders,
  products,
  categories,
  promotions,
  notifications,
  locations,
  analytics,
  settings,
}

extension AdminDestinationX on AdminDestination {
  IconData get icon => switch (this) {
        AdminDestination.dashboard => Icons.dashboard_outlined,
        AdminDestination.users => Icons.people_outline,
        AdminDestination.vendors => Icons.storefront_outlined,
        AdminDestination.drivers => Icons.two_wheeler_outlined,
        AdminDestination.orders => Icons.receipt_long_outlined,
        AdminDestination.products => Icons.fastfood_outlined,
        AdminDestination.categories => Icons.category_outlined,
        AdminDestination.promotions => Icons.campaign_outlined,
        AdminDestination.notifications => Icons.notifications_outlined,
        AdminDestination.locations => Icons.location_on_outlined,
        AdminDestination.analytics => Icons.bar_chart_outlined,
        AdminDestination.settings => Icons.settings_outlined,
      };

  // Reuses existing, already-shipped strings where one fits (Orders/
  // Promotions already have a short, accurate title) rather than minting a
  // near-duplicate nav-only label for those two. Vendors uses its own
  // restaurantManagementTitle since the destination now covers the full
  // restaurant directory (list/search/filter/edit/enable-disable), not just
  // the approval queue vendorApprovalsTitle was named for.
  String label(AppLocalizations l10n) => switch (this) {
        AdminDestination.dashboard => l10n.adminNavDashboard,
        AdminDestination.users => l10n.adminNavUsers,
        AdminDestination.vendors => l10n.restaurantManagementTitle,
        AdminDestination.drivers => l10n.adminNavDrivers,
        AdminDestination.orders => l10n.adminOrdersTitle,
        AdminDestination.products => l10n.adminNavProducts,
        AdminDestination.categories => l10n.adminNavCategories,
        AdminDestination.promotions => l10n.adminPromotionsTitle,
        AdminDestination.notifications => l10n.adminNavNotifications,
        AdminDestination.locations => l10n.adminNavLocations,
        AdminDestination.analytics => l10n.adminNavAnalytics,
        AdminDestination.settings => l10n.adminNavSettings,
      };
}

const _wideBreakpoint = 840.0;

void _navigateTo(BuildContext context, AdminDestination current, AdminDestination destination) {
  if (destination == current) return;
  if (destination == AdminDestination.dashboard) {
    // AdminDashboardScreen is rendered at the app's single go_router `/`
    // page (via `_RoleGate`), so it's always the first route in this
    // Navigator — popping back to it is exactly "go to Dashboard" no matter
    // how deep the admin has navigated.
    Navigator.of(context).popUntil((route) => route.isFirst);
    return;
  }
  final l10n = AppLocalizations.of(context)!;
  // Vendors/Orders/Promotions keep their own existing screen — Orders and
  // Promotions in particular are untouched per the "don't rebuild them"
  // requirement, so they open as their own full-screen route (own AppBar,
  // own back button) rather than being squeezed into this shell's body.
  final Widget screen = switch (destination) {
    AdminDestination.users => const AdminUsersScreen(),
    AdminDestination.vendors => const AdminVendorsScreen(),
    AdminDestination.orders => const AdminOrdersScreen(),
    AdminDestination.promotions => const AdminPromotionsScreen(),
    _ => AdminScaffold(
        title: destination.label(l10n),
        selected: destination,
        body: _AdminComingSoonBody(destination: destination),
      ),
  };
  Navigator.of(context).push(fadeSlideRoute(screen));
}

/// Shared shell for every admin page: an AppBar (page title, language
/// toggle, sign-out) plus the same [AdminDestination] list rendered as a
/// persistent sidebar on wide viewports or a [Drawer] on narrow ones.
/// Applies [VendorPalette] — this app's existing dark-navy/cyan identity
/// (already used by Home, the vendor menu screen, cart, ...) — rather than
/// inventing a separate admin color scheme.
class AdminScaffold extends ConsumerWidget {
  const AdminScaffold({
    required this.title,
    required this.selected,
    required this.body,
    super.key,
  });

  final String title;
  final AdminDestination selected;
  final Widget body;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final vendorTheme = VendorPalette.themeFrom(Theme.of(context));
    final isWide = MediaQuery.sizeOf(context).width >= _wideBreakpoint;

    final content = Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: ResponsiveCenter(maxWidth: 1100, child: body),
    );

    return Theme(
      data: vendorTheme,
      child: Scaffold(
        backgroundColor: VendorPalette.background,
        appBar: AppBar(
          backgroundColor: VendorPalette.background,
          foregroundColor: VendorPalette.textPrimary,
          title: Text(title),
          actions: [
            const LanguageToggleButton(),
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: l10n.signOutTooltip,
              onPressed: () => ref.read(authServiceProvider).signOut(),
            ),
          ],
        ),
        drawer: isWide
            ? null
            : Drawer(
                backgroundColor: VendorPalette.surface,
                child: SafeArea(
                  child: _AdminNavList(
                    selected: selected,
                    onTap: (destination) {
                      Navigator.of(context).pop();
                      _navigateTo(context, selected, destination);
                    },
                  ),
                ),
              ),
        body: isWide
            ? Row(
                children: [
                  SizedBox(
                    width: 240,
                    child: ColoredBox(
                      color: VendorPalette.surface,
                      child: _AdminNavList(
                        selected: selected,
                        onTap: (destination) => _navigateTo(context, selected, destination),
                      ),
                    ),
                  ),
                  const VerticalDivider(width: 1, color: VendorPalette.divider),
                  Expanded(child: content),
                ],
              )
            : content,
      ),
    );
  }
}

class _AdminNavList extends StatelessWidget {
  const _AdminNavList({required this.selected, required this.onTap});

  final AdminDestination selected;
  final ValueChanged<AdminDestination> onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      children: [
        for (final destination in AdminDestination.values)
          ListTile(
            leading: Icon(
              destination.icon,
              color: destination == selected ? VendorPalette.primaryCyan : VendorPalette.textSecondary,
            ),
            title: Text(
              destination.label(l10n),
              style: TextStyle(
                color: destination == selected ? VendorPalette.primaryCyan : VendorPalette.textPrimary,
                fontWeight: destination == selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            selected: destination == selected,
            selectedTileColor: VendorPalette.surfaceElevated,
            onTap: () => onTap(destination),
          ),
      ],
    );
  }
}

/// Body shown for every [AdminDestination] with no real screen yet — reuses
/// the same "coming soon" copy [PlaceholderScreen] uses elsewhere in the
/// app, just as a body (not its own Scaffold/AppBar) so it can sit inside
/// this shell and keep the sidebar/drawer visible and navigable.
class _AdminComingSoonBody extends StatelessWidget {
  const _AdminComingSoonBody({required this.destination});

  final AdminDestination destination;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: VendorPalette.surfaceElevated, shape: BoxShape.circle),
              child: Icon(destination.icon, size: 40, color: VendorPalette.primaryCyan),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              l10n.featureComingSoonTitle,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(color: VendorPalette.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.featureComingSoonMessage,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: VendorPalette.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
