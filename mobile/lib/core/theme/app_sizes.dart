/// Component dimension tokens — sizes that are part of the design system
/// (control heights, tap targets, badge/icon sizes), as opposed to the
/// spacing between things ([AppSpacing]) or corner shapes ([AppRadius]).
class AppSizes {
  AppSizes._();

  /// Minimum interactive target (Material/WCAG guidance).
  static const double minTapTarget = 48;

  /// Primary/secondary buttons (filled, outlined, elevated, gradient).
  static const double buttonHeight = 48;

  /// Text buttons and inline actions.
  static const double compactButtonHeight = 44;

  /// Finite minimum button width (Material's own default). Never
  /// `double.infinity`: a button laid out with unbounded width (in a Row,
  /// a ListTile trailing, dialog actions) would throw "BoxConstraints
  /// forces an infinite width" — see the Phase 1 C1/C2 fix.
  static const double buttonMinWidth = 64;

  static const double iconSmall = 16;
  static const double iconMedium = 20;
  static const double iconLarge = 24;
}
