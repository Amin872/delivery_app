import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/l10n/enum_labels.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/widgets/staggered_list_item.dart';
import '../../../core/widgets/star_rating.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/app_user.dart';
import '../../../models/approval_status.dart';
import '../../../models/driver.dart';
import '../../../routing/page_transitions.dart';
import '../../customer/screens/customer_home_screen.dart' show firestoreServiceProvider;
import '../widgets/admin_scaffold.dart';
import 'admin_driver_detail_screen.dart';
import 'admin_users_screen.dart' show allUsersProvider;

final allDriversProvider = StreamProvider.autoDispose<List<Driver>>((ref) {
  return ref.watch(firestoreServiceProvider).watchAllDrivers();
});

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

/// Admin driver directory — joins `drivers` (availability/rating/approval)
/// with `users` (identity) via [buildDriverRows], the same join
/// `AdminOrderDetailScreen`'s reassignment picker uses. Each row shows the
/// driver's approval state; approving/rejecting happens on
/// [AdminDriverDetailScreen]. No enable/disable or suspension here.
class AdminDriversScreen extends ConsumerStatefulWidget {
  const AdminDriversScreen({super.key});

  @override
  ConsumerState<AdminDriversScreen> createState() => _AdminDriversScreenState();
}

class _AdminDriversScreenState extends ConsumerState<AdminDriversScreen> {
  String _query = '';
  // Null = all. Combined with [_query] (both must match).
  ApprovalStatus? _statusFilter;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AdminScaffold(
      title: l10n.adminNavDrivers,
      selected: AdminDestination.drivers,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            style: const TextStyle(color: VendorPalette.textPrimary),
            decoration: InputDecoration(
              hintText: l10n.searchDriversHint,
              hintStyle: const TextStyle(color: VendorPalette.textMuted),
              prefixIcon: const Icon(Icons.search, color: VendorPalette.textSecondary),
              filled: true,
              fillColor: VendorPalette.surfaceContainer,
              border: OutlineInputBorder(borderRadius: AppRadius.medium, borderSide: BorderSide.none),
            ),
            onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
          ),
          const SizedBox(height: AppSpacing.md),
          // Same approval chips as AdminVendorsScreen (same three states and
          // labels); filtering is client-side over the existing stream.
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: ChoiceChip(
                    key: const ValueKey('driver_filter_all'),
                    label: Text(l10n.allStatusesLabel),
                    selected: _statusFilter == null,
                    onSelected: (_) => setState(() => _statusFilter = null),
                  ),
                ),
                for (final status in ApprovalStatus.values)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      key: ValueKey('driver_filter_${status.name}'),
                      label: Text(vendorApprovalStatusLabel(context, status)),
                      selected: _statusFilter == status,
                      onSelected: (_) => setState(() => _statusFilter = status),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(child: _DriverList(query: _query, status: _statusFilter)),
        ],
      ),
    );
  }
}

class _DriverList extends ConsumerWidget {
  const _DriverList({required this.query, required this.status});

  final String query;
  final ApprovalStatus? status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final driversAsync = ref.watch(allDriversProvider);
    final usersAsync = ref.watch(allUsersProvider);

    if (driversAsync.isLoading || usersAsync.isLoading) {
      return const ListSkeletonLoader();
    }
    if (driversAsync.hasError) {
      return Center(child: Text(localizedErrorMessage(context, driversAsync.error!)));
    }
    if (usersAsync.hasError) {
      return Center(child: Text(localizedErrorMessage(context, usersAsync.error!)));
    }

    final filtered = filterDriverRows(
      buildDriverRows(driversAsync.value!, usersAsync.value!),
      query: query,
      status: status,
    );

    if (filtered.isEmpty) {
      return Center(child: Text(l10n.noDriversFoundMessage));
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final row = filtered[index];
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: VendorPalette.surfaceElevated,
              child: Text(
                row.name.isNotEmpty ? row.name[0].toUpperCase() : '?',
                style: const TextStyle(color: VendorPalette.textPrimary),
              ),
            ),
            title: Text(row.name),
            // The two status pills sit under the rating rather than stacked
            // in `trailing`: ListTile caps trailing at the tile's fixed
            // height, which two pills overflowed; here the tile grows with
            // its content (and with the user's text scale).
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
            onTap: () => Navigator.of(context)
                .push(fadeSlideRoute(AdminDriverDetailScreen(driverId: row.driverId))),
          ),
        ).staggeredEntrance(index);
      },
    );
  }
}

class _AvailabilityBadge extends StatelessWidget {
  const _AvailabilityBadge({required this.isAvailable});

  final bool isAvailable;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final color = isAvailable ? AppColors.success(colorScheme) : VendorPalette.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: AppRadius.pill),
      child: Text(
        isAvailable ? l10n.driverAvailableStatusLabel : l10n.driverUnavailableStatusLabel,
        style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }
}

/// Pill showing a driver's approval state (pending / approved / rejected),
/// shared by the driver list and [AdminDriverDetailScreen]. Labels reuse the
/// vendor approval strings — same three states, same wording.
class DriverApprovalBadge extends StatelessWidget {
  const DriverApprovalBadge({required this.status, super.key});

  final ApprovalStatus status;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = switch (status) {
      ApprovalStatus.approved => AppColors.success(colorScheme),
      ApprovalStatus.pending => AppColors.warning(colorScheme),
      ApprovalStatus.rejected => colorScheme.error,
    };
    return Container(
      key: ValueKey('driver_approval_badge_${status.name}'),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: AppRadius.pill),
      child: Text(
        vendorApprovalStatusLabel(context, status),
        style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }
}
