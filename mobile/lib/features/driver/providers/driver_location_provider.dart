import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/location_service.dart';
import '../screens/driver_home_screen.dart' show activeDriverOrderProvider;

final locationServiceProvider = Provider<LocationService>((ref) => LocationService());

/// Side-effect provider: while [driverId] has a delivery in flight
/// (`activeDriverOrderProvider` resolves non-null), streams the device's
/// position and publishes it to `drivers/{driverId}.lastKnownLocation` —
/// what the customer's order-tracking map reads. Publishes nothing once the
/// driver has no active delivery, so idle drivers don't broadcast location.
final driverLocationSyncProvider = Provider.family<void, String>((ref, driverId) {
  final hasActiveOrder = ref.watch(activeDriverOrderProvider(driverId)).valueOrNull != null;
  if (!hasActiveOrder) return;

  final locationService = ref.watch(locationServiceProvider);
  final subscription = locationService.streamPosition().listen(
        (position) => locationService
            .publishDriverLocation(driverId: driverId, position: position)
            .catchError((_) {}),
      );
  ref.onDispose(subscription.cancel);
});
