import 'package:flutter/material.dart';

/// Caps [child] at [maxWidth] and centers it once the viewport grows past
/// that — a complete no-op below it, so phone-sized layouts are unaffected.
/// The app also targets web/desktop (see `pubspec.yaml`), where every screen
/// would otherwise stretch a single-column list edge-to-edge on a wide window.
class ResponsiveCenter extends StatelessWidget {
  const ResponsiveCenter({required this.child, this.maxWidth = 700, super.key});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
