import 'package:flutter/material.dart';

/// Lets [child] scroll instead of overflowing once it's taller than the
/// viewport — e.g. an auth form whose fields no longer fit once the
/// on-screen keyboard opens — while still centering it vertically when it
/// does fit. The standard LayoutBuilder + ConstrainedBox(minHeight) fix for
/// a keyboard-triggered RenderFlex overflow on a centered, unscrollable
/// Column.
class CenteredScrollBody extends StatelessWidget {
  const CenteredScrollBody({required this.child, this.padding = const EdgeInsets.all(24), super.key});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: padding,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - padding.vertical),
            child: child,
          ),
        );
      },
    );
  }
}
