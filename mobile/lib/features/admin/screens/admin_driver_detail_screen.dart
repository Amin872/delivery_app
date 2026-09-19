import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/providers/formatters_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/animated_async.dart';
import '../../../core/widgets/language_toggle_button.dart';
import '../../../core/widgets/responsive_center.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/widgets/star_rating.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/app_user.dart';
import '../../../models/driver.dart';
import '../../customer/screens/customer_home_screen.dart' show firestoreServiceProvider;

final _driverUserProvider = StreamProvider.autoDispose.family<AppUser, String>((ref, userId) {
  return ref.watch(firestoreServiceProvider).watchUser(userId);
});

final _driverProvider = StreamProvider.autoDispose.family<Driver, String>((ref, driverId) {
  return ref.watch(firestoreServiceProvider).watchDriver(driverId);
});

final _driverDeliveryCountProvider = FutureProvider.autoDispose.family<int, String>((ref, driverId) {
  return ref.watch(firestoreServiceProvider).countDriverDeliveries(driverId);
});

/// Read-only admin driver detail — identity (from `users/{uid}`),
/// availability/rating/location (from `drivers/{uid}`), and delivery count
/// (existing `countDriverDeliveries` aggregation, same one
/// `DriverStatsScreen` already uses for the driver's own view of it).
/// No enable/disable/approval/suspension — Phase 4 Drivers is read-only,
/// and no new driver state is introduced.
class AdminDriverDetailScreen extends ConsumerWidget {
  const AdminDriverDetailScreen({required this.driverId, super.key});

  final String driverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final userAsync = ref.watch(_driverUserProvider(driverId));
    final vendorTheme = VendorPalette.themeFrom(Theme.of(context));

    return Theme(
      data: vendorTheme,
      child: Scaffold(
        backgroundColor: VendorPalette.background,
        appBar: AppBar(
          backgroundColor: VendorPalette.background,
          foregroundColor: VendorPalette.textPrimary,
          title: Text(userAsync.valueOrNull?.displayName ?? l10n.adminNavDrivers),
          actions: const [LanguageToggleButton()],
        ),
        body: ResponsiveCenter(
          child: userAsync.animatedWhen(
            data: (user) => _DriverDetailBody(driverId: driverId, user: user),
            loading: () => const ListSkeletonLoader(),
            error: (error, _) => Center(
              child: Text(
                localizedErrorMessage(context, error),
                style: const TextStyle(color: VendorPalette.textSecondary),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DriverDetailBody extends ConsumerWidget {
  const _DriverDetailBody({required this.driverId, required this.user});

  final String driverId;
  final AppUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final dateFormat = ref.watch(dateTimeFormatProvider);
    final driverAsync = ref.watch(_driverProvider(driverId));
    final deliveryCountAsync = ref.watch(_driverDeliveryCountProvider(driverId));

    return driverAsync.animatedWhen(
      data: (driver) {
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Row(
              children: [
                _AvailabilityBadge(isAvailable: driver.isAvailable),
                const Spacer(),
                StarRatingDisplay(
                  rating: driver.averageRating,
                  count: driver.ratingCount == 0 ? null : driver.ratingCount,
                  size: 18,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _InfoCard(children: [
              _InfoRow(label: l10n.emailLabel, value: user.email),
              _InfoRow(
                label: l10n.phoneNumberLabel,
                value: user.phoneNumber ?? l10n.noPhoneNumberPlaceholder,
              ),
            ]),
            const SizedBox(height: AppSpacing.md),
            _InfoCard(children: [
              deliveryCountAsync.when(
                data: (count) => _InfoRow(label: l10n.deliveredOrdersLabel, value: '$count'),
                loading: () => _InfoRow(label: l10n.deliveredOrdersLabel, value: l10n.loadingLabel),
                error: (_, __) => _InfoRow(label: l10n.deliveredOrdersLabel, value: '—'),
              ),
              _InfoRow(
                label: l10n.ratingStatLabel,
                value: driver.ratingCount == 0
                    ? l10n.notRatedYetLabel
                    : driver.averageRating!.toStringAsFixed(1),
              ),
            ]),
            const SizedBox(height: AppSpacing.md),
            _InfoCard(children: [
              if (driver.lastKnownLocation == null)
                _InfoRow(label: l10n.lastKnownLocationLabel, value: l10n.noLocationDataMessage)
              else ...[
                _InfoRow(
                  label: l10n.lastKnownLocationLabel,
                  value:
                      '${driver.lastKnownLocation!.latitude.toStringAsFixed(5)}, ${driver.lastKnownLocation!.longitude.toStringAsFixed(5)}',
                ),
                _InfoRow(
                  label: l10n.locationUpdatedAtLabel,
                  value: dateFormat.format(driver.lastKnownLocation!.updatedAt),
                ),
              ],
            ]),
          ],
        );
      },
      loading: () => const ListSkeletonLoader(),
      error: (error, _) => Center(
        child: Text(
          localizedErrorMessage(context, error),
          style: const TextStyle(color: VendorPalette.textSecondary),
        ),
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

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: VendorPalette.surfaceContainer,
        borderRadius: AppRadius.large,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: VendorPalette.textSecondary)),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(color: VendorPalette.textPrimary, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
