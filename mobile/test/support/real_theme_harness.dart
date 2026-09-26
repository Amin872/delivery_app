import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:delivery_app/core/l10n/numeral_policy.dart';
import 'package:delivery_app/core/providers/formatters_provider.dart';
import 'package:delivery_app/core/providers/preferences_provider.dart';
import 'package:delivery_app/core/theme/app_theme.dart';
import 'package:delivery_app/l10n/app_localizations.dart';

/// Reusable UI-test setup that renders with the REAL app theme
/// ([AppTheme.light]) — button minimum sizes, card/list/chip themes, the
/// app font — instead of a bare MaterialApp. Bare-MaterialApp tests are
/// what let the Phase 1 "BoxConstraints forces an infinite width" bug
/// (a theme-level button size) through; use this for layout tests.

/// Phone widths every layout test should survive (small Android, common
/// Android, common iPhone).
const phoneWidths = <double>[320, 360, 393];

/// Arabic (RTL, the default app language) and English (LTR).
const layoutLocales = <Locale>[Locale('ar'), Locale('en')];

/// One width × locale combination.
typedef LayoutConfig = ({double width, Locale locale});

List<LayoutConfig> get allLayoutConfigs => [
      for (final width in phoneWidths)
        for (final locale in layoutLocales) (width: width, locale: locale),
    ];

/// Pumps [home] under the real theme at [width] × [height] logical pixels
/// in [locale], with SharedPreferences and the formatters provided. Extra
/// provider [overrides] are appended.
Future<void> pumpWithRealTheme(
  WidgetTester tester,
  Widget home, {
  Locale locale = const Locale('ar'),
  double width = 360,
  double height = 800,
  double textScale = 1,
  List<Override> overrides = const [],
}) async {
  applyNumeralPolicy(); // same as main.dart
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        currencyFormatProvider.overrideWithValue(NumberFormat.currency(locale: locale.languageCode, name: 'SYP')),
        dateTimeFormatProvider.overrideWithValue(DateFormat('yyyy-MM-dd HH:mm')),
        ...overrides,
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: home,
      ),
    ),
  );
}

/// Declares one `testWidgets` per [allLayoutConfigs] entry, named
/// `"<description> [<width> <lang>]"`. Any framework error during the test
/// (overflow, infinite-width, null check) fails that combination.
void testWidgetsAcrossLayouts(
  String description,
  Future<void> Function(WidgetTester tester, LayoutConfig config) body,
) {
  for (final config in allLayoutConfigs) {
    testWidgets('$description [${config.width.toInt()} ${config.locale.languageCode}]', (tester) async {
      await body(tester, config);
    });
  }
}
