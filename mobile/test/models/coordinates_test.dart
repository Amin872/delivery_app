import 'package:flutter_test/flutter_test.dart';

import 'package:delivery_app/models/coordinates.dart';

void main() {
  test('Coordinates stores the latitude/longitude it was constructed with', () {
    const coordinates = Coordinates(latitude: 33.5138, longitude: 36.2765);

    expect(coordinates.latitude, 33.5138);
    expect(coordinates.longitude, 36.2765);
  });

  group('equality', () {
    test('two Coordinates with the same latitude/longitude are equal', () {
      const a = Coordinates(latitude: 33.5138, longitude: 36.2765);
      const b = Coordinates(latitude: 33.5138, longitude: 36.2765);

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('Coordinates with a different latitude are not equal', () {
      const a = Coordinates(latitude: 33.5138, longitude: 36.2765);
      const b = Coordinates(latitude: 34.0, longitude: 36.2765);

      expect(a, isNot(equals(b)));
    });

    test('Coordinates with a different longitude are not equal', () {
      const a = Coordinates(latitude: 33.5138, longitude: 36.2765);
      const b = Coordinates(latitude: 33.5138, longitude: 37.0);

      expect(a, isNot(equals(b)));
    });

    test('a Coordinates is equal to itself', () {
      const a = Coordinates(latitude: 33.5138, longitude: 36.2765);

      expect(a, equals(a));
    });
  });

  group('serialization', () {
    test('Coordinates round-trips through toMap/fromMap', () {
      const coordinates = Coordinates(latitude: 33.5138, longitude: 36.2765);

      final restored = Coordinates.fromMap(coordinates.toMap());

      expect(restored, equals(coordinates));
    });

    test('Coordinates.fromMap accepts integer-valued map fields', () {
      final restored = Coordinates.fromMap({'latitude': 33, 'longitude': 36});

      expect(restored.latitude, 33.0);
      expect(restored.longitude, 36.0);
    });
  });
}
