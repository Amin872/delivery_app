import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart' show launchUrl;

import '../../../core/contact/phone_launcher.dart';
import '../../../core/format/display_formatters.dart';
import '../../../core/l10n/enum_labels.dart';
import '../../../core/location/navigation_launcher.dart' show UrlLaunchFn;
import '../../../core/location/distance_estimator.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_spinner.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/coordinates.dart';
import '../../../models/order.dart';
import 'driver_order_summary.dart';
import 'driver_proof_picker.dart';

/// The delivery the driver currently holds, as one tinted card in sections:
/// the order reference and status; the route (stops, estimate, navigate);
/// calling the customer; notes; items; the proof photo; the totals to
/// collect; and the "Move to …" action. Purely presentational —
/// DriverHomeScreen still owns the lifecycle decision (which status is
/// next, whether a proof photo is needed) and the advance/upload calls,
/// and passes them in.
class DriverActiveDeliveryCard extends StatelessWidget {
  const DriverActiveDeliveryCard({
    required this.order,
    required this.nextStatus,
    required this.needsProof,
    required this.canAdvance,
    required this.advancing,
    required this.proofImage,
    required this.onProofPicked,
    required this.onAdvance,
    this.driverPosition,
    this.onNavigate,
    this.fetchCustomerPhone,
    this.launchUrlForCall = launchUrl,
    super.key,
  });

  final DeliveryOrder order;
  // Null when the driver has no further step to take on this order.
  final OrderStatus? nextStatus;
  final bool needsProof;
  final bool canAdvance;
  final bool advancing;
  final File? proofImage;
  final ValueChanged<File> onProofPicked;
  final VoidCallback onAdvance;
  // The driver's recent position (see recentDriverPosition), or null — only
  // used for the approximate distance/ETA line.
  final Coordinates? driverPosition;
  // Opens external navigation to the next stop; the screen owns the launch
  // and its error feedback. Null hides the navigate button.
  final ValueChanged<Coordinates>? onNavigate;
  // Asks the getOrderContact callable for this order's customer's number
  // (the screen supplies it). Null hides the call button.
  final Future<String> Function()? fetchCustomerPhone;
  // Injectable dialer launch, for tests.
  final UrlLaunchFn launchUrlForCall;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final next = nextStatus;
    final stop = driverNextStop(order);
    final stopCoordinates = stop?.coordinates;
    final toPickup = stop?.kind == DriverStopKind.pickup;
    final estimate = estimateTrip(driverPosition, stopCoordinates);
    final canCall = fetchCustomerPhone != null && driverCanCallCustomer(order);
    final instructions = order.deliveryInstructions;
    final driverNote = order.driverNote;
    final hasNotes = (instructions?.isNotEmpty ?? false) || (driverNote?.isNotEmpty ?? false);

    const sectionGap = Divider(height: AppSpacing.xl);

    return Card(
      color: colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Order: short reference + status chip (the chip drops under
            // the reference when both don't fit).
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                Text(l10n.orderLabel(displayOrderId(order.id)), style: textTheme.titleMedium),
                OrderStatusChip(status: order.status),
              ],
            ),
            // 2. Route.
            DriverOrderLocations(order: order),
            // Straight-line estimate at an assumed average speed — labeled
            // "≈ … estimated", never presented as a routed/traffic ETA.
            if (estimate != null)
              Padding(
                key: const ValueKey('driver_trip_estimate'),
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.schedule_outlined, size: AppSizes.iconSmall, color: AppColors.textSecondary(colorScheme)),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        toPickup
                            ? l10n.tripEstimateToPickup(estimate.distanceKmLabel, estimate.etaMinutes)
                            : l10n.tripEstimateToDropOff(estimate.distanceKmLabel, estimate.etaMinutes),
                        style: textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            if (stopCoordinates != null && onNavigate != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: OutlinedButton.icon(
                  key: ValueKey(toPickup ? 'navigate_to_pickup' : 'navigate_to_drop_off'),
                  onPressed: () => onNavigate!(stopCoordinates),
                  icon: const Icon(Icons.directions_outlined),
                  label: Text(toPickup ? l10n.navigateToPickupButton : l10n.navigateToDropOffButton),
                ),
              ),
            // 3. Customer contact.
            if (canCall)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: PhoneCallAction(
                  key: const ValueKey('driver_call_customer'),
                  fetchPhone: fetchCustomerPhone!,
                  launch: launchUrlForCall,
                  builder: (context, onPressed, busy) => OutlinedButton.icon(
                    onPressed: onPressed,
                    icon: busy
                        ? buttonSpinner(colorScheme.primary, size: AppSizes.iconSmall)
                        : const Icon(Icons.call_outlined),
                    label: Text(l10n.callCustomerButton),
                  ),
                ),
              ),
            // 4. Notes.
            if (hasNotes) ...[
              sectionGap,
              if (instructions?.isNotEmpty ?? false)
                _NoteLine(icon: Icons.info_outline, label: l10n.orderDeliveryInstructionsLabel, text: instructions!),
              if (driverNote?.isNotEmpty ?? false)
                _NoteLine(icon: Icons.sticky_note_2_outlined, label: l10n.orderDriverNoteLabel, text: driverNote!),
            ],
            // 5. Items.
            sectionGap,
            _SectionTitle(l10n.orderItemsTitle),
            InfoCard(children: [DriverOrderItems(order: order)]),
            // 6. Proof (only on the final hop).
            if (needsProof) ...[
              sectionGap,
              _SectionTitle(l10n.proofSectionTitle),
              DriverProofPicker(file: proofImage, onPicked: onProofPicked),
            ],
            // 7. Totals.
            const SizedBox(height: AppSpacing.md),
            InfoCard(children: [DriverOrderTotals(order: order)]),
            // 8. The next step.
            if (next != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.lg),
                child: FilledButton(
                  key: const ValueKey('driver_advance_button'),
                  onPressed: (advancing || !canAdvance) ? null : onAdvance,
                  child: advancing
                      ? buttonSpinner(colorScheme.onPrimary, size: AppSizes.iconSmall)
                      : Text(
                          l10n.advanceStatusButtonLabel(orderStatusLabel(context, next)),
                          maxLines: 2,
                          textAlign: TextAlign.center,
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Semantics(header: true, child: Text(title, style: Theme.of(context).textTheme.labelLarge)),
    );
  }
}

/// A delivery note: icon, a small label, and the full text under it.
class _NoteLine extends StatelessWidget {
  const _NoteLine({required this.icon, required this.label, required this.text});

  final IconData icon;
  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final secondary = AppColors.textSecondary(Theme.of(context).colorScheme);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: AppSizes.iconSmall, color: secondary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: textTheme.bodySmall?.copyWith(color: secondary)),
                Text(text, style: textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
