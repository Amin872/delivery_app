import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/preferences_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';

/// Real app-wide setting exposed here — theme mode — backed by the existing
/// [themeModeProvider] (already wired into `app.dart`'s MaterialApp, just
/// never surfaced in any UI before this screen).
///
/// Uses the same [VendorPalette] theme as AccountScreen (which pushes this
/// screen) so the two feel like one continuous flow rather than separate
/// apps — same reasoning as CustomerHomeScreen/StoreListScreen already
/// applying this palette to the browsing flow.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    // Only Light is offered until AppTheme.supportsDarkMode — Dark/System
    // had no real dark palette behind them. A previously saved dark/system
    // choice reads as Light here, matching what the app actually renders.
    final themeMode = AppTheme.supportsDarkMode ? ref.watch(themeModeProvider) : ThemeMode.light;
    final vendorTheme = VendorPalette.themeFrom(Theme.of(context));

    return Theme(
      data: vendorTheme,
      child: Scaffold(
        backgroundColor: VendorPalette.background,
        appBar: AppBar(
          backgroundColor: VendorPalette.background,
          foregroundColor: VendorPalette.textPrimary,
          title: Text(l10n.settingsTitle),
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xs),
              child: Text(
                l10n.themeModeTitle,
                style: vendorTheme.textTheme.titleSmall
                    ?.copyWith(color: VendorPalette.textSecondary),
              ),
            ),
            RadioGroup<ThemeMode>(
              groupValue: themeMode,
              onChanged: (mode) => ref.read(themeModeProvider.notifier).setThemeMode(mode!),
              child: Column(
                children: [
                  RadioListTile<ThemeMode>(
                    value: ThemeMode.light,
                    title: Text(l10n.themeModeLight),
                    secondary: const Icon(Icons.light_mode_outlined),
                  ),
                  if (AppTheme.supportsDarkMode) ...[
                    RadioListTile<ThemeMode>(
                      value: ThemeMode.dark,
                      title: Text(l10n.themeModeDark),
                      secondary: const Icon(Icons.dark_mode_outlined),
                    ),
                    RadioListTile<ThemeMode>(
                      value: ThemeMode.system,
                      title: Text(l10n.themeModeSystem),
                      secondary: const Icon(Icons.brightness_auto_outlined),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
