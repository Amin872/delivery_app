import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:delivery_app/core/providers/preferences_provider.dart';

void main() {
  group('SelectedCityController', () {
    test('defaults to damascus when nothing is stored yet', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = SelectedCityController(prefs);

      expect(controller.state, 'damascus');
    });

    test('loads a pre-existing string value under the existing key unchanged', () async {
      // Simulates a value saved by the pre-migration enum-based code
      // (which stored `City.aleppo.name`, i.e. the same string) — must be
      // read back identically, with no conversion.
      SharedPreferences.setMockInitialValues({'selectedCity': 'aleppo'});
      final prefs = await SharedPreferences.getInstance();
      final controller = SelectedCityController(prefs);

      expect(controller.state, 'aleppo');
    });

    test('setCity updates state and persists under the existing key', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = SelectedCityController(prefs);

      controller.setCity('homs');

      expect(controller.state, 'homs');
      expect(prefs.getString('selectedCity'), 'homs');
    });

    test('accepts a city id not among the five legacy ids', () async {
      // A future admin-added city id must work too — this provider has no
      // notion of a fixed/known set, it's just a stored string.
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = SelectedCityController(prefs);

      controller.setCity('a-future-admin-added-city');

      expect(controller.state, 'a-future-admin-added-city');
    });
  });
}
