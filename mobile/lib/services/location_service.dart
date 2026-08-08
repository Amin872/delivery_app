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

  Future<void> publishDriverLocation({
    required String driverId,
    required Position position,
  }) {
    return guardFuture(() => _db.collection('drivers').doc(driverId).update({
          'lastKnownLocation': {
            'latitude': position.latitude,
            'longitude': position.longitude,
            'updatedAt': DateTime.now().millisecondsSinceEpoch,
          },
        }));
  }
}
