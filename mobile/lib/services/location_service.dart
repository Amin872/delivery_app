import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

import '../core/errors/guard.dart';

class LocationService {
  LocationService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  Future<Position> getCurrentPosition() {
    return guardFuture(() async {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
      return Geolocator.getCurrentPosition();
    });
  }

  Stream<Position> streamPosition() {
    return guardStream(Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 25,
      ),
    ));
  }

  // Writes to two places: orders/{orderId}/driverLocation/current is the
  // customer-facing live-tracking feed (order-scoped, see firestore.rules —
  // only the assigned driver may write it, only while the order is
  // pickedUp/delivering). drivers/{driverId}.lastKnownLocation is kept in
  // sync alongside it purely for AdminDriverDetailScreen's general
  // "last known location" dispatch view — it is no longer read for
  // customer-facing tracking (see DriverTrackingMap).
  Future<void> publishDriverLocation({
    required String driverId,
    required String orderId,
    required Position position,
  }) {
    return guardFuture(() {
      final locationMap = {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      };
      final batch = _db.batch();
      batch.set(
        _db.collection('orders').doc(orderId).collection('driverLocation').doc('current'),
        locationMap,
      );
      batch.update(_db.collection('drivers').doc(driverId), {'lastKnownLocation': locationMap});
      return batch.commit();
    });
  }
}
