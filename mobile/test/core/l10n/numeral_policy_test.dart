import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:delivery_app/core/format/display_formatters.dart';
import 'package:delivery_app/core/l10n/numeral_policy.dart';
import 'package:delivery_app/l10n/app_localizations.dart';

final _easternDigits = RegExp('[\u0660-\u0669\u06F0-\u06F9]');

void main() {
  testWidgets('Arabic UI uses Western digits for dates, times, money, counts and ids', (tester) async {
    applyNumeralPolicy(); // as main.dart does, before the app builds
    late BuildContext captured;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ar'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (context) {
        captured = context;
        return const SizedBox();
      }),
    ));

    final date = DateTime(2026, 9, 26, 14, 5);
    final material = MaterialLocalizations.of(captured);
    final outputs = {
      'app date (dateTimeFormatProvider shape)': DateFormat.yMd('ar').add_Hm().format(date),
      'material compact date': material.formatCompactDate(date),
      'material full date': material.formatFullDate(date),
      'material time': material.formatTimeOfDay(const TimeOfDay(hour: 14, minute: 5)),
      'money': NumberFormat.currency(locale: 'ar', name: 'SYP').format(25000),
      'count': NumberFormat.decimalPattern('ar').format(1234),
      'order id': displayOrderId('Xk3pQ9aB7cD2eF1gH4iJ'),
    };
    for (final entry in outputs.entries) {
      expect(entry.value.contains(_easternDigits), isFalse, reason: '${entry.key}: "${entry.value}"');
      expect(entry.value.contains(RegExp('[0-9]')), isTrue, reason: '${entry.key}: "${entry.value}"');
    }
    // Arabic text itself is untouched.
    expect(lookupAppLocalizations(const Locale('ar')).retryButton, 'إعادة المحاولة');
  });
}
