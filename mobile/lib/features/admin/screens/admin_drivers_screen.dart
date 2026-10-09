import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/enum_labels.dart';
import '../../../core/paging/paged_list_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../core/widgets/staggered_list_item.dart';
import '../../../core/widgets/star_rating.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/app_user.dart';
import '../../../models/approval_status.dart';
import '../../../models/driver.dart';
import '../../../routing/page_transitions.dart';
import '../../customer/screens/customer_home_screen.dart' show firestoreServiceProvider;
import '../../../services/firestore_service.dart' show DriverAccount;
import '../widgets/admin_actions.dart';
import '../widgets/admin_paged_list.dart';
import '../widgets/admin_scaffold.dart';
import 'admin_driver_detail_screen.dart';

class DriverRow {
  const DriverRow({
    required this.driverId,
    required this.name,
    required this.email,
    required this.isAvailable,
    required this.averageRating,
    required this.ratingCount,
    required this.approvalStatus,
  });

  final String driverId;
  final String name;
  final String email;
  final bool isAvailable;
  final double? averageRating;
  final int ratingCount;
  final ApprovalStatus approvalStatus;
}

/// Joins `drivers` (availability/rating) with `users` (identity) client-side
/// — the same correlation `AdminOrderDetailScreen`'s reassignment picker
/// already does in Phase 3, extracted here as a pure, Firebase-free function
/// so the join itself is unit-testable independent of the two streams.
/// Drivers with no matching `role == driver` user doc (or vice versa) are
/// silently excluded rather than shown with fabricated data — same
/// defensive join the Phase 3 picker already relies on.
List<DriverRow> buildDriverRows(List<Driver> drivers, List<AppUser> users) {
  final driversById = {for (final driver in drivers) driver.id: driver};
  return users
      .where((user) => user.role == UserRole.driver && driversById.containsKey(user.id))
      .map((user) {
        final driver = driversById[user.id]!;
        return DriverRow(
          driverId: user.id,
          name: user.displayName,
          email: user.email,
          isAvailable: driver.isAvailable,
          averageRating: driver.averageRating,
          ratingCount: driver.ratingCount,
          approvalStatus: driver.approvalStatus,
        );
      })
      .toList();
}

/// The rows matching both the search [query] (already trimmed and
/// lower-cased; matched against name and email) and the approval [status]
/// chip (null = any status).
List<DriverRow> filterDriverRows(List<DriverRow> rows, {required String query, ApprovalStatus? status}) {
  return rows
      .where((row) => status == null || row.approvalStatus == status)
      .where((row) =>
          query.isEmpty || row.name.toLowerCase().contains(query) || row.email.toLowerCase().contains(query))
      .toList();
}

/// The rows for one page of driver accounts — the same join and
/// driver-role check as [buildDriverRows], over just that page.
List<DriverRow> driverRowsForAccounts(List<DriverAccount> accounts) => buildDriverRows(
      [for (final account in accounts) account.driver],
      [for (final account in accounts) account.user],
    );

/// Admin driver directory — `drivers` (availability/rating/approval) joined
/// with `users` (identity), 25 per page with "Load more"
/// (FirestoreService.fetchDriverAccountsPage). The approval chips filter on
/// the server; the search is a server-side name prefix (or email prefix
/// with `@`) on `users`, and when it's combined with a chip that page is
/// filtered by status here, so it can hold fewer than 25 rows. Approving /
/// rejecting happens on [AdminDriverDetailScreen]; the row is re-read when
/// the admin comes back. No enable/disable or suspension here.
class AdminDriversScreen extends ConsumerStatefulWidget {
  const AdminDriversScreen({super.key});

  @override
  ConsumerState<AdminDriversScreen> createState() => _AdminDriversScreenState();
}

class _AdminDriversScreenState extends ConsumerState<AdminDriversScreen> {
  String _query = '';
  // Null = all. Combined with [_query] (both must match).
  ApprovalStatus? _statusFilter;

  late final PagedListController<DriverRow> _drivers = PagedListController(
    idOf: (row) => row.driverId,
    fetchPage: (cursor) async {
      final page = await ref
          .read(firestoreServiceProvider)
          .fetchDriverAccountsPage(status: _statusFilter, search: _query, after: cursor);
      // The search path pages `users`, so its status chip applies here.
      return page.withItems(filterDriverRows(driverRowsForAccounts(page.items), query: '', status: _statusFilter));
    },
  );

