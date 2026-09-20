import 'package:flutter_test/flutter_test.dart';

import 'package:delivery_app/models/governorate.dart';

void main() {
  test('GovernorateOption round-trips through toMap/fromMap', () {
    const governorate = GovernorateOption(
      id: 'damascus',
      nameEn: 'Damascus',
      nameAr: 'دمشق',
      enabled: true,
      order: 0,
    );

    final restored = GovernorateOption.fromMap(governorate.id, governorate.toMap());

    expect(restored.id, governorate.id);
    expect(restored.nameEn, governorate.nameEn);
    expect(restored.nameAr, governorate.nameAr);
    expect(restored.enabled, governorate.enabled);
    expect(restored.order, governorate.order);
  });

  test('GovernorateOption.fromMap defaults enabled to true when missing', () {
    final restored = GovernorateOption.fromMap('aleppo', {
      'nameEn': 'Aleppo',
      'nameAr': 'حلب',
      'order': 2,
    });

    expect(restored.enabled, isTrue);
  });

  test('GovernorateOption.fromMap defaults order to 0 when missing', () {
    final restored = GovernorateOption.fromMap('homs', {
      'nameEn': 'Homs',
      'nameAr': 'حمص',
      'enabled': true,
    });

    expect(restored.order, 0);
  });

  test('GovernorateOption.fromMap round-trips a disabled governorate', () {
    const governorate = GovernorateOption(
      id: 'quneitra',
      nameEn: 'Quneitra',
      nameAr: 'القنيطرة',
      enabled: false,
      order: 12,
    );

    final restored = GovernorateOption.fromMap(governorate.id, governorate.toMap());

    expect(restored.enabled, isFalse);
  });

  group('visibleGovernorates', () {
    test('excludes disabled governorates', () {
      const governorates = [
        GovernorateOption(id: 'damascus', nameEn: 'Damascus', nameAr: 'دمشق', enabled: true, order: 0),
        GovernorateOption(id: 'homs', nameEn: 'Homs', nameAr: 'حمص', enabled: false, order: 1),
      ];

      final result = visibleGovernorates(governorates);

      expect(result.map((g) => g.id), ['damascus']);
    });

    test('sorts by order, regardless of input order', () {
      const governorates = [
        GovernorateOption(id: 'tartus', nameEn: 'Tartus', nameAr: 'طرطوس', enabled: true, order: 4),
        GovernorateOption(id: 'damascus', nameEn: 'Damascus', nameAr: 'دمشق', enabled: true, order: 0),
        GovernorateOption(id: 'aleppo', nameEn: 'Aleppo', nameAr: 'حلب', enabled: true, order: 1),
      ];

      final result = visibleGovernorates(governorates);

      expect(result.map((g) => g.id).toList(), ['damascus', 'aleppo', 'tartus']);
    });

    test('returns an empty list when every governorate is disabled', () {
      const governorates = [
        GovernorateOption(id: 'damascus', nameEn: 'Damascus', nameAr: 'دمشق', enabled: false, order: 0),
      ];

      expect(visibleGovernorates(governorates), isEmpty);
    });

    test('returns an empty list for an empty input', () {
      expect(visibleGovernorates(const []), isEmpty);
    });
  });
}
