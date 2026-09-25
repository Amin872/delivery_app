import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/order.dart';
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

// The only statuses firestore.rules' orders/{orderId}/driverLocation
// create/update rule actually accepts a write for (see firestore.rules'
// own `status in ['pickedUp', 'delivering']` condition). driverAssigned is
// deliberately excluded here even though it's a valid "active order" state
// for activeDriverOrderProvider (which also drives the driver home
// screen's active-delivery card, and must keep including driverAssigned
// for that) — starting GPS streaming that early would only produce
// permission-denied writes rejected by the rules, wasting battery/network
// for no effect (D.3 fix). Publishing starts once the driver has actually
// collected the order, not merely been assigned it.
const _gpsPublishableStatuses = {OrderStatus.pickedUp, OrderStatus.delivering};

/// Side-effect provider: while [driverId] has a delivery in flight AND that
/// delivery is in a status `firestore.rules` actually allows publishing
/// for (`_gpsPublishableStatuses`), streams the device's position and
/// publishes it to `orders/{orderId}/driverLocation/current` — what the
/// customer's order-tracking map reads — for that specific active order.
/// Publishes nothing once the driver has no active delivery, or while it's
/// merely `driverAssigned` (not yet physically picked up), so idle/not-yet-
/// dispatched drivers don't broadcast location or attempt writes the rules
/// would reject anyway.
final driverLocationSyncProvider = Provider.autoDispose.family<void, String>((ref, driverId) {
  final activeOrder = ref.watch(activeDriverOrderProvider(driverId)).valueOrNull;
  if (activeOrder == null || !_gpsPublishableStatuses.contains(activeOrder.status)) return;

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
