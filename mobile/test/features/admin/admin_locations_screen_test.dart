import 'package:flutter_test/flutter_test.dart';

import 'package:delivery_app/features/admin/screens/admin_locations_screen.dart';
import 'package:delivery_app/models/city.dart';
import 'package:delivery_app/models/governorate.dart';

CityOption _city(String id, {String? governorateId, bool enabled = true, int order = 0}) {
  return CityOption(
    id: id,
    nameEn: id,
    nameAr: id,
    enabled: enabled,
    order: order,
    governorateId: governorateId,
  );
}

GovernorateOption _governorate(String id, {bool enabled = true, int order = 0}) {
  return GovernorateOption(id: id, nameEn: id, nameAr: id, enabled: enabled, order: order);
}

void main() {
  group('buildCityRows', () {
    test('resolves the governorate for a city with a matching governorateId', () {
      final rows = buildCityRows(
        [_city('damascus', governorateId: 'damascus')],
        [_governorate('damascus'), _governorate('aleppo')],
      );

      expect(rows.single.governorate?.id, 'damascus');
    });

    test('resolves an explicit unassigned state for a null governorateId', () {
      final rows = buildCityRows(
        [_city('damascus', governorateId: null)],
        [_governorate('damascus')],
      );

      expect(rows.single.governorate, isNull);
    });

    test('resolves an explicit unassigned state for a stale/missing governorateId, never crashing',
        () {
      final rows = buildCityRows(
        [_city('damascus', governorateId: 'nonexistent-governorate')],
        [_governorate('damascus')],
      );

      expect(rows.single.governorate, isNull);
    });

    test('still resolves a disabled governorate by name (not excluded from the join)', () {
      final rows = buildCityRows(
        [_city('damascus', governorateId: 'damascus')],
        [_governorate('damascus', enabled: false)],
      );

      expect(rows.single.governorate?.id, 'damascus');
      expect(rows.single.governorate?.enabled, isFalse);
    });

    test('returns an empty list for an empty input', () {
      expect(buildCityRows(const [], const []), isEmpty);
    });
  });

  group('cityIdsInGovernorate', () {
    test('returns every city assigned to the governorate, and only those', () {
      final cities = [
        _city('damascus', governorateId: 'damascus'),
        _city('douma', governorateId: 'damascus'),
        _city('aleppo', governorateId: 'aleppo'),
        _city('homs', governorateId: null),
      ];

      expect(cityIdsInGovernorate(cities, 'damascus'), {'damascus', 'douma'});
      expect(cityIdsInGovernorate(cities, 'aleppo'), {'aleppo'});
    });

    test('is empty when no city is assigned to the governorate', () {
      expect(cityIdsInGovernorate([_city('damascus', governorateId: null)], 'damascus'), isEmpty);
      expect(cityIdsInGovernorate(const [], 'damascus'), isEmpty);
    });
  });

  group('validateLocationId', () {
    test('flags an empty id as required', () {
      expect(
        validateLocationId('', isNew: true, existingIds: const {}),
        LocationIdValidationError.required,
      );
      expect(
        validateLocationId(null, isNew: true, existingIds: const {}),
        LocationIdValidationError.required,
      );
    });

    test('flags an uppercase or invalid-character id as invalid format', () {
      expect(
        validateLocationId('Damascus', isNew: true, existingIds: const {}),
        LocationIdValidationError.invalidFormat,
      );
      expect(
        validateLocationId('damascus city', isNew: true, existingIds: const {}),
        LocationIdValidationError.invalidFormat,
      );
      expect(
        validateLocationId('1damascus', isNew: true, existingIds: const {}),
        LocationIdValidationError.invalidFormat,
      );
    });

    test('accepts a lowercase/underscore slug', () {
      expect(
        validateLocationId('rif_dimashq', isNew: true, existingIds: const {}),
        isNull,
      );
    });

    test('flags a duplicate id only when creating new', () {
      expect(
        validateLocationId('damascus', isNew: true, existingIds: const {'damascus'}),
        LocationIdValidationError.duplicate,
      );
      expect(
        validateLocationId('damascus', isNew: false, existingIds: const {'damascus'}),
        isNull,
      );
    });
  });
}
