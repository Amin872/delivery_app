import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:delivery_app/core/l10n/enum_labels.dart';
import 'package:delivery_app/l10n/app_localizations.dart';
import 'package:delivery_app/models/city.dart';

Future<void> _withContext(
  WidgetTester tester,
  Locale locale,
  void Function(BuildContext context) callback,
) {
  return tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) {
          callback(context);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
}

void main() {
  group('cityLabel', () {
    testWidgets('resolves a live city name in English', (tester) async {
      late String label;
      const liveCities = [
        CityOption(id: 'damascus', nameEn: 'Damascus', nameAr: 'دمشق', enabled: true, order: 0),
      ];
      await _withContext(tester, const Locale('en'), (context) {
        label = cityLabel(context, 'damascus', liveCities);
      });
      expect(label, 'Damascus');
    });

    testWidgets('resolves a live city name in Arabic', (tester) async {
      late String label;
      const liveCities = [
        CityOption(id: 'damascus', nameEn: 'Damascus', nameAr: 'دمشق', enabled: true, order: 0),
      ];
      await _withContext(tester, const Locale('ar'), (context) {
        label = cityLabel(context, 'damascus', liveCities);
      });
      expect(label, 'دمشق');
    });

    testWidgets(
        'falls back to the legacy ARB string for a legacy id with no live match',
        (tester) async {
      late String label;
      await _withContext(tester, const Locale('en'), (context) {
        // No knownCities passed — same as an empty/not-yet-loaded live list.
        label = cityLabel(context, 'aleppo');
      });
      expect(label, 'Aleppo');
    });

    testWidgets('returns the raw id for a completely unknown id, never crashing', (tester) async {
      late String label;
      await _withContext(tester, const Locale('en'), (context) {
        label = cityLabel(context, 'nonexistent-city-id');
      });
      expect(label, 'nonexistent-city-id');
    });

    testWidgets('prefers a live entry (even disabled) over the legacy fallback', (tester) async {
      late String label;
      const liveCities = [
        CityOption(
          id: 'aleppo',
          nameEn: 'Aleppo (renamed)',
          nameAr: 'حلب',
          enabled: false,
          order: 1,
        ),
      ];
      await _withContext(tester, const Locale('en'), (context) {
        label = cityLabel(context, 'aleppo', liveCities);
      });
      expect(label, 'Aleppo (renamed)');
    });
  });
}
