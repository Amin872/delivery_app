import 'package:flutter_test/flutter_test.dart';

import 'package:delivery_app/models/district.dart';

void main() {
  test('DistrictOption round-trips through toMap/fromMap', () {
    const district = DistrictOption(
      id: 'al_mazzeh',
      nameEn: 'Al-Mazzeh',
      nameAr: 'المزة',
      cityId: 'damascus',
      enabled: true,
      order: 0,
    );

    final restored = DistrictOption.fromMap(district.id, district.toMap());

    expect(restored.id, district.id);
    expect(restored.nameEn, district.nameEn);
    expect(restored.nameAr, district.nameAr);
    expect(restored.cityId, district.cityId);
    expect(restored.enabled, district.enabled);
    expect(restored.order, district.order);
  });

  test('DistrictOption.fromMap defaults enabled to true when missing', () {
    final restored = DistrictOption.fromMap('al_mazzeh', {
      'nameEn': 'Al-Mazzeh',
      'nameAr': 'المزة',
      'cityId': 'damascus',
      'order': 1,
    });

    expect(restored.enabled, isTrue);
  });

  test('DistrictOption.fromMap defaults order to 0 when missing', () {
    final restored = DistrictOption.fromMap('al_mazzeh', {
      'nameEn': 'Al-Mazzeh',
      'nameAr': 'المزة',
      'cityId': 'damascus',
      'enabled': true,
    });

    expect(restored.order, 0);
  });

  test('DistrictOption.fromMap round-trips a disabled district', () {
    const district = DistrictOption(
      id: 'al_mazzeh',
      nameEn: 'Al-Mazzeh',
      nameAr: 'المزة',
      cityId: 'damascus',
      enabled: false,
      order: 2,
    );

    final restored = DistrictOption.fromMap(district.id, district.toMap());

    expect(restored.enabled, isFalse);
  });

  test('DistrictOption.fromMap carries cityId through unchanged, never defaulting it', () {
    final restored = DistrictOption.fromMap('al_mazzeh', {
      'nameEn': 'Al-Mazzeh',
      'nameAr': 'المزة',
      'cityId': 'aleppo',
      'enabled': true,
      'order': 0,
    });

    expect(restored.cityId, 'aleppo');
  });

  group('visibleDistricts', () {
    test('excludes disabled districts', () {
      const districts = [
        DistrictOption(
          id: 'al_mazzeh',
          nameEn: 'Al-Mazzeh',
          nameAr: 'المزة',
          cityId: 'damascus',
          enabled: true,
          order: 0,
        ),
        DistrictOption(
          id: 'douma',
          nameEn: 'Douma',
          nameAr: 'دوما',
          cityId: 'damascus',
          enabled: false,
          order: 1,
        ),
      ];

      final result = visibleDistricts(districts);

      expect(result.map((d) => d.id), ['al_mazzeh']);
    });

    test('sorts by order, regardless of input order', () {
      const districts = [
        DistrictOption(
          id: 'douma',
          nameEn: 'Douma',
          nameAr: 'دوما',
          cityId: 'damascus',
          enabled: true,
          order: 2,
        ),
        DistrictOption(
          id: 'al_mazzeh',
          nameEn: 'Al-Mazzeh',
          nameAr: 'المزة',
          cityId: 'damascus',
          enabled: true,
          order: 0,
        ),
        DistrictOption(
          id: 'jaramana',
          nameEn: 'Jaramana',
          nameAr: 'جرمانا',
          cityId: 'damascus',
          enabled: true,
          order: 1,
        ),
      ];

      final result = visibleDistricts(districts);

      expect(result.map((d) => d.id).toList(), ['al_mazzeh', 'jaramana', 'douma']);
    });

    test('returns an empty list when every district is disabled', () {
      const districts = [
        DistrictOption(
          id: 'al_mazzeh',
          nameEn: 'Al-Mazzeh',
          nameAr: 'المزة',
          cityId: 'damascus',
          enabled: false,
          order: 0,
        ),
      ];

      expect(visibleDistricts(districts), isEmpty);
    });

    test('returns an empty list for an empty input', () {
      expect(visibleDistricts(const []), isEmpty);
    });
  });
}
