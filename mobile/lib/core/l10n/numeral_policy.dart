import 'package:intl/intl.dart';

import '../providers/preferences_provider.dart';

/// App-wide numeral policy: Western digits (0–9) everywhere — dates, times,
/// money, quantities, counters, ids, statistics — in every supported
/// language. Arabic UI text stays Arabic; only digits are affected.
///
/// Money and counts (`NumberFormat`) already use Western digits for the
/// app's locales. Dates did not: once `flutter_localizations` loads the
/// Arabic date symbols, `DateFormat` (ours and Material's pickers/labels)
/// defaults to Arabic-Indic digits. This turns that default off.
///
/// Must run before `runApp` (Material caches its date formats on first use).
void applyNumeralPolicy() {
  for (final locale in supportedLocales) {
    DateFormat.useNativeDigitsByDefaultFor(locale.languageCode, false);
    DateFormat.useNativeDigitsByDefaultFor(locale.toString(), false);
  }
}
