import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';

/// Tappable pill styled like a search field, centered in VendorMenuScreen's
/// header between the back button and the favorite heart — opens the same
/// `SearchScreen` as the home screen's floating search button rather than
/// duplicating a live-search experience on this screen too. Fixed
/// dark-translucent color (from [VendorPalette], not `ColorScheme`) is
/// deliberate: this pill sits on an arbitrary vendor photo, not the app's
/// own background, so it needs to read clearly against the photo rather
/// than adapt to light/dark theme — same reasoning as
/// [StoreHeaderActionButton]. Dark (not the previous frosted-white) to
/// match Phase 4A's dark-navy/cyan direction for this screen.
class StoreSearchBar extends StatelessWidget {
  const StoreSearchBar({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Material(
        color: VendorPalette.surfaceElevated.withValues(alpha: 0.72),
        borderRadius: AppRadius.pill,
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.35),
        child: InkWell(
          borderRadius: AppRadius.pill,
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            alignment: Alignment.center,
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.search, color: VendorPalette.textSecondary, size: 22),
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    l10n.searchFieldHint,
                    textAlign: TextAlign.start,
                    style: TextStyle(color: VendorPalette.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
