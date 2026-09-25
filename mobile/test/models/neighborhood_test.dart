import 'package:flutter_test/flutter_test.dart';

import 'package:delivery_app/models/neighborhood.dart';

void main() {
  test('NeighborhoodOption round-trips through toMap/fromMap', () {
    const neighborhood = NeighborhoodOption(
      id: 'damascus_mazzeh',
      nameEn: 'Al-Mazzeh',
      nameAr: 'المزة',
      cityId: 'damascus',
      enabled: true,
      order: 0,
      ochaPcode: 'N0001',
    );

    final restored = NeighborhoodOption.fromMap(neighborhood.id, neighborhood.toMap());

    expect(restored.id, neighborhood.id);
    expect(restored.nameEn, neighborhood.nameEn);
    expect(restored.nameAr, neighborhood.nameAr);
    expect(restored.cityId, neighborhood.cityId);
    expect(restored.enabled, neighborhood.enabled);
    expect(restored.order, neighborhood.order);
    expect(restored.ochaPcode, neighborhood.ochaPcode);
  });

  test('NeighborhoodOption.fromMap defaults enabled to true when missing', () {
    final restored = NeighborhoodOption.fromMap('damascus_mazzeh', {
      'nameEn': 'Al-Mazzeh',
      'nameAr': 'المزة',
      'cityId': 'damascus',
      'order': 1,
    });

    expect(restored.enabled, isTrue);
  });

  test('NeighborhoodOption.fromMap defaults order to 0 when missing', () {
    final restored = NeighborhoodOption.fromMap('damascus_mazzeh', {
      'nameEn': 'Al-Mazzeh',
      'nameAr': 'المزة',
      'cityId': 'damascus',
      'enabled': true,
    });

    expect(restored.order, 0);
  });

  test('NeighborhoodOption.fromMap defaults ochaPcode to null when missing', () {
    final restored = NeighborhoodOption.fromMap('damascus_mazzeh', {
      'nameEn': 'Al-Mazzeh',
      'nameAr': 'المزة',
      'cityId': 'damascus',
      'enabled': true,
      'order': 0,
    });

    expect(restored.ochaPcode, isNull);
  });

  test('NeighborhoodOption.fromMap round-trips a disabled (e.g. industrial/camp) record', () {
    const neighborhood = NeighborhoodOption(
      id: 'aleppo_mokhayam_handarat',
      nameEn: 'Mokhayam Handarat',
      nameAr: 'مخيم حندرات',
      cityId: 'aleppo',
      enabled: false,
      order: 108,
      ochaPcode: 'N0227',
    );

    final restored = NeighborhoodOption.fromMap(neighborhood.id, neighborhood.toMap());

    expect(restored.enabled, isFalse);
  });

  test('NeighborhoodOption.fromMap carries cityId through unchanged, never defaulting it', () {
    final restored = NeighborhoodOption.fromMap('damascus_yarmuk_hettin', {
      'nameEn': 'Hettin',
      'nameAr': 'حطين',
      'cityId': 'damascus_yarmuk',
      'enabled': true,
      'order': 1,
    });

    expect(restored.cityId, 'damascus_yarmuk');
  });

  group('visibleNeighborhoods', () {
    test('excludes disabled neighborhoods', () {
      const neighborhoods = [
        NeighborhoodOption(
          id: 'damascus_mazzeh',
          nameEn: 'Al-Mazzeh',
          nameAr: 'المزة',
          cityId: 'damascus',
          enabled: true,
          order: 0,
        ),
        NeighborhoodOption(
          id: 'aleppo_university_of_aleppo',
          nameEn: 'University of Aleppo',
          nameAr: 'جامعة حلب',
          cityId: 'aleppo',
          enabled: false,
          order: 1,
        ),
      ];

      final result = visibleNeighborhoods(neighborhoods);

      expect(result.map((n) => n.id), ['damascus_mazzeh']);
    });

    test('sorts by order, regardless of input order', () {
      const neighborhoods = [
        NeighborhoodOption(
          id: 'c',
          nameEn: 'C',
          nameAr: 'ج',
          cityId: 'damascus',
          enabled: true,
          order: 2,
        ),
        NeighborhoodOption(
          id: 'a',
          nameEn: 'A',
          nameAr: 'أ',
          cityId: 'damascus',
          enabled: true,
          order: 0,
        ),
        NeighborhoodOption(
          id: 'b',
          nameEn: 'B',
          nameAr: 'ب',
          cityId: 'damascus',
          enabled: true,
          order: 1,
        ),
      ];

      final result = visibleNeighborhoods(neighborhoods);

      expect(result.map((n) => n.id).toList(), ['a', 'b', 'c']);
    });

    test('returns an empty list when every neighborhood is disabled', () {
      const neighborhoods = [
        NeighborhoodOption(
          id: 'damascus_mazzeh',
          nameEn: 'Al-Mazzeh',
          nameAr: 'المزة',
          cityId: 'damascus',
          enabled: false,
          order: 0,
        ),
      ];

      expect(visibleNeighborhoods(neighborhoods), isEmpty);
    });

    test('returns an empty list for an empty input', () {
      expect(visibleNeighborhoods(const []), isEmpty);
    });
  });
}
