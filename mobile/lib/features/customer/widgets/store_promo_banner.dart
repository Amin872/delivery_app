import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';

/// Static, generic promotional banner shown on VendorMenuScreen — same
/// "hardcoded, evergreen, no fabricated specific numbers" rule as the home
/// screen's PromoBannerCarousel. Restyled for Phase 4A as a premium dark
/// navy/cyan card (subtle gradient between two [VendorPalette] surface
/// tones, cyan accent) rather than the earlier flat purple/pink fill, to
/// match this screen's dark visual language — content and localized
/// strings are unchanged, only presentation.
class StorePromoBanner extends StatelessWidget {
  const StorePromoBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      child: Container(
        constraints: const BoxConstraints(minHeight: 120),
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [VendorPalette.surfaceContainer, VendorPalette.surfaceElevated],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: VendorPalette.divider),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: VendorPalette.primaryCyan.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.local_offer_outlined, color: VendorPalette.primaryCyan),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.storePromoBannerTitle,
                    textAlign: TextAlign.start,
                    style: textTheme.titleMedium?.copyWith(color: VendorPalette.textPrimary),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    l10n.storePromoBannerSubtitle,
                    textAlign: TextAlign.start,
                    style: textTheme.bodySmall?.copyWith(color: VendorPalette.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
