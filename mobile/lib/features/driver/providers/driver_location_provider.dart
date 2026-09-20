import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/location_service.dart';
import '../screens/driver_home_screen.dart' show activeDriverOrderProvider;

final locationServiceProvider = Provider<LocationService>((ref) => LocationService());

// Floor on top of the 25m distanceFilter below — bounds worst-case publish
// rate to once per this long even if the device reports rapid small-jitter
// movement, without needing a timer (just drops stream events that arrive
// too soon after the last accepted one).
const minPublishInterval = Duration(seconds: 5);

// Pure so it's directly unit-testable without faking DateTime.now().
bool shouldThrottlePublish({required DateTime now, required DateTime? lastPublishedAt}) {
  return lastPublishedAt != null && now.difference(lastPublishedAt) < minPublishInterval;
}

/// Side-effect provider: while [driverId] has a delivery in flight
/// (`activeDriverOrderProvider` resolves non-null), streams the device's
/// position and publishes it to `orders/{orderId}/driverLocation/current` —
/// what the customer's order-tracking map reads — for that specific active
/// order. Publishes nothing once the driver has no active delivery, so idle
/// drivers don't broadcast location.
final driverLocationSyncProvider = Provider.autoDispose.family<void, String>((ref, driverId) {
  final activeOrder = ref.watch(activeDriverOrderProvider(driverId)).valueOrNull;
  if (activeOrder == null) return;

  final locationService = ref.watch(locationServiceProvider);
  DateTime? lastPublishedAt;
  // A transient GPS error (signal loss, permission hiccup) shouldn't crash
  // this best-effort background sync — onError must be handled explicitly,
  // since an unhandled stream error becomes an uncaught async exception
  // rather than something a per-event .catchError on the publish Future
  // would ever see.
  final subscription = locationService.streamPosition().listen(
        (position) {
          final now = DateTime.now();
          if (shouldThrottlePublish(now: now, lastPublishedAt: lastPublishedAt)) {
            return;
          }
          lastPublishedAt = now;
          locationService
              .publishDriverLocation(driverId: driverId, orderId: activeOrder.id, position: position)
              .catchError((_) {});
        },
        onError: (_) {},
      );
  ref.onDispose(subscription.cancel);
});
