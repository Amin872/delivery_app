import '../errors/app_exception.dart';

/// Looks up [name] in [values], throwing an [AppException] (`malformed-data`)
/// instead of the uncaught `TypeError`/`ArgumentError` that `Enum.values.byName`
/// throws when a Firestore document's string value has drifted from the enum
/// (e.g. a renamed status) — callers get a typed, catchable error instead.
T enumByName<T extends Enum>(List<T> values, String? name) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw const AppException('malformed-data');
}
