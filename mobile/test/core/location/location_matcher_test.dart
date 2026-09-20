import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:delivery_app/core/location/location_matcher.dart';
import 'package:delivery_app/models/city.dart';
import 'package:delivery_app/models/coordinates.dart';
import 'package:delivery_app/models/district.dart';
import 'package:delivery_app/models/governorate.dart';
import 'package:delivery_app/services/geocoding_service.dart';

// Synthetic, generic test fixtures ONLY — per the Locations Phase 3
// instructions, no real Syrian governorate/city/district data is inserted
// merely for these tests.
const _governorateA = GovernorateOption(
  id: 'test_governorate_a',
  nameAr: 'محافظة الاختبار أ',
  nameEn: 'Test Governorate A',
  enabled: true,
  order: 0,
);
const _governorateB = GovernorateOption(
  id: 'test_governorate_b',
  nameAr: 'محافظة الاختبار ب',
  nameEn: 'Test Governorate B',
  enabled: true,
  order: 1,
);

const _city = CityOption(
  id: 'test_city',
  nameAr: 'مدينة الاختبار',
  nameEn: 'Test City',
  enabled: true,
  order: 0,
  governorateId: 'test_governorate_a',
);
const _cityNoGovernorate = CityOption(
  id: 'test_city_no_governorate',
  nameAr: 'مدينة بلا محافظة',
  nameEn: 'City Without Governorate',
  enabled: true,
  order: 1,
);
const _cityDisabled = CityOption(
  id: 'test_city_disabled',
  nameAr: 'مدينة معطلة',
  nameEn: 'Disabled Test City',
  enabled: false,
  order: 2,
  governorateId: 'test_governorate_a',
);
const _cityInGovernorateB = CityOption(
  id: 'test_city_in_b',
  nameAr: 'مدينة النزاع',
  nameEn: 'Conflict City',
  enabled: true,
  order: 3,
  governorateId: 'test_governorate_b',
);
const _cityAmbiguousOne = CityOption(
  id: 'test_city_ambiguous_1',
  nameAr: 'مدينة مكررة',
  nameEn: 'Duplicate City',
  enabled: true,
  order: 4,
);
const _cityAmbiguousTwo = CityOption(
  id: 'test_city_ambiguous_2',
  nameAr: 'مدينة مكررة',
  nameEn: 'Duplicate City',
  enabled: true,
  order: 5,
);

const _district = DistrictOption(
  id: 'test_district',
  nameAr: 'حي الاختبار',
  nameEn: 'Test District',
  cityId: 'test_city',
  enabled: true,
  order: 0,
);
const _districtWrongCity = DistrictOption(
  id: 'test_district_wrong_city',
  nameAr: 'حي الاختبار',
  nameEn: 'Test District',
  cityId: 'test_city_no_governorate',
  enabled: true,
  order: 0,
);

GeocodeResult _geocode({String? region, String? city, String? district}) {
  return GeocodeResult(
    coordinates: const Coordinates(latitude: 0, longitude: 0),
    region: region,
    city: city,
    district: district,
  );
}

/// Inserts an Arabic diacritic (FATHA, U+064E) between every character of
/// [base] — deterministically produces a heavily-diacritized variant that
/// must normalize back to the same value as [base] itself, without hand-
/// typing real Arabic vowelization (and the risk of a typo silently
/// breaking the test).
String _withDiacritics(String base) => base.split('').join('َ');

