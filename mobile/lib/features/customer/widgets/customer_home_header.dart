import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import 'store_header_action_button.dart';

/// Fixed (non-scrolling) top bar for the redesigned [CustomerHomeScreen] —
/// a circular notification bell pinned to the physical left, the city
/// selector centered, and a circular account button pinned to the physical
/// right. Matches the reference screenshots' header exactly (bell/account
/// always on the same physical side regardless of locale, same as this
/// codebase's other literal-position overrides — e.g. ProductDetailsSheet's
/// close button), so this uses `Positioned(left:/right:)` inside a `Stack`
/// rather than a `Row` (which would reorder under RTL). Reuses
/// [StoreHeaderActionButton] for the two circular buttons instead of a new
/// button style, and [VendorPalette] for the dark-navy background this
/// screen now shares with `VendorMenuScreen`.
class CustomerHomeHeader extends StatelessWidget {
  const CustomerHomeHeader({
    required this.locationLabel,
    required this.onLocationTap,
    required this.onNotificationsTap,
    required this.onAccountTap,
    super.key,
  });

  final String locationLabel;
  final VoidCallback onLocationTap;
  final VoidCallback onNotificationsTap;
  final VoidCallback? onAccountTap;

  static const double height = 64;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark, // dark status-bar icons on the light background
      child: ColoredBox(
        color: VendorPalette.background,
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: height,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  left: 12,
                  child: StoreHeaderActionButton(
                    icon: Icons.notifications_none_outlined,
                    tooltip: l10n.notificationsTitle,
                    onPressed: onNotificationsTap,
                  ),
                ),
                Center(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: onLocationTap,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.keyboard_arrow_down, color: VendorPalette.textPrimary),
                          const SizedBox(width: 4),
                          Text(
                            locationLabel,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(color: VendorPalette.textPrimary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 12,
                  child: StoreHeaderActionButton(
                    icon: Icons.person_outline,
                    tooltip: l10n.accountTitle,
                    onPressed: onAccountTap,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
