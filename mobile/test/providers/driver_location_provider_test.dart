import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:delivery_app/features/driver/providers/driver_location_provider.dart';
import 'package:delivery_app/features/driver/screens/driver_home_screen.dart'
    show activeDriverOrderProvider;
import 'package:delivery_app/models/order.dart';
import 'package:delivery_app/services/location_service.dart';

class _PublishCall {
  _PublishCall(this.driverId, this.orderId, this.position);
  final String driverId;
  final String orderId;
  final Position position;
}

class _FakeLocationService extends LocationService {
  _FakeLocationService(this._positions) : super(firestore: FakeFirebaseFirestore());

  final Stream<Position> _positions;
  final List<_PublishCall> published = [];

  @override
  Stream<Position> streamPosition() => _positions;

  @override
  Future<void> publishDriverLocation({
    required String driverId,
    required String orderId,
    required Position position,
  }) async {
    published.add(_PublishCall(driverId, orderId, position));
  }
}

Position _position(double lat) {
  return Position(
    latitude: lat,
    longitude: 36.3,
    timestamp: DateTime.now(),
    accuracy: 5,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}

DeliveryOrder _activeOrder(String id) {
  return DeliveryOrder(
    id: id,
    customerId: 'customer-1',
    vendorId: 'vendor-1',
    driverId: 'driver-1',
    items: const [],
    status: OrderStatus.pickedUp,
    total: 10,
    deliveryAddress: 'addr',
    createdAt: DateTime.now(),
  );
}

void main() {
  group('shouldThrottlePublish (pure)', () {
    test('never throttles the first publish (no prior timestamp)', () {
      expect(
        shouldThrottlePublish(now: DateTime(2026, 1, 1), lastPublishedAt: null),
        isFalse,
      );
    });

    test('throttles a publish arriving inside the window', () {
      final last = DateTime(2026, 1, 1, 12, 0, 0);
      expect(
        shouldThrottlePublish(now: last.add(const Duration(seconds: 3)), lastPublishedAt: last),
        isTrue,
      );
    });

    test('does not throttle once the window has fully elapsed', () {
      final last = DateTime(2026, 1, 1, 12, 0, 0);
      expect(
        shouldThrottlePublish(now: last.add(minPublishInterval), lastPublishedAt: last),
        isFalse,
      );
      expect(
        shouldThrottlePublish(
          now: last.add(minPublishInterval + const Duration(seconds: 1)),
          lastPublishedAt: last,
        ),
        isFalse,
      );
    });
  });

  test('publishes to the currently active order id, not a bare driver doc', () async {
    final positions = StreamController<Position>();
    final fakeService = _FakeLocationService(positions.stream);

    final container = ProviderContainer(overrides: [
      locationServiceProvider.overrideWithValue(fakeService),
      activeDriverOrderProvider
          .overrideWith((ref, driverId) => Stream.value(_activeOrder('order-1'))),
    ]);
    addTearDown(container.dispose);

    container.listen(driverLocationSyncProvider('driver-1'), (previous, next) {});
    await pumpEventQueue();

    positions.add(_position(33.5));
    await pumpEventQueue();

    expect(fakeService.published, hasLength(1));
    expect(fakeService.published.single.orderId, 'order-1');
    expect(fakeService.published.single.driverId, 'driver-1');
  });

  test('publishes nothing while the driver has no active order', () async {
    final positions = StreamController<Position>();
    final fakeService = _FakeLocationService(positions.stream);

    final container = ProviderContainer(overrides: [
      locationServiceProvider.overrideWithValue(fakeService),
      activeDriverOrderProvider.overrideWith((ref, driverId) => Stream.value(null)),
    ]);
    addTearDown(container.dispose);

    container.listen(driverLocationSyncProvider('driver-1'), (previous, next) {});
    await pumpEventQueue();

    positions.add(_position(33.5));
    await pumpEventQueue();

    expect(fakeService.published, isEmpty);
  });
}
