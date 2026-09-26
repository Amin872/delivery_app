import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme/app_theme.dart';

/// Gradient-accented headline metric tile for the vendor/driver stats
/// dashboards — several are typically laid out in a [Row], hence [Expanded].
///
/// [gradient] optionally overrides the default [AppGradients.primary] fill —
/// same reasoning and same shape as `GradientButton.gradient`: that default
/// is a fixed brand-burgundy regardless of the ambient theme, which clashes
/// on a [VendorPalette]-themed screen (e.g. Admin Analytics). Those screens
/// pass their own cyan gradient built from `VendorPalette` constants rather
/// than this widget guessing its ambient theme.
class StatCard extends StatelessWidget {
  const StatCard({required this.label, required this.value, this.icon, this.gradient, super.key});

  final String label;
  final String value;
  final IconData? icon;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: gradient ?? AppGradients.primary(colorScheme),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: colorScheme.primary.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) Icon(icon, color: AppGradients.onPrimary),
            const SizedBox(height: 8),
            // A long amount (large sales totals, 1.3x text) shrinks to fit
            // on one line instead of wrapping mid-number; it never grows.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                value,
                maxLines: 1,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(color: AppGradients.onPrimary),
              ),
            ),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: AppGradients.onPrimary.withValues(alpha: 0.9))),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 350.ms).scaleXY(begin: 0.92, end: 1);
  }
}
