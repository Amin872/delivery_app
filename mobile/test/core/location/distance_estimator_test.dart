import 'package:flutter_test/flutter_test.dart';

import 'package:delivery_app/core/location/distance_estimator.dart';
import 'package:delivery_app/models/coordinates.dart';

void main() {
  group('haversineDistanceMeters', () {
    test('returns 0 for identical coordinates', () {
      const point = Coordinates(latitude: 33.5138, longitude: 36.2765);

      expect(haversineDistanceMeters(point, point), 0);
    });

    test('returns a known real-world distance within a small tolerance', () {
      // Damascus city center to Aleppo city center — roughly 300km
      // straight-line, a well-known approximate figure used only to sanity
      // check the formula, not asserted to sub-meter precision.
      const damascus = Coordinates(latitude: 33.5138, longitude: 36.2765);
      const aleppo = Coordinates(latitude: 36.2021, longitude: 37.1343);

      final distanceKm = haversineDistanceMeters(damascus, aleppo) / 1000;

      expect(distanceKm, greaterThan(280));
      expect(distanceKm, lessThan(320));
    });

    test('is symmetric regardless of argument order', () {
      const a = Coordinates(latitude: 33.5, longitude: 36.3);
      const b = Coordinates(latitude: 33.6, longitude: 36.4);

      expect(haversineDistanceMeters(a, b), haversineDistanceMeters(b, a));
    });
  });

  group('estimateEtaMinutes', () {
    test('returns at least 1 minute for a very short distance', () {
      expect(estimateEtaMinutes(10), 1);
    });

    test('scales roughly linearly with distance', () {
      final shortEta = estimateEtaMinutes(1000);
      final longEta = estimateEtaMinutes(10000);

      expect(longEta, greaterThan(shortEta));
    });
  });

  group('estimateTrip', () {
    test('combines haversine distance and the rough ETA', () {
      const a = Coordinates(latitude: 33.5138, longitude: 36.2765);
      const b = Coordinates(latitude: 33.5300, longitude: 36.2900);

      final trip = estimateTrip(a, b)!;

      expect(trip.distanceMeters, haversineDistanceMeters(a, b));
      expect(trip.etaMinutes, estimateEtaMinutes(trip.distanceMeters));
    });

    test('formats distance as km with one "." decimal', () {
      const trip = TripEstimate(distanceMeters: 2449, etaMinutes: 6);

      expect(trip.distanceKmLabel, '2.4');
    });

    test('is null when either point is unknown', () {
      const a = Coordinates(latitude: 33.5, longitude: 36.3);

      expect(estimateTrip(null, a), isNull);
      expect(estimateTrip(a, null), isNull);
      expect(estimateTrip(null, null), isNull);
    });
  });
}
