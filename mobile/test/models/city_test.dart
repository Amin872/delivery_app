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
}
