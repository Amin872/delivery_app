import 'package:flutter/material.dart';

import '../../../core/format/display_formatters.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import 'adaptive_label_value.dart';
import 'most_ordered_card.dart' show orderAccentBackground;

/// Floating "عرض الطلبية" pill replacing the old full-width `StoreCartBar`
/// docked bar — measured from the reference: light-cyan fill, ~56-58dp tall,
/// ~16dp corner radius, floating with a visible gap above the bottom edge
/// (not flush/attached like a `bottomNavigationBar`), 16dp side margins.
/// Always rendered, even with an empty order (price "€ 0,00", count "0"),
/// unlike `StoreCartBar` which the caller hid entirely via `cart.isEmpty`.
/// Callers place this as a `Positioned` overlay above their scrollable body
/// (not `Scaffold.bottomNavigationBar`, which would dock it flush and steal
/// layout space) so content keeps scrolling underneath it.
class FloatingOrderButton extends StatelessWidget {
  const FloatingOrderButton({
    required this.itemCount,
    required this.totalLabel,
    required this.onTap,
    super.key,
  });

  final int itemCount;
  final String totalLabel;
  final VoidCallback onTap;

  static const double _height = 56;
  static const double _badgeSize = 28;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final labelStyle = textTheme.titleSmall?.copyWith(color: VendorPalette.background, fontWeight: FontWeight.w700);

    return Material(
      color: orderAccentBackground,
      borderRadius: AppRadius.large,
      elevation: 4,
      child: InkWell(
        borderRadius: AppRadius.large,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _height),
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.xs),
            child: Center(
              child: AdaptiveLabelValue(
                label: l10n.viewOrderButtonLabel,
                value: totalLabel,
                valueFirst: true,
                style: labelStyle,
                trailingExtent: _badgeSize,
                // A pill that is a circle for 1–2 digits and widens for more,
                // rather than a fixed circle that clips "128".
                trailing: Container(
                  constraints: const BoxConstraints(minWidth: _badgeSize, minHeight: _badgeSize),
                  padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.xs),
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(color: VendorPalette.background, borderRadius: AppRadius.pill),
                  child: Text(
                    formatCount(itemCount, Localizations.localeOf(context).toString()),
                    style: textTheme.labelMedium?.copyWith(color: orderAccentBackground, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
