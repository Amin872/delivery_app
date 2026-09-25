import 'package:flutter_test/flutter_test.dart';

import 'package:delivery_app/core/location/location_matcher.dart';
import 'package:delivery_app/models/city.dart';
import 'package:delivery_app/models/coordinates.dart';
import 'package:delivery_app/models/governorate.dart';
import 'package:delivery_app/models/neighborhood.dart';
import 'package:delivery_app/services/geocoding_service.dart';

// Synthetic, generic test fixtures ONLY — same convention as
// location_matcher_test.dart's own matchLocation coverage: no real Syrian
// governorate/city/neighbourhood data is inserted merely for these tests.
const _governorate = GovernorateOption(
  id: 'test_governorate',
  nameAr: 'محافظة الاختبار',
  nameEn: 'Test Governorate',
  enabled: true,
  order: 0,
);

const _city = CityOption(
  id: 'test_city',
  nameAr: 'مدينة الاختبار',
  nameEn: 'Test City',
  enabled: true,
  order: 0,
  governorateId: 'test_governorate',
);
const _otherCity = CityOption(
  id: 'test_city_other',
  nameAr: 'مدينة أخرى',
  nameEn: 'Other City',
  enabled: true,
  order: 1,
  governorateId: 'test_governorate',
);

const _neighborhood = NeighborhoodOption(
  id: 'test_neighborhood',
  nameAr: 'حي الاختبار',
  nameEn: 'Test Neighborhood',
  cityId: 'test_city',
  enabled: true,
  order: 0,
);
const _neighborhoodInOtherCity = NeighborhoodOption(
  id: 'test_neighborhood_other',
  nameAr: 'حي الاختبار',
  nameEn: 'Test Neighborhood',
  cityId: 'test_city_other',
  enabled: true,
  order: 0,
);

const _coordinates = Coordinates(latitude: 33.5, longitude: 36.3);

void main() {
  group('matchNeighborhoodLocation — exact matching', () {
    test('resolves governorate, city, and neighborhood via exact English name match', () {
      final result = matchNeighborhoodLocation(
        geocodeResult: const GeocodeResult(
          coordinates: _coordinates,
          region: 'Test Governorate',
          city: 'Test City',
          neighborhood: 'Test Neighborhood',
        ),
        governorates: const [_governorate],
        cities: const [_city],
        neighborhoods: const [_neighborhood],
      );

      expect(result.governorate?.id, 'test_governorate');
      expect(result.city?.id, 'test_city');
      expect(result.neighborhood?.id, 'test_neighborhood');
      expect(result.confidence, MatchConfidence.exact);
    });

    test('resolves via exact Arabic name match', () {
      final result = matchNeighborhoodLocation(
        geocodeResult: const GeocodeResult(
          coordinates: _coordinates,
          region: 'محافظة الاختبار',
          city: 'مدينة الاختبار',
          neighborhood: 'حي الاختبار',
        ),
        governorates: const [_governorate],
        cities: const [_city],
        neighborhoods: const [_neighborhood],
      );

      expect(result.neighborhood?.id, 'test_neighborhood');
    });
  });

  group('matchNeighborhoodLocation — hierarchy', () {
    test('only matches a neighborhood whose cityId equals the matched city', () {
      final result = matchNeighborhoodLocation(
        geocodeResult: const GeocodeResult(
          coordinates: _coordinates,
          city: 'Test City',
          // Same neighbourhood name exists under a different city — must
          // not cross over.
          neighborhood: 'Test Neighborhood',
        ),
        governorates: const [],
        cities: const [_city, _otherCity],
        neighborhoods: const [_neighborhoodInOtherCity],
      );

      expect(result.city?.id, 'test_city');
      expect(result.neighborhood, isNull);
    });

    test('city with no matched governorate still resolves', () {
      final result = matchNeighborhoodLocation(
        geocodeResult: const GeocodeResult(coordinates: _coordinates, city: 'Test City'),
        governorates: const [],
        cities: const [_city],
        neighborhoods: const [_neighborhood],
      );

      expect(result.city?.id, 'test_city');
      expect(result.governorate, isNull);
    });
  });

  group('matchNeighborhoodLocation — no match', () {
    test('returns none-confidence when nothing matches', () {
      final result = matchNeighborhoodLocation(
        geocodeResult: const GeocodeResult(coordinates: _coordinates, city: 'Unknown Place'),
        governorates: const [_governorate],
        cities: const [_city],
        neighborhoods: const [_neighborhood],
      );

      expect(result.city, isNull);
      expect(result.confidence, MatchConfidence.none);
    });

    test('skips neighbourhood matching entirely when no city matched', () {
      final result = matchNeighborhoodLocation(
        geocodeResult: const GeocodeResult(
          coordinates: _coordinates,
          neighborhood: 'Test Neighborhood',
        ),
        governorates: const [],
        cities: const [],
        neighborhoods: const [_neighborhood],
      );

      expect(result.neighborhood, isNull);
      expect(result.reasons.any((r) => r.contains('skipped')), isTrue);
    });

    test('an empty GeocodeResult resolves to none', () {
      final result = matchNeighborhoodLocation(
        geocodeResult: const GeocodeResult(coordinates: _coordinates),
        governorates: const [_governorate],
        cities: const [_city],
        neighborhoods: const [_neighborhood],
      );

      expect(result.governorate, isNull);
      expect(result.city, isNull);
      expect(result.neighborhood, isNull);
      expect(result.confidence, MatchConfidence.none);
    });
  });
}
