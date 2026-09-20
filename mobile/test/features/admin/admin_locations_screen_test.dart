import 'package:flutter_test/flutter_test.dart';

import 'package:delivery_app/features/admin/screens/admin_locations_screen.dart';
import 'package:delivery_app/models/city.dart';
import 'package:delivery_app/models/governorate.dart';
import 'package:delivery_app/models/vendor.dart';

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

Vendor _vendor(String id, {required String city}) {
  return Vendor(
    id: id,
    ownerId: 'owner-$id',
    name: 'Vendor $id',
    description: '',
    isOpen: true,
    approvalStatus: VendorApprovalStatus.approved,
    city: city,
  );
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

  group('vendorCountForCity', () {
    test('counts only vendors whose city matches', () {
      final vendors = [
        _vendor('v1', city: 'damascus'),
        _vendor('v2', city: 'aleppo'),
        _vendor('v3', city: 'damascus'),
      ];

      expect(vendorCountForCity(vendors, 'damascus'), 2);
      expect(vendorCountForCity(vendors, 'aleppo'), 1);
      expect(vendorCountForCity(vendors, 'homs'), 0);
    });

    test('returns 0 for an empty vendor list', () {
      expect(vendorCountForCity(const [], 'damascus'), 0);
    });
  });

  group('vendorCountForGovernorate', () {
    test('counts vendors across every city assigned to the governorate', () {
      final vendors = [
        _vendor('v1', city: 'damascus'),
        _vendor('v2', city: 'douma'),
        _vendor('v3', city: 'aleppo'),
      ];
      final cities = [
        _city('damascus', governorateId: 'damascus'),
        _city('douma', governorateId: 'damascus'),
        _city('aleppo', governorateId: 'aleppo'),
      ];

      expect(vendorCountForGovernorate(vendors, cities, 'damascus'), 2);
      expect(vendorCountForGovernorate(vendors, cities, 'aleppo'), 1);
    });

    test('returns 0 when no city is assigned to the governorate', () {
      final vendors = [_vendor('v1', city: 'damascus')];
      final cities = [_city('damascus', governorateId: null)];

      expect(vendorCountForGovernorate(vendors, cities, 'damascus'), 0);
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
