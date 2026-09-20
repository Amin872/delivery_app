import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:delivery_app/services/location_service.dart';

Position _position({double lat = 33.5, double lng = 36.3}) {
  return Position(
    latitude: lat,
    longitude: lng,
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

void main() {
  test('publishDriverLocation writes the order-scoped current-location doc', () async {
    final firestore = FakeFirebaseFirestore();
    final service = LocationService(firestore: firestore);
    // The driver doc always already exists by the time a delivery is in
    // flight (created at signup, see AuthService.signUp) — mirror that here
    // since publishDriverLocation's batch updates it alongside the new path.
    await firestore.collection('drivers').doc('driver-1').set({'isAvailable': true});

    await service.publishDriverLocation(
      driverId: 'driver-1',
      orderId: 'order-1',
      position: _position(),
    );

    final doc = await firestore
        .collection('orders')
        .doc('order-1')
        .collection('driverLocation')
        .doc('current')
        .get();

    expect(doc.exists, isTrue);
    expect(doc.data()!['latitude'], 33.5);
    expect(doc.data()!['longitude'], 36.3);
    expect(doc.data()!['updatedAt'], isNotNull);
  });

  test('publishDriverLocation also keeps drivers/{driverId}.lastKnownLocation in sync', () async {
    final firestore = FakeFirebaseFirestore();
    final service = LocationService(firestore: firestore);
    await firestore.collection('drivers').doc('driver-1').set({'isAvailable': true});

    await service.publishDriverLocation(
      driverId: 'driver-1',
      orderId: 'order-1',
      position: _position(lat: 34.0, lng: 36.7),
    );

    final driverDoc = await firestore.collection('drivers').doc('driver-1').get();
    final lastKnownLocation = driverDoc.data()!['lastKnownLocation'] as Map<String, dynamic>;
    expect(lastKnownLocation['latitude'], 34.0);
    expect(lastKnownLocation['longitude'], 36.7);
  });

  test('publishDriverLocation overwrites the previous current-location doc on republish',
      () async {
    final firestore = FakeFirebaseFirestore();
    final service = LocationService(firestore: firestore);
    await firestore.collection('drivers').doc('driver-1').set({'isAvailable': true});

    await service.publishDriverLocation(
      driverId: 'driver-1',
      orderId: 'order-1',
      position: _position(lat: 33.0, lng: 36.0),
    );
    await service.publishDriverLocation(
      driverId: 'driver-1',
      orderId: 'order-1',
      position: _position(lat: 33.9, lng: 36.9),
    );

    final snapshot = await firestore
        .collection('orders')
        .doc('order-1')
        .collection('driverLocation')
        .get();
    expect(snapshot.docs, hasLength(1));
    expect(snapshot.docs.first.data()['latitude'], 33.9);
  });
}
