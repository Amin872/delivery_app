import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme/app_theme.dart';

/// Gradient-filled primary action button — the redesigned counterpart to a
/// bare `FilledButton`, used for each screen's single primary CTA (sign in,
/// place order, save, ...). Keeps the same `onPressed`/`child` API
/// `FilledButton` call sites already use (including the loading-spinner-swap
/// pattern), so replacing one with the other is a near-drop-in change.
class GradientButton extends StatefulWidget {
  const GradientButton({required this.onPressed, required this.child, super.key});

  final VoidCallback? onPressed;
  final Widget child;

  @override
  State<GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<GradientButton> {
  bool _isPressed = false;

  void _setPressed(bool value) {
    if (widget.onPressed == null) return;
    setState(() => _isPressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final enabled = widget.onPressed != null;

    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: _isPressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: Container(
          height: 48,
          width: double.infinity,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: enabled ? AppGradients.primary(colorScheme) : null,
            color: enabled ? null : colorScheme.onSurface.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: colorScheme.primary.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: DefaultTextStyle.merge(
            style: TextStyle(
              color: enabled
                  ? colorScheme.onPrimary
                  : colorScheme.onSurface.withValues(alpha: 0.38),
              fontWeight: FontWeight.w600,
            ),
            child: IconTheme.merge(
              data: IconThemeData(
                color: enabled
                    ? colorScheme.onPrimary
                    : colorScheme.onSurface.withValues(alpha: 0.38),
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    ).animate().fadeIn(duration: 300.ms).scaleXY(begin: 0.95, end: 1);
  }
}
