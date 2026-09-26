import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:delivery_app/core/theme/app_colors.dart';
import 'package:delivery_app/core/theme/app_theme.dart';

void main() {
  test('one identity: the theme is built from AppPalette', () {
    final theme = AppTheme.light;
    expect(theme.scaffoldBackgroundColor, AppPalette.background);
    expect(theme.colorScheme.primary, AppPalette.primary);
    expect(theme.colorScheme.secondary, AppPalette.accent);
    expect(theme.colorScheme.onSurface, AppPalette.textPrimary);
    expect(theme.colorScheme.error, AppPalette.error);
  });

  test('legacy VendorPalette is only an alias of the unified tokens', () {
    expect(VendorPalette.background, AppPalette.background);
    expect(VendorPalette.primaryCyan, AppPalette.primary);
    expect(VendorPalette.textPrimary, AppPalette.textPrimary);
    final base = AppTheme.light;
    expect(identical(VendorPalette.themeFrom(base), base), isTrue);
  });

  test('dark mode is not a second identity yet', () {
    expect(AppTheme.dark.colorScheme.primary, AppTheme.light.colorScheme.primary);
    expect(AppTheme.dark.scaffoldBackgroundColor, AppTheme.light.scaffoldBackgroundColor);
  });

  test('button minimum sizes have a finite width (Phase 1 C1 guard)', () {
    final theme = AppTheme.light;
    for (final size in [
      theme.filledButtonTheme.style!.minimumSize!.resolve({}),
      theme.textButtonTheme.style!.minimumSize!.resolve({}),
      theme.outlinedButtonTheme.style!.minimumSize!.resolve({}),
      theme.elevatedButtonTheme.style!.minimumSize!.resolve({}),
    ]) {
      expect(size!.width.isFinite, isTrue);
    }
  });

  test('status colours are semantic tokens', () {
    final scheme = AppTheme.light.colorScheme;
    expect(AppColors.success(scheme), AppPalette.success);
    expect(AppColors.warning(scheme), AppPalette.warning);
    expect(AppColors.info(scheme), AppPalette.info);
    expect(scheme.brightness, Brightness.light);
  });
}
