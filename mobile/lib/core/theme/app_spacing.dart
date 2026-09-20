/// Centralized spacing scale — use these instead of writing raw numbers
/// (`SizedBox(height: 12)`, `EdgeInsets.all(16)`, ...) inline in widgets, so
/// spacing stays consistent and a single change here reflows the whole app.
/// A deliberately small, predictable set — not every multiple of 4 is
/// offered, only the ones that actually recur across the UI.
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 40;

  /// Vertical gap between major page sections (e.g. between a carousel and
  /// the next one) — larger than any padding value, reserved for that one
  /// purpose so it isn't reached for by accident where `xxxl` would do.
  static const double section = 48;
}
