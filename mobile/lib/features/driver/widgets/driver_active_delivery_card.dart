import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart' show launchUrl;

import '../../../core/contact/phone_launcher.dart';
import '../../../core/l10n/enum_labels.dart';
import '../../../core/location/navigation_launcher.dart' show UrlLaunchFn;
import '../../../core/location/distance_estimator.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_spinner.dart';
import '../../../core/widgets/image_picker_avatar.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/coordinates.dart';
import '../../../models/order.dart';
import 'driver_order_summary.dart';

/// The delivery the driver currently holds: status, pickup and drop-off,
/// notes, items and the cash total to collect, plus the proof photo and
/// "Move to …" action. Purely presentational — DriverHomeScreen still owns
/// the lifecycle decision (which status is next, whether a proof photo is
/// needed) and the advance/upload calls, and passes them in.
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
    final next = nextStatus;
    final stop = driverNextStop(order);
    final stopCoordinates = stop?.coordinates;
    final toPickup = stop?.kind == DriverStopKind.pickup;
    final estimate = estimateTrip(driverPosition, stopCoordinates);

    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.orderLabel(order.id), style: textTheme.titleMedium),
            Text(orderStatusLabel(context, order.status), style: textTheme.bodyMedium),
            DriverOrderLocations(order: order),
            // Straight-line estimate at an assumed average speed — labeled
            // "≈ … estimated", never presented as a routed/traffic ETA.
            if (estimate != null)
              Padding(
                key: const ValueKey('driver_trip_estimate'),
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Row(
                  children: [
                    const Icon(Icons.schedule_outlined, size: 16),
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
            if (fetchCustomerPhone != null && driverCanCallCustomer(order))
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: PhoneCallAction(
                  key: const ValueKey('driver_call_customer'),
                  fetchPhone: fetchCustomerPhone!,
                  launch: launchUrlForCall,
                  builder: (context, onPressed, busy) => OutlinedButton.icon(
                    onPressed: onPressed,
                    icon: busy
                        ? buttonSpinner(Theme.of(context).colorScheme.primary, size: 16)
                        : const Icon(Icons.call_outlined),
                    label: Text(l10n.callCustomerButton),
                  ),
                ),
              ),
            if (order.deliveryInstructions != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 16),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: Text(order.deliveryInstructions!)),
                  ],
                ),
              ),
            if (order.driverNote != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Row(
                  children: [
                    const Icon(Icons.sticky_note_2_outlined, size: 16),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: Text(order.driverNote!)),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            DriverOrderItemsBreakdown(order: order),
            if (needsProof)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.md),
                child: Row(
                  children: [
                    ImagePickerAvatar(radius: 28, localFile: proofImage, onPicked: onProofPicked),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: Text(l10n.proofOfDeliveryHint)),
                  ],
                ),
              ),
            if (next != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.md),
                child: FilledButton(
                  onPressed: (advancing || !canAdvance) ? null : onAdvance,
                  child: advancing
                      ? buttonSpinner(Theme.of(context).colorScheme.onPrimary, size: 16)
                      : Text(l10n.advanceStatusButtonLabel(orderStatusLabel(context, next))),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
