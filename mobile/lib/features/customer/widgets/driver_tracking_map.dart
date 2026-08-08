import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/widgets/app_spinner.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/driver.dart';
import '../screens/customer_home_screen.dart' show firestoreServiceProvider;

final driverLocationProvider = StreamProvider.family<Driver, String>((ref, driverId) {
  return ref.watch(firestoreServiceProvider).watchDriver(driverId);
});

/// Live map of [driverId]'s current position, fed by the `drivers/{uid}`
/// doc that `driverLocationSyncProvider` (driver side) keeps updated while
/// a delivery is in flight. A `ConsumerStatefulWidget` because the map
/// camera needs to re-center via a `GoogleMapController` as new positions
/// arrive, which a stateless rebuild can't drive.
class DriverTrackingMap extends ConsumerStatefulWidget {
  const DriverTrackingMap({required this.driverId, super.key});

  final String driverId;

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
    final driverAsync = ref.watch(driverLocationProvider(widget.driverId));

    ref.listen(driverLocationProvider(widget.driverId), (previous, next) {
      final location = next.valueOrNull?.lastKnownLocation;
      if (location != null) {
        _controller?.animateCamera(
          CameraUpdate.newLatLng(LatLng(location.latitude, location.longitude)),
        );
      }
    });

    final location = driverAsync.valueOrNull?.lastKnownLocation;
    if (location == null) {
      return SizedBox(
        height: 220,
        child: Center(
          child: driverAsync.isLoading
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
        ),
      ),
    );
  }
}
