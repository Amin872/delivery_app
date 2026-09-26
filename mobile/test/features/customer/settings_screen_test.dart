import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:delivery_app/core/providers/preferences_provider.dart';
import 'package:delivery_app/features/customer/screens/settings_screen.dart';
import 'package:delivery_app/l10n/app_localizations.dart';

import '../../support/real_theme_harness.dart';

void main() {
  testWidgetsAcrossLayouts('offers only Light while there is no real dark theme', (tester, config) async {
    await pumpWithRealTheme(tester, const SettingsScreen(), locale: config.locale, width: config.width);
    await tester.pumpAndSettle();
    final l10n = lookupAppLocalizations(config.locale);
    expect(find.text(l10n.themeModeLight), findsOneWidget);
    expect(find.text(l10n.themeModeDark), findsNothing);
    expect(find.text(l10n.themeModeSystem), findsNothing);
  });

  testWidgets('a previously saved Dark choice shows as Light (what the app renders)', (tester) async {
    SharedPreferences.setMockInitialValues({'themeMode': 'dark'});
    final prefs = await SharedPreferences.getInstance();
    await pumpWithRealTheme(tester, const SettingsScreen(),
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(SettingsScreen)));
    expect(container.read(themeModeProvider), ThemeMode.dark, reason: 'the saved preference is really Dark');
    final group = tester.widget<RadioGroup<ThemeMode>>(find.byType(RadioGroup<ThemeMode>));
    expect(group.groupValue, ThemeMode.light);
  });
}
