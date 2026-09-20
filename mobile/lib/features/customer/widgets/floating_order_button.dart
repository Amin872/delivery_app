import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
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

    return Material(
      color: orderAccentBackground,
      borderRadius: AppRadius.large,
      elevation: 4,
      child: InkWell(
        borderRadius: AppRadius.large,
        onTap: onTap,
        child: Container(
          height: _height,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                totalLabel,
                style: textTheme.titleSmall
                    ?.copyWith(color: VendorPalette.background, fontWeight: FontWeight.w700),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.viewOrderButtonLabel,
                    style: textTheme.titleSmall
                        ?.copyWith(color: VendorPalette.background, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Container(
                    width: _badgeSize,
                    height: _badgeSize,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: VendorPalette.background,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$itemCount',
                      style: textTheme.labelMedium
                          ?.copyWith(color: orderAccentBackground, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