void main() {
  group('normalizeLocationName', () {
    test('strips Arabic diacritics (tashkeel)', () {
      const base = 'مدينة الاختبار';
      expect(normalizeLocationName(_withDiacritics(base)), normalizeLocationName(base));
    });

    test('case-folds Latin text', () {
      expect(normalizeLocationName('TEST CITY'), normalizeLocationName('test city'));
      expect(normalizeLocationName('Test City'), 'test city');
    });

    test('collapses repeated whitespace and trims', () {
      expect(normalizeLocationName('  Test    City  '), 'test city');
    });

    test('normalizes punctuation (hyphen) to whitespace', () {
      expect(normalizeLocationName('Al-Mazzeh'), normalizeLocationName('Al Mazzeh'));
    });

    test('never treats Arabic and Latin text as equal — no translation occurs', () {
      expect(normalizeLocationName('Test City'), isNot(normalizeLocationName('مدينة الاختبار')));
    });
  });

  group('matchLocation — exact name matching', () {
    test('1. exact Arabic city match', () {
      final result = matchLocation(
        geocodeResult: _geocode(city: 'مدينة الاختبار'),
        governorates: const [_governorateA],
        cities: const [_city],
        districts: const [],
      );

      expect(result.city?.id, _city.id);
      expect(result.confidence, MatchConfidence.strong);
    });

    test('2. exact English city match', () {
      final result = matchLocation(
        geocodeResult: _geocode(city: 'Test City'),
        governorates: const [_governorateA],
        cities: const [_city],
        districts: const [],
      );

      expect(result.city?.id, _city.id);
    });

    test('3. Arabic diacritics normalization still resolves the city', () {
      final result = matchLocation(
        geocodeResult: _geocode(city: _withDiacritics('مدينة الاختبار')),
        governorates: const [_governorateA],
        cities: const [_city],
        districts: const [],
      );

      expect(result.city?.id, _city.id);
    });

    test('4. English case normalization still resolves the city', () {
      final result = matchLocation(
        geocodeResult: _geocode(city: 'TEST CITY'),
        governorates: const [_governorateA],
        cities: const [_city],
        districts: const [],
      );

      expect(result.city?.id, _city.id);
    });
  });

  group('matchLocation — district hierarchy', () {
    test('5. exact district match constrained to its city yields exact confidence', () {
      final result = matchLocation(
        geocodeResult: _geocode(city: 'Test City', district: 'Test District'),
        governorates: const [_governorateA],
        cities: const [_city],
        districts: const [_district],
      );

      expect(result.city?.id, _city.id);
      expect(result.district?.id, _district.id);
      expect(result.confidence, MatchConfidence.exact);
    });

    test('6. a district belonging to a different city must NOT match', () {
      final result = matchLocation(
        geocodeResult: _geocode(city: 'Test City', district: 'Test District'),
        governorates: const [_governorateA],
        cities: const [_city, _cityNoGovernorate],
        // Only the wrong-city district is present — the correctly-scoped
        // one from test 5 is absent here on purpose.
        districts: const [_districtWrongCity],
      );

      expect(result.city?.id, _city.id);
      expect(result.district, isNull);
      // City matched exactly on its own merits; the unrelated district
      // text doesn't downgrade that.
      expect(result.confidence, MatchConfidence.strong);
    });
  });

  group('matchLocation — governorate hierarchy', () {
    test('7. a city is excluded when its own governorateId conflicts with the matched governorate',
        () {
      final result = matchLocation(
        geocodeResult: _geocode(region: 'Test Governorate A', city: 'Conflict City'),
        governorates: const [_governorateA, _governorateB],
        // _cityInGovernorateB's name matches the geocode city text, but it
        // belongs to governorate B while the region text resolved to A.
        cities: const [_cityInGovernorateB],
        districts: const [],
      );

      expect(result.governorate?.id, _governorateA.id);
      expect(result.city, isNull);
    });

    test('a city consistent with the matched governorate still matches', () {
      final result = matchLocation(
        geocodeResult: _geocode(region: 'Test Governorate A', city: 'Test City'),
        governorates: const [_governorateA, _governorateB],
        cities: const [_city],
        districts: const [],
      );

      expect(result.governorate?.id, _governorateA.id);
      expect(result.city?.id, _city.id);
    });

    test('8. a city with no governorateId can still match, even with no region signal', () {
      final result = matchLocation(
        geocodeResult: _geocode(city: 'City Without Governorate'),
        governorates: const [_governorateA],
        cities: const [_cityNoGovernorate],
        districts: const [],
      );

      expect(result.city?.id, _cityNoGovernorate.id);
      expect(result.governorate, isNull);
    });
  });

  group('matchLocation — disabled locations', () {
    test('9. a disabled city can still be resolved by the matcher', () {
      final result = matchLocation(
        geocodeResult: _geocode(city: 'Disabled Test City'),
        governorates: const [],
        cities: const [_cityDisabled],
        districts: const [],
      );

      expect(result.city?.id, _cityDisabled.id);
      expect(result.city?.enabled, isFalse);
    });
  });

  group('matchLocation — no match / ambiguity', () {
    test('10. no match anywhere returns MatchConfidence.none', () {
      final result = matchLocation(
        geocodeResult: _geocode(city: 'Nowhere At All'),
        governorates: const [_governorateA],
        cities: const [_city],
        districts: const [_district],
      );

      expect(result.governorate, isNull);
      expect(result.city, isNull);
      expect(result.district, isNull);
      expect(result.confidence, MatchConfidence.none);
    });

    test('11. ambiguous candidates are not silently resolved to one of them', () {
      final result = matchLocation(
        geocodeResult: _geocode(city: 'Duplicate City'),
        governorates: const [],
        cities: const [_cityAmbiguousOne, _cityAmbiguousTwo],
        districts: const [],
      );

      expect(result.city, isNull);
      expect(result.confidence, MatchConfidence.possible);
      expect(result.reasons.any((r) => r.contains('ambiguous')), isTrue);
    });
  });

  group('matchLocation — Arabic/English display integrity', () {
    test('12. matched entity display names remain exactly the Firestore values', () {
      final result = matchLocation(
        geocodeResult: _geocode(city: 'مدينة الاختبار'),
        governorates: const [],
        cities: const [_city],
        districts: const [],
      );

      expect(result.city?.nameAr, 'مدينة الاختبار');
      expect(result.city?.nameEn, 'Test City');
    });

    test('13. matching an Arabic-only signal never translates or invents an English name', () {
      final result = matchLocation(
        geocodeResult: _geocode(city: 'مدينة الاختبار'),
        governorates: const [],
        cities: const [_city],
        districts: const [],
      );

      // nameEn came from Firestore data, not derived from the Arabic input.
      expect(result.city?.nameEn, 'Test City');
    });
  });

  group('source-level guarantees', () {
    late String source;

    setUpAll(() {
      source = File('lib/core/location/location_matcher.dart').readAsStringSync();
    });

    test('14. no hardcoded Syrian city/district names exist in the matcher implementation', () {
      const realPlaceNames = [
        'Damascus', 'Aleppo', 'Homs', 'Hama', 'Latakia', 'Tartus', 'Idlib',
        'Raqqa', 'Deir ez-Zor', 'Hasakah', 'Daraa', 'Quneitra', 'Suwayda',
        'دمشق', 'حلب', 'حمص', 'حماة', 'اللاذقية', 'طرطوس', 'إدلب', 'الرقة',
        'درعا', 'القنيطرة', 'السويداء',
      ];
      for (final name in realPlaceNames) {
        expect(source.contains(name), isFalse, reason: '"$name" must not appear in location_matcher.dart');
      }
    });

    test('15. the matcher has no Firestore/Mapbox/HTTP/Riverpod/geolocator dependency', () {
      // Scoped to actual `import` lines rather than the whole file text —
      // the file's own doc comments legitimately explain what it does NOT
      // depend on (in prose), which would otherwise false-positive here.
      final importLines =
          source.split('\n').where((line) => line.trim().startsWith('import ')).join('\n');
      const forbiddenImports = [
        'cloud_firestore',
        'firebase',
        'mapbox',
        'package:http',
        'flutter_riverpod',
        'geolocator',
      ];
      for (final needle in forbiddenImports) {
        expect(importLines.toLowerCase().contains(needle), isFalse,
            reason: 'location_matcher.dart must not import "$needle"');
      }
    });
  });
}
