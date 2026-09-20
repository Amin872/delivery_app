import 'package:flutter_test/flutter_test.dart';

import 'package:delivery_app/models/city.dart';

void main() {
  test('CityOption round-trips through toMap/fromMap', () {
    const city = CityOption(
      id: 'damascus',
      nameEn: 'Damascus',
      nameAr: 'دمشق',
      enabled: true,
      order: 0,
    );

    final restored = CityOption.fromMap(city.id, city.toMap());

    expect(restored.id, city.id);
    expect(restored.nameEn, city.nameEn);
    expect(restored.nameAr, city.nameAr);
    expect(restored.enabled, city.enabled);
    expect(restored.order, city.order);
  });

  test('CityOption.fromMap defaults enabled to true when missing', () {
    final restored = CityOption.fromMap('aleppo', {
      'nameEn': 'Aleppo',
      'nameAr': 'حلب',
      'order': 1,
    });

    expect(restored.enabled, isTrue);
  });

  test('CityOption.fromMap defaults order to 0 when missing', () {
    final restored = CityOption.fromMap('homs', {
      'nameEn': 'Homs',
      'nameAr': 'حمص',
      'enabled': true,
    });

    expect(restored.order, 0);
  });

  test('CityOption.fromMap round-trips a disabled city', () {
    const city = CityOption(
      id: 'tartus',
      nameEn: 'Tartus',
      nameAr: 'طرطوس',
      enabled: false,
      order: 4,
    );

    final restored = CityOption.fromMap(city.id, city.toMap());

    expect(restored.enabled, isFalse);
  });

  group('visibleCities', () {
    test('excludes disabled cities', () {
      const cities = [
        CityOption(id: 'damascus', nameEn: 'Damascus', nameAr: 'دمشق', enabled: true, order: 0),
        CityOption(id: 'homs', nameEn: 'Homs', nameAr: 'حمص', enabled: false, order: 1),
      ];

      final result = visibleCities(cities);

      expect(result.map((c) => c.id), ['damascus']);
    });

    test('sorts by order, regardless of input order', () {
      const cities = [
        CityOption(id: 'tartus', nameEn: 'Tartus', nameAr: 'طرطوس', enabled: true, order: 4),
        CityOption(id: 'damascus', nameEn: 'Damascus', nameAr: 'دمشق', enabled: true, order: 0),
        CityOption(id: 'aleppo', nameEn: 'Aleppo', nameAr: 'حلب', enabled: true, order: 1),
      ];

      final result = visibleCities(cities);

      expect(result.map((c) => c.id).toList(), ['damascus', 'aleppo', 'tartus']);
    });

    test('returns an empty list when every city is disabled', () {
      const cities = [
        CityOption(id: 'damascus', nameEn: 'Damascus', nameAr: 'دمشق', enabled: false, order: 0),
      ];

      expect(visibleCities(cities), isEmpty);
    });

    test('returns an empty list for an empty input', () {
      expect(visibleCities(const []), isEmpty);
    });
  });
}
