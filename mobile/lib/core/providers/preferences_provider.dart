import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/city.dart';

/// Overridden in `main.dart` with the [SharedPreferences] instance awaited
/// before `runApp`, so the app's persisted language/theme choice is
/// available synchronously on first frame instead of flashing a default.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider must be overridden');
});

const _localeKey = 'locale';
const _themeModeKey = 'themeMode';
const _cityKey = 'selectedCity';

const supportedLocales = [Locale('ar'), Locale('en')];

final localeProvider = StateNotifierProvider<LocaleController, Locale>((ref) {
  return LocaleController(ref.watch(sharedPreferencesProvider));
});

class LocaleController extends StateNotifier<Locale> {
  LocaleController(this._prefs)
      : super(Locale(_prefs.getString(_localeKey) ?? 'ar'));

  final SharedPreferences _prefs;

  void setLocale(Locale locale) {
    state = locale;
    _prefs.setString(_localeKey, locale.languageCode);
  }

  void toggle() {
    setLocale(state.languageCode == 'ar' ? const Locale('en') : const Locale('ar'));
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeController, ThemeMode>((ref) {
  return ThemeModeController(ref.watch(sharedPreferencesProvider));
});

class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController(this._prefs)
      : super(_fromString(_prefs.getString(_themeModeKey)));

  final SharedPreferences _prefs;

  static ThemeMode _fromString(String? value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      default:
        // No stored preference yet (first run) — default to dark, since the
        // app's burgundy theme is designed dark-first. An explicit prior
        // choice of 'system' (stored by setThemeMode) is still honored above.
        return ThemeMode.dark;
    }
  }

  void setThemeMode(ThemeMode mode) {
    state = mode;
    _prefs.setString(_themeModeKey, mode.name);
  }
}

/// The customer's browsing city — a device-local preference (like
/// [localeProvider]/[themeModeProvider]), not account data, so switching
/// city here never touches Firestore. Drives a client-side filter over the
/// already-fetched open-vendor list on [CustomerHomeScreen], same shape as
/// the existing category filter.
final selectedCityProvider = StateNotifierProvider<SelectedCityController, City>((ref) {
  return SelectedCityController(ref.watch(sharedPreferencesProvider));
});

class SelectedCityController extends StateNotifier<City> {
  SelectedCityController(this._prefs) : super(_fromString(_prefs.getString(_cityKey)));

  final SharedPreferences _prefs;

  static City _fromString(String? value) {
    return City.values.firstWhere((c) => c.name == value, orElse: () => City.damascus);
  }

  void setCity(City city) {
    state = city;
    _prefs.setString(_cityKey, city.name);
  }
}