  @override
  void initState() {
    super.initState();
    _drivers.refresh();
  }

  @override
  void dispose() {
    _drivers.dispose();
    super.dispose();
  }

  void _setQuery(String query) {
    if (query == _query) return;
    setState(() => _query = query);
    _drivers.refresh();
  }

  void _setStatusFilter(ApprovalStatus? status) {
    if (status == _statusFilter) return;
    setState(() => _statusFilter = status);
    _drivers.refresh();
  }

  // The detail screen can approve or reject the driver: re-read just that
  // account on return (dropping it if it no longer matches the chip).
  Future<void> _openDriver(DriverRow row) async {
    await Navigator.of(context).push(fadeSlideRoute(AdminDriverDetailScreen(driverId: row.driverId)));
    if (!mounted) return;
    try {
      final account = await ref.read(firestoreServiceProvider).fetchDriverAccount(row.driverId);
      if (!mounted) return;
      final fresh = account == null
          ? const <DriverRow>[]
          : filterDriverRows(driverRowsForAccounts([account]), query: '', status: _statusFilter);
      if (fresh.isEmpty) {
        _drivers.remove(row.driverId);
      } else {
        _drivers.replace(fresh.single);
      }
    } catch (_) {
      // Keep the row as it was.
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AdminScaffold(
      title: l10n.adminNavDrivers,
      selected: AdminDestination.drivers,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminSearchField(
            hintText: l10n.searchDriversHint,
            helperText: l10n.searchStartsWithHelper,
            onChanged: _setQuery,
          ),
          const SizedBox(height: AppSpacing.md),
          // Same approval chips as AdminVendorsScreen (same three states and
          // labels).
          AdminFilterChipBar(
            chips: [
              ChoiceChip(
                key: const ValueKey('driver_filter_all'),
                label: Text(l10n.allStatusesLabel),
                selected: _statusFilter == null,
                onSelected: (_) => _setStatusFilter(null),
              ),
              for (final status in ApprovalStatus.values)
                ChoiceChip(
                  key: ValueKey('driver_filter_${status.name}'),
                  label: Text(vendorApprovalStatusLabel(context, status)),
                  selected: _statusFilter == status,
                  onSelected: (_) => _setStatusFilter(status),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: AdminPagedList<DriverRow>(
              controller: _drivers,
              emptyMessage: l10n.noDriversFoundMessage,
              itemBuilder: (context, row, index) => _DriverTile(row: row, onTap: () => _openDriver(row))
                  .staggeredEntrance(index),
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverTile extends StatelessWidget {
  const _DriverTile({required this.row, required this.onTap});

  final DriverRow row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: VendorPalette.surfaceElevated,
          child: Text(
            row.name.isNotEmpty ? row.name[0].toUpperCase() : '?',
            style: const TextStyle(color: VendorPalette.textPrimary),
          ),
        ),
        title: Text(row.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        // The two status pills sit under the rating rather than stacked in
        // `trailing`: ListTile caps trailing at the tile's fixed height,
        // which two pills overflowed; here the tile grows with its content
        // (and with the user's text scale).
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StarRatingDisplay(
              rating: row.averageRating,
              count: row.ratingCount == 0 ? null : row.ratingCount,
              size: 14,
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                DriverApprovalBadge(status: row.approvalStatus),
                _AvailabilityBadge(isAvailable: row.isAvailable),
              ],
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

class _AvailabilityBadge extends StatelessWidget {
  const _AvailabilityBadge({required this.isAvailable});

  final bool isAvailable;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return StatusBadge(
      label: isAvailable ? l10n.driverAvailableStatusLabel : l10n.driverUnavailableStatusLabel,
      tone: isAvailable ? StatusTone.success : StatusTone.neutral,
    );
  }
}

/// A driver's approval state (pending / approved / rejected), shared by the
/// driver list and [AdminDriverDetailScreen]. Same mapping and labels as
/// vendors — see [ApprovalStatusBadge].
class DriverApprovalBadge extends StatelessWidget {
  const DriverApprovalBadge({required this.status, super.key});

  final ApprovalStatus status;

  @override
  Widget build(BuildContext context) =>
      ApprovalStatusBadge(key: ValueKey('driver_approval_badge_${status.name}'), status: status);
}
