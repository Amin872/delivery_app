import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/providers/formatters_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../core/widgets/animated_async.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/app_spinner.dart';
import '../../../core/widgets/language_toggle_button.dart';
import '../../../core/widgets/responsive_center.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/widgets/star_rating.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/app_user.dart';
import '../../../models/approval_status.dart';
import '../../../models/driver.dart';
import '../../customer/screens/customer_home_screen.dart' show firestoreServiceProvider;
import 'admin_drivers_screen.dart' show DriverApprovalBadge;

final _driverUserProvider = StreamProvider.autoDispose.family<AppUser, String>((ref, userId) {
  return ref.watch(firestoreServiceProvider).watchUser(userId);
});

final _driverProvider = StreamProvider.autoDispose.family<Driver, String>((ref, driverId) {
  return ref.watch(firestoreServiceProvider).watchDriver(driverId);
});

final _driverDeliveryCountProvider = FutureProvider.autoDispose.family<int, String>((ref, driverId) {
  return ref.watch(firestoreServiceProvider).countDriverDeliveries(driverId);
});

/// Admin driver detail — identity (from `users/{uid}`),
/// availability/rating/location/approval (from `drivers/{uid}`), and
/// delivery count (existing `countDriverDeliveries` aggregation, same one
/// `DriverStatsScreen` already uses for the driver's own view of it). The
/// one admin action here is approving or rejecting the driver
/// ([FirestoreService.setDriverApprovalStatus]); no enable/disable or
/// suspension.
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
            InfoCard(children: [
              Row(
                children: [
                  Text(
                    l10n.approvalStatusFieldLabel,
                    style: const TextStyle(color: VendorPalette.textSecondary),
                  ),
                  const Spacer(),
                  DriverApprovalBadge(status: driver.approvalStatus),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _DriverApprovalActions(driverId: driverId, status: driver.approvalStatus),
            ]),
            const SizedBox(height: AppSpacing.md),
            InfoCard(children: [
              _InfoRow(label: l10n.emailLabel, value: user.email),
              _InfoRow(
                label: l10n.phoneNumberLabel,
                value: user.phoneNumber ?? l10n.noPhoneNumberPlaceholder,
              ),
            ]),
            const SizedBox(height: AppSpacing.md),
            InfoCard(children: [
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
            InfoCard(children: [
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

/// Approve / Reject for one driver. Offers only the transitions that change
/// something (no "Approve" on an approved driver). While a write is in
/// flight both buttons are disabled, so a double tap can't send twice.
class _DriverApprovalActions extends ConsumerStatefulWidget {
  const _DriverApprovalActions({required this.driverId, required this.status});

  final String driverId;
  final ApprovalStatus status;

  @override
  ConsumerState<_DriverApprovalActions> createState() => _DriverApprovalActionsState();
}

class _DriverApprovalActionsState extends ConsumerState<_DriverApprovalActions> {
  ApprovalStatus? _submitting;

  Future<void> _set(ApprovalStatus status) async {
    if (_submitting != null) return;
    setState(() => _submitting = status);
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    try {
      await ref.read(firestoreServiceProvider).setDriverApprovalStatus(widget.driverId, status);
      messenger.showSnackBar(buildAppSnackBar(
        colorScheme,
        status == ApprovalStatus.approved
            ? l10n.driverApprovedMessage
            : l10n.driverRejectedByAdminMessage,
      ));
    } catch (_) {
      messenger.showSnackBar(
        buildAppSnackBar(colorScheme, l10n.driverApprovalFailedMessage, isError: true),
      );
    } finally {
      if (mounted) setState(() => _submitting = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final busy = _submitting != null;
    return Row(
      children: [
        if (widget.status != ApprovalStatus.approved)
          Expanded(
            child: FilledButton.icon(
              key: const ValueKey('driver_approve_button'),
              onPressed: busy ? null : () => _set(ApprovalStatus.approved),
              icon: _submitting == ApprovalStatus.approved
                  ? buttonSpinner(colorScheme.onPrimary, size: 16)
                  : const Icon(Icons.check_circle_outline),
              label: Text(l10n.approveTooltip),
            ),
          ),
        if (widget.status == ApprovalStatus.pending) const SizedBox(width: AppSpacing.sm),
        if (widget.status != ApprovalStatus.rejected)
          Expanded(
            child: OutlinedButton.icon(
              key: const ValueKey('driver_reject_button'),
              onPressed: busy ? null : () => _set(ApprovalStatus.rejected),
              style: OutlinedButton.styleFrom(foregroundColor: colorScheme.error),
              icon: _submitting == ApprovalStatus.rejected
                  ? buttonSpinner(colorScheme.error, size: 16)
                  : const Icon(Icons.cancel_outlined),
              label: Text(l10n.rejectTooltip),
            ),
          ),
      ],
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
