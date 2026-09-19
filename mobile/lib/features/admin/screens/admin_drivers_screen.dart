import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/widgets/staggered_list_item.dart';
import '../../../core/widgets/star_rating.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/app_user.dart';
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
  });

  final String driverId;
  final String name;
  final String email;
  final bool isAvailable;
  final double? averageRating;
  final int ratingCount;
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
        );
      })
      .toList();
}

/// Read-only admin driver directory — joins `drivers` (availability/rating)
/// with `users` (identity), same client-side join
/// `AdminOrderDetailScreen`'s reassignment picker already established in
/// Phase 3, just surfaced as its own browsable list instead of a picker.
/// No enable/disable/approval here — Phase 4 Drivers is read-only.
class AdminDriversScreen extends ConsumerStatefulWidget {
  const AdminDriversScreen({super.key});

  @override
  ConsumerState<AdminDriversScreen> createState() => _AdminDriversScreenState();
}

class _AdminDriversScreenState extends ConsumerState<AdminDriversScreen> {
  String _query = '';

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
          Expanded(child: _DriverList(query: _query)),
        ],
      ),
    );
  }
}

class _DriverList extends ConsumerWidget {
  const _DriverList({required this.query});

  final String query;

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

    final rows = buildDriverRows(driversAsync.value!, usersAsync.value!);

    final filtered = query.isEmpty
        ? rows
        : rows
            .where((row) =>
                row.name.toLowerCase().contains(query) || row.email.toLowerCase().contains(query))
            .toList();

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
            subtitle: StarRatingDisplay(
              rating: row.averageRating,
              count: row.ratingCount == 0 ? null : row.ratingCount,
              size: 14,
            ),
            trailing: _AvailabilityBadge(isAvailable: row.isAvailable),
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
