import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Circular semi-transparent icon button overlaid directly on the hero
/// image — VendorMenuScreen's back arrow and favorite heart both use this,
/// so they read clearly against a photo of any brightness rather than a
/// bare icon. Fixed navy-tinted translucent fill (not `ColorScheme`) is
/// deliberate here: this sits on an arbitrary vendor photo, not the app's
/// own background, so it needs to contrast with the photo rather than
/// adapt to light/dark theme — same reasoning as [StoreSearchBar]'s pill.
/// The tint still matches [VendorPalette] rather than a neutral black so it
/// reads as part of the same dark-navy/cyan design language.
///
/// No manual RTL mirroring needed here: directional glyphs like
/// `Icons.arrow_back` already carry `matchTextDirection: true` on the
/// `IconData` itself, so a plain `Icon(icon)` auto-flips for RTL locales.
class StoreHeaderActionButton extends StatelessWidget {
  const StoreHeaderActionButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.color,
    super.key,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? color;

  // Touch target — within the 44–48dp band explicitly rather than trusting
  // IconButton's own default sizing to land there.
  static const _diameter = 46.0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Material(
        color: VendorPalette.surfaceElevated.withValues(alpha: 0.55),
        shape: const CircleBorder(),
        elevation: 1,
        shadowColor: AppPalette.shadow.withValues(alpha: 0.4),
        child: SizedBox(
          width: _diameter,
          height: _diameter,
          child: IconButton(
            icon: Icon(icon),
            color: color ?? VendorPalette.textPrimary,
            tooltip: tooltip,
            onPressed: onPressed,
          ),
        ),
      ),
    );
  }
}
