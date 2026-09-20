import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/l10n/enum_labels.dart';
import '../../../core/providers/preferences_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_spinner.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/language_toggle_button.dart';
import '../../../core/widgets/placeholder_screen.dart';
import '../../../core/widgets/responsive_center.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/app_user.dart';
import '../../../models/city.dart';
import '../../../routing/page_transitions.dart';
import '../../auth/providers/auth_provider.dart';
import '../widgets/account_menu_section.dart';
import '../widgets/profile_header.dart';
import 'delivery_addresses_screen.dart';
import 'edit_profile_screen.dart';
import 'settings_screen.dart';

/// "الملف الشخصي" — opened by tapping the avatar/greeting on the main
/// [AccountScreen]. Holds everything that screen deliberately does NOT show
/// (email, phone, language, region, account settings, delete account, sign
/// out) so the main Account screen can stay a short list of shortcuts while
/// this screen holds the fuller profile/settings surface.
class PersonalInfoScreen extends ConsumerWidget {
  const PersonalInfoScreen({required this.customerId, super.key});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final appUserAsync = ref.watch(currentAppUserProvider);
    final vendorTheme = VendorPalette.themeFrom(Theme.of(context));

    return Theme(
      data: vendorTheme,
      child: Scaffold(
        backgroundColor: VendorPalette.background,
        appBar: AppBar(
          backgroundColor: VendorPalette.background,
          foregroundColor: VendorPalette.textPrimary,
          title: Text(l10n.personalInfoTitle),
        ),
        body: appUserAsync.when(
          data: (appUser) => appUser == null
              ? const SizedBox.shrink()
              : ResponsiveCenter(child: _PersonalInfoBody(appUser: appUser)),
          loading: () => Center(child: screenSpinner(context)),
          error: (error, _) => Center(
            child: Text(
              localizedErrorMessage(context, error),
              style: const TextStyle(color: VendorPalette.textSecondary),
            ),
          ),
        ),
      ),
    );
  }
}

class _PersonalInfoBody extends ConsumerWidget {
  const _PersonalInfoBody({required this.appUser});

  final AppUser appUser;

  Future<void> _openCityPicker(BuildContext context, WidgetRef ref, City current) {
    final l10n = AppLocalizations.of(context)!;
    return showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(l10n.selectCityTitle, style: Theme.of(sheetContext).textTheme.titleMedium),
            ),
            for (final city in City.values)
              ListTile(
                title: Text(cityLabel(sheetContext, city)),
                trailing: city == current
                    ? Icon(Icons.check, color: Theme.of(sheetContext).colorScheme.primary)
                    : null,
                onTap: () {
                  ref.read(selectedCityProvider.notifier).setCity(city);
                  Navigator.of(sheetContext).pop();
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.signOutConfirmTitle,
      message: l10n.signOutConfirmMessage,
    );
    if (confirmed == true) {
      await ref.read(authServiceProvider).signOut();
    }
  }

  Future<void> _confirmDeleteAccount(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.deleteAccountButton,
      message: l10n.deleteAccountConfirmMessage,
      isDestructive: true,
    );
    if (confirmed != true) return;
    try {
      await ref.read(authServiceProvider).deleteAccount();
    } catch (error) {
      if (!context.mounted) return;
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(localizedErrorMessage(context, error)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.confirmButton),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final selectedCity = ref.watch(selectedCityProvider);

    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
      children: [
        ProfileHeader(
          displayName: appUser.displayName,
          email: appUser.email,
          phoneNumber: appUser.phoneNumber,
          onEditTap: () =>
              Navigator.of(context).push(fadeSlideRoute(EditProfileScreen(appUser: appUser))),
        ),
        const SizedBox(height: AppSpacing.sm),
        AccountMenuSection(
          title: l10n.accountTitle,
          items: [
            AccountMenuItem(
              icon: Icons.location_on_outlined,
              label: l10n.deliveryAddressLabel,
              onTap: () => Navigator.of(context)
                  .push(fadeSlideRoute(DeliveryAddressesScreen(customerId: appUser.id))),
            ),
            AccountMenuItem(
              icon: Icons.translate_outlined,
              label: l10n.languageToggleTooltip,
              trailing: const LanguageToggleButton(),
            ),
            AccountMenuItem(
              icon: Icons.map_outlined,
              label: l10n.regionCityLabel,
              subtitle: cityLabel(context, selectedCity),
              onTap: () => _openCityPicker(context, ref, selectedCity),
            ),
            AccountMenuItem(
              icon: Icons.notifications_outlined,
              label: l10n.notificationPreferencesTitle,
              onTap: () => Navigator.of(context).push(fadeSlideRoute(PlaceholderScreen(
                  title: l10n.notificationPreferencesTitle, icon: Icons.notifications_outlined))),
            ),
            AccountMenuItem(
              icon: Icons.settings_outlined,
              label: l10n.settingsTitle,
              onTap: () => Navigator.of(context).push(fadeSlideRoute(const SettingsScreen())),
            ),
            AccountMenuItem(
              icon: Icons.privacy_tip_outlined,
              label: l10n.termsPrivacyTitle,
              onTap: () => Navigator.of(context).push(fadeSlideRoute(PlaceholderScreen(
                  title: l10n.termsPrivacyTitle, icon: Icons.description_outlined))),
            ),
          ],
        ),
        AccountMenuSection(
          title: l10n.dangerZoneTitle,
          items: [
            AccountMenuItem(
              icon: Icons.delete_forever_outlined,
              label: l10n.deleteAccountButton,
              iconColor: colorScheme.error,
              labelColor: colorScheme.error,
              onTap: () => _confirmDeleteAccount(context, ref),
            ),
            AccountMenuItem(
              icon: Icons.logout,
              label: l10n.signOutButton,
              iconColor: colorScheme.error,
              labelColor: colorScheme.error,
              trailing: const SizedBox.shrink(),
              onTap: () => _confirmSignOut(context, ref),
            ),
          ],
        ),
      ],
    );
  }
}
