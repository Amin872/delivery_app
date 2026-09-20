import 'package:flutter/widgets.dart';

/// Centralized corner-radius scale. Verified against the codebase before
/// picking these values: `BorderRadius.circular(12)` and `.circular(16)`
/// were already the two most-repeated radii across existing widgets (cards,
/// inputs, sheets), so `medium`/`large` below match real, established
/// usage rather than introducing new arbitrary numbers.
class AppRadius {
  AppRadius._();

  static const double smallValue = 8;
  static const double mediumValue = 12;
  static const double largeValue = 16;
  static const double extraLargeValue = 20;

  /// Large enough that `BorderRadius.circular(pillValue)` always renders as
  /// a fully-rounded stadium shape regardless of the box's own height —
  /// the standard trick for "pill" buttons/chips/search bars.
  static const double pillValue = 999;
  static const double circleValue = 999;

  static const BorderRadius small = BorderRadius.all(Radius.circular(smallValue));
  static const BorderRadius medium = BorderRadius.all(Radius.circular(mediumValue));
  static const BorderRadius large = BorderRadius.all(Radius.circular(largeValue));
  static const BorderRadius extraLarge = BorderRadius.all(Radius.circular(extraLargeValue));
  static const BorderRadius pill = BorderRadius.all(Radius.circular(pillValue));
  static const BorderRadius circle = BorderRadius.all(Radius.circular(circleValue));
}
