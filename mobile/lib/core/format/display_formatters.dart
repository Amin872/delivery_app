/// Display-only formatting helpers shared by every role's screens. Pure
/// functions: they never change what's stored (order ids, coordinates,
/// phone numbers and amounts stay exactly as they are in Firestore) — only
/// how they read on screen.
///
/// Money and dates keep their existing sources of truth:
/// `currencyFormatProvider` / `dateTimeFormatProvider`
/// (core/providers/formatters_provider.dart).
library;

import 'package:intl/intl.dart';

const _lri = '\u2066'; // LEFT-TO-RIGHT ISOLATE
const _pdi = '\u2069'; // POP DIRECTIONAL ISOLATE

/// Wraps [text] so it always reads left-to-right as one unit, even inside
/// an Arabic (RTL) sentence — e.g. "+963 944 123 456" or "#A1B2C3" would
/// otherwise have their leading "+"/"#" moved to the wrong end by the bidi
/// algorithm. Invisible; safe to pass to any Text.
String ltrIsolate(String text) => '$_lri$text$_pdi';

/// Removes the isolate marks added by [ltrIsolate] (for tests/comparisons).
String stripBidiIsolates(String text) => text.replaceAll(_lri, '').replaceAll(_pdi, '');

/// Short, human-friendly reference for an order: `#` + the last [length]
/// letters/digits of its document id, upper-cased (Firestore ids are
/// random, so the tail is as distinctive as any other slice). Display only;
/// the full id is still what every query, link and callable uses.
String shortOrderId(String orderId, {int length = 6}) {
  final alnum = orderId.replaceAll(RegExp('[^A-Za-z0-9]'), '');
  final tail = alnum.length <= length ? alnum : alnum.substring(alnum.length - length);
  return '#${tail.toUpperCase()}';
}

/// [shortOrderId], isolated for use inside localized (possibly RTL) text.
String displayOrderId(String orderId, {int length = 6}) => ltrIsolate(shortOrderId(orderId, length: length));

/// Readable coordinates: `33.51380° N, 36.27650° E`, fixed [digits]
/// (5 ≈ 1 m), hemisphere letters instead of signs, isolated LTR.
String formatCoordinates(double latitude, double longitude, {int digits = 5}) {
  final lat = '${latitude.abs().toStringAsFixed(digits)}° ${latitude < 0 ? 'S' : 'N'}';
  final lng = '${longitude.abs().toStringAsFixed(digits)}° ${longitude < 0 ? 'W' : 'E'}';
  return ltrIsolate('$lat, $lng');
}

/// Readable phone number, isolated LTR. Syrian numbers are grouped
/// (`+963 944 123 456`, `0944 123 456`); anything else is returned as
/// typed (trimmed), never reformatted into something wrong.
String formatPhone(String raw) {
  final trimmed = raw.trim();
  final digits = trimmed.replaceAll(RegExp(r'[\s\-().]'), '');
  final international = RegExp(r'^(?:\+|00)963(\d{3})(\d{3})(\d{3})$').firstMatch(digits);
  if (international != null) {
    return ltrIsolate('+963 ${international[1]} ${international[2]} ${international[3]}');
  }
  final national = RegExp(r'^0(\d{3})(\d{3})(\d{3})$').firstMatch(digits);
  if (national != null) {
    return ltrIsolate('0${national[1]} ${national[2]} ${national[3]}');
  }
  return ltrIsolate(trimmed);
}

/// A stored amount as editable text for a form field: `25000`, not
/// `25000.00`; keeps real fractions (`12.5`). Empty for null. Parsing the
/// field back is unchanged (`double.tryParse`).
String formatAmountForInput(num? amount) {
  if (amount == null) return '';
  if (amount == amount.roundToDouble()) return amount.toInt().toString();
  return amount.toString();
}

/// The one count format (quantities, badges, statistics): locale grouping,
/// Western digits (see core/l10n/numeral_policy.dart). Shared by
/// `countFormatProvider` and [formatCount] so both always agree.
NumberFormat countNumberFormat(String locale) => NumberFormat.decimalPattern(locale);

/// A count for widgets without a Riverpod ref — same output as
/// `countFormatProvider` for the app's current [locale].
String formatCount(num value, String locale) => countNumberFormat(locale).format(value);
