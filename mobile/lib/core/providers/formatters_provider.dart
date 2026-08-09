import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'preferences_provider.dart';

/// Rebuilt only when [localeProvider] changes, instead of on every widget
/// rebuild — `NumberFormat`/`DateFormat` construction does real work
/// (locale data lookup) that's wasted redone on every frame.
final currencyFormatProvider = Provider<NumberFormat>((ref) {
  final locale = ref.watch(localeProvider);
  return NumberFormat.currency(locale: locale.toString(), name: 'SYP');
});

final dateTimeFormatProvider = Provider<DateFormat>((ref) {
  final locale = ref.watch(localeProvider);
  return DateFormat.yMd(locale.toString()).add_Hm();
});
