import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/location/distance_estimator.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_spinner.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/coordinates.dart';
import '../../../models/driver.dart';
import '../../../models/order.dart';
import '../screens/customer_home_screen.dart' show firestoreServiceProvider;

final driverOrderLocationProvider =
    StreamProvider.autoDispose.family<DriverLocation?, String>((ref, orderId) {
  return ref.watch(firestoreServiceProvider).watchOrderDriverLocation(orderId);
});

// GoogleMap tiles aren't `Theme`-aware — without this the map renders as a
// bright rectangle inside an otherwise dark screen. Standard Google Maps
// "Night mode" style JSON (widely published in Google's own Maps styling
// docs), applied only when the app is actually in dark mode.
const _darkMapStyle = '''
[
  {"elementType": "geometry", "stylers": [{"color": "#212121"}]},
  {"elementType": "labels.icon", "stylers": [{"visibility": "off"}]},
  {"elementType": "labels.text.fill", "stylers": [{"color": "#757575"}]},
  {"elementType": "labels.text.stroke", "stylers": [{"color": "#212121"}]},
  {"featureType": "administrative", "elementType": "geometry", "stylers": [{"color": "#757575"}]},
  {"featureType": "poi", "elementType": "geometry", "stylers": [{"color": "#2c2c2c"}]},
  {"featureType": "poi.park", "elementType": "geometry", "stylers": [{"color": "#1b1b1b"}]},
  {"featureType": "road", "elementType": "geometry.fill", "stylers": [{"color": "#2c2c2c"}]},
  {"featureType": "road", "elementType": "geometry.stroke", "stylers": [{"color": "#000000"}]},
  {"featureType": "road.arterial", "elementType": "geometry", "stylers": [{"color": "#373737"}]},
  {"featureType": "road.highway", "elementType": "geometry", "stylers": [{"color": "#3c3c3c"}]},
  {"featureType": "transit", "elementType": "geometry", "stylers": [{"color": "#2f2f2f"}]},
  {"featureType": "water", "elementType": "geometry", "stylers": [{"color": "#000000"}]},
  {"featureType": "water", "elementType": "labels.text.fill", "stylers": [{"color": "#3d3d3d"}]}
]
''';

/// Live map of the driver currently delivering [order], fed by
/// `orders/{orderId}/driverLocation/current` — the order-scoped feed that
/// `driverLocationSyncProvider` (driver side) keeps updated while that
/// specific delivery is in flight. A `ConsumerStatefulWidget` because the
/// map camera needs to re-center via a `GoogleMapController` as new
/// positions arrive, which a stateless rebuild can't drive.
///
/// Also shows a straight-line distance/rough ETA (when [order] has a
/// delivery pin to measure against — see models/order.dart's
/// deliveryLatitude/deliveryLongitude), purely additive over the live
/// position itself. The "call driver" action is not part of the map: it
/// lives on OrderTrackingScreen so it shows for the whole contact window,
/// whether or not a driver position has arrived yet.
class DriverTrackingMap extends ConsumerStatefulWidget {
  const DriverTrackingMap({required this.order, super.key});

  final DeliveryOrder order;

  @override
  ConsumerState<DriverTrackingMap> createState() => _DriverTrackingMapState();
}

/// Driver marker plus, when the order has a drop-off pin, a destination
/// marker. Pure (no map controller) so it's unit-testable.
Set<Marker> trackingMarkers(LatLng driver, LatLng? destination, {String? destinationTitle}) {
  return {
    Marker(markerId: const MarkerId('driver'), position: driver),
    if (destination != null)
      Marker(
        markerId: const MarkerId('drop_off'),
        position: destination,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: InfoWindow(title: destinationTitle),
      ),
  };
}

/// Smallest bounds containing both points, in either order.
LatLngBounds trackingBounds(LatLng a, LatLng b) {
  return LatLngBounds(
    southwest: LatLng(math.min(a.latitude, b.latitude), math.min(a.longitude, b.longitude)),
    northeast: LatLng(math.max(a.latitude, b.latitude), math.max(a.longitude, b.longitude)),
  );
}

class _DriverTrackingMapState extends ConsumerState<DriverTrackingMap> {
  GoogleMapController? _controller;
  bool _fittedBothPoints = false;

  LatLng? get _destination {
    final drop = widget.order.deliveryCoordinates;
    return drop == null ? null : LatLng(drop.latitude, drop.longitude);
  }

  Future<void> _fitBoth(LatLng driver, LatLng destination) async {
    try {
      await _controller?.animateCamera(
        CameraUpdate.newLatLngBounds(trackingBounds(driver, destination), 48),
      );
      _fittedBothPoints = true;
    } catch (_) {
      // Map not laid out yet — the next location update retries.
    }
  }

  // Keeps driver and drop-off in view without re-animating on every GPS
  // tick: fit both once, then only refit if the driver leaves the visible
  // area. With no drop-off pin, follow the driver as before.
  Future<void> _onDriverMoved(LatLng driver) async {
    final controller = _controller;
    if (controller == null) return;
    final destination = _destination;
    if (destination == null) {
      await controller.animateCamera(CameraUpdate.newLatLng(driver));
      return;
    }
    if (!_fittedBothPoints) {
      await _fitBoth(driver, destination);
      return;
    }
    try {
      final visible = await controller.getVisibleRegion();
      if (!visible.contains(driver)) await _fitBoth(driver, destination);
    } catch (_) {}
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final orderId = widget.order.id;
    final locationAsync = ref.watch(driverOrderLocationProvider(orderId));

    ref.listen(driverOrderLocationProvider(orderId), (previous, next) {
      final location = next.valueOrNull;
      if (location != null) {
        _onDriverMoved(LatLng(location.latitude, location.longitude));
      }
    });

    final location = locationAsync.valueOrNull;
    if (location == null) {
      return SizedBox(
        height: 220,
        child: Center(
          child: locationAsync.isLoading
              ? screenSpinner(context)
              : Text(l10n.waitingForDriverLocationMessage),
        ),
      );
    }

    final position = LatLng(location.latitude, location.longitude);
    final destination = _destination;
    final estimate = estimateTrip(
      Coordinates(latitude: location.latitude, longitude: location.longitude),
      widget.order.deliveryCoordinates,
    );

    return ClipRRect(
      borderRadius: AppRadius.medium,
      child: SizedBox(
        height: 220,
        child: Stack(
          children: [
            GoogleMap(
              initialCameraPosition: CameraPosition(target: position, zoom: 15),
              onMapCreated: (controller) {
                _controller = controller;
                if (destination != null) _fitBoth(position, destination);
              },
              markers: trackingMarkers(position, destination, destinationTitle: l10n.dropOffMarkerTitle),
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              style: Theme.of(context).brightness == Brightness.dark ? _darkMapStyle : null,
            ),
            if (estimate != null)
              Positioned(
                left: AppSpacing.sm,
                top: AppSpacing.sm,
                child: _InfoPill(
                  text: '${l10n.distanceAwayLabel(estimate.distanceKmLabel)}'
                      ' · ${l10n.etaLabel(estimate.etaMinutes)}',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: VendorPalette.surfaceContainer.withValues(alpha: 0.92),
        borderRadius: AppRadius.extraLarge,
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: VendorPalette.textPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
