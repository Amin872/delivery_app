import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// A label and a value (e.g. "Add to order" + "25,000 SYP") for the
/// customer's order pills: side by side when both fit on one line, stacked
/// when they don't. The choice is made by measuring the real text at the
/// current text scale — not by a screen-width breakpoint — so it holds for
/// every width, language and font size.
///
/// The [value] is never truncated (in the stacked layout it is only scaled
/// down if it alone is wider than the pill). The [label] ellipsises as a
/// last resort. [trailing] (e.g. an item-count badge) always sits after the
/// label; [trailingExtent] is its width for the fit measurement.
class AdaptiveLabelValue extends StatelessWidget {
  const AdaptiveLabelValue({
    required this.label,
    required this.value,
    required this.style,
    this.valueFirst = false,
    this.trailing,
    this.trailingExtent = 0,
    super.key,
  });

  final String label;
  final String value;
  final TextStyle? style;

  /// Value at the start (reading order) and label at the end, instead of
  /// label first.
  final bool valueFirst;
  final Widget? trailing;
  final double trailingExtent;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaler = MediaQuery.textScalerOf(context);
        final direction = Directionality.of(context);
        double widthOf(String text) => (TextPainter(
              text: TextSpan(text: text, style: style),
              textDirection: direction,
              textScaler: scaler,
              maxLines: 1,
            )..layout())
                .width;
        final trailingSpace = trailing == null ? 0.0 : AppSpacing.sm + trailingExtent;
        final fits = widthOf(label) + AppSpacing.md + widthOf(value) + trailingSpace <= constraints.maxWidth;

        final valueText = Text(value, style: style, maxLines: 1);
        if (fits) {
          final labelText = Expanded(
            child: Text(
              label,
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: valueFirst ? TextAlign.end : TextAlign.start,
            ),
          );
          return Row(
            children: [
              if (valueFirst) ...[valueText, const SizedBox(width: AppSpacing.md), labelText]
              else ...[labelText, const SizedBox(width: AppSpacing.md), valueText],
              if (trailing != null) ...[const SizedBox(width: AppSpacing.sm), trailing!],
            ],
          );
        }

        final labelLine = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                style: style,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: AppSpacing.sm), trailing!],
          ],
        );
        final valueLine = FittedBox(fit: BoxFit.scaleDown, child: valueText);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: valueFirst ? [valueLine, labelLine] : [labelLine, valueLine],
        );
      },
    );
  }
}
