import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/widgets/app_spinner.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/driver.dart';
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

/// Live map of the driver currently delivering [orderId], fed by
/// `orders/{orderId}/driverLocation/current` — the order-scoped feed that
/// `driverLocationSyncProvider` (driver side) keeps updated while that
/// specific delivery is in flight. A `ConsumerStatefulWidget` because the
/// map camera needs to re-center via a `GoogleMapController` as new
/// positions arrive, which a stateless rebuild can't drive.
class DriverTrackingMap extends ConsumerStatefulWidget {
  const DriverTrackingMap({required this.orderId, super.key});

  final String orderId;

  @override
  ConsumerState<DriverTrackingMap> createState() => _DriverTrackingMapState();
}

class _DriverTrackingMapState extends ConsumerState<DriverTrackingMap> {
  GoogleMapController? _controller;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final locationAsync = ref.watch(driverOrderLocationProvider(widget.orderId));

    ref.listen(driverOrderLocationProvider(widget.orderId), (previous, next) {
      final location = next.valueOrNull;
      if (location != null) {
        _controller?.animateCamera(
          CameraUpdate.newLatLng(LatLng(location.latitude, location.longitude)),
        );
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 220,
        child: GoogleMap(
          initialCameraPosition: CameraPosition(target: position, zoom: 15),
          onMapCreated: (controller) => _controller = controller,
          markers: {Marker(markerId: const MarkerId('driver'), position: position)},
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          style: Theme.of(context).brightness == Brightness.dark ? _darkMapStyle : null,
        ),
      ),
    );
  }
}
