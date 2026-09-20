import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../l10n/app_localizations.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Shared "not built yet" destination for account-menu entries whose real
/// feature (payment methods, help center, terms, ...) has no backing
/// data/service yet. Keeps every unimplemented menu item navigable to a
/// real, named screen instead of a dead tap target, without inventing fake
/// data for a feature that doesn't exist — see AccountScreen's usage.
///
/// Applies the same [VendorPalette] dark-navy/cyan theme as
/// CustomerHomeScreen/StoreListScreen — this screen is currently only
/// reached from AccountScreen (also VendorPalette-themed), so it should feel
/// like a continuation of that flow rather than a jarring color switch.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({required this.title, required this.icon, super.key});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final vendorTheme = VendorPalette.themeFrom(Theme.of(context));
    final colorScheme = vendorTheme.colorScheme;

    return Theme(
      data: vendorTheme,
      child: Scaffold(
        backgroundColor: VendorPalette.background,
        appBar: AppBar(
          backgroundColor: VendorPalette.background,
          foregroundColor: VendorPalette.textPrimary,
          title: Text(title),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 40, color: colorScheme.onPrimaryContainer),
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  l10n.featureComingSoonTitle,
                  style: vendorTheme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  l10n.featureComingSoonMessage,
                  style: vendorTheme.textTheme.bodyMedium
                      ?.copyWith(color: colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ).animate().fadeIn(duration: 300.ms).scaleXY(begin: 0.94, end: 1, curve: Curves.easeOut),
        ),
      ),
    );
  }
}
