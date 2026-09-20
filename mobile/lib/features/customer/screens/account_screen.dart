import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_spinner.dart';
import '../../../core/widgets/placeholder_screen.dart';
import '../../../core/widgets/responsive_center.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/app_user.dart';
import '../../../routing/page_transitions.dart';
import '../../auth/providers/auth_provider.dart';
import '../widgets/account_menu_section.dart';
import 'delivery_addresses_screen.dart';
import 'favorites_screen.dart';
import 'my_orders_screen.dart';
import 'order_history_screen.dart';
import 'personal_info_screen.dart';

/// Reached via the profile icon in [CustomerHomeScreen]'s header.
///
/// Kept deliberately short — a greeting header plus exactly the 7 shortcuts
/// a customer reaches for often (orders, favorites, payment, delivery
/// address, help, terms). No email/phone/language/settings/notifications/
/// sign-out here — those live one tap away in [PersonalInfoScreen], opened
/// by tapping the header. This split is the actual fix for the earlier
/// "crowded settings page" feedback: a short list with real visual
/// hierarchy, not a longer one with smaller rows.
///
/// Uses the same [VendorPalette] dark-navy/cyan theme as CustomerHomeScreen
/// itself so Account reads as a continuation of the home screen's identity.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({required this.customerId, super.key});

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
          title: Text(l10n.accountTitle),
        ),
        body: appUserAsync.when(
          data: (appUser) => appUser == null
              ? _NoProfileState(ref: ref)
              : ResponsiveCenter(child: _AccountBody(appUser: appUser)),
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

/// Not signed in / no Firestore profile doc yet — same recovery affordance
/// (retry the stream, or sign out) as `app_router.dart`'s `_RoleGate` for the
/// identical underlying condition.
class _NoProfileState extends StatelessWidget {
  const _NoProfileState({required this.ref});

  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.noProfileFoundMessage,
              style: const TextStyle(color: VendorPalette.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: () => ref.invalidate(currentAppUserProvider),
              child: Text(l10n.retryButton),
            ),
            TextButton(
              onPressed: () => ref.read(authServiceProvider).signOut(),
              child: Text(l10n.signOutButton),
            ),
          ],
        ),
      ),
    );
  }
}

/// Avatar + "مرحباً، {name}!" — the whole card is one tap target opening
/// [PersonalInfoScreen], where email/phone/edit actually live. Deliberately
/// no email/phone shown here (see this file's class doc).
class _GreetingHeader extends StatelessWidget {
  const _GreetingHeader({required this.displayName, required this.onTap});

  final String displayName;
  final VoidCallback onTap;

  String get _initials {
    final parts = displayName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    final first = parts.first.substring(0, 1);
    final last = parts.length > 1 ? parts.last.substring(0, 1) : '';
    return (first + last).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final name = displayName.trim().isEmpty ? l10n.guestGreetingFallback : displayName;

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 0),
      child: Material(
        color: colorScheme.surfaceContainer,
        borderRadius: AppRadius.large,
        child: InkWell(
          borderRadius: AppRadius.large,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: colorScheme.primary, shape: BoxShape.circle),
                  child: Text(
                    _initials,
                    style: textTheme.titleLarge?.copyWith(color: colorScheme.onPrimary),
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Text(
                    l10n.accountGreetingLabel(name),
                    style: textTheme.titleLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.06, end: 0, curve: Curves.easeOut);
  }
}

class _AccountBody extends StatelessWidget {
  const _AccountBody({required this.appUser});

  final AppUser appUser;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
      children: [
        _GreetingHeader(
          displayName: appUser.displayName,
          onTap: () => Navigator.of(context)
              .push(fadeSlideRoute(PersonalInfoScreen(customerId: appUser.id))),
        ),
        const SizedBox(height: AppSpacing.sm),
        AccountMenuSection(
          title: '',
          items: [
            AccountMenuItem(
              icon: Icons.receipt_long_outlined,
              label: l10n.myOrdersTitle,
              onTap: () => Navigator.of(context)
                  .push(fadeSlideRoute(MyOrdersScreen(customerId: appUser.id))),
            ),
            AccountMenuItem(
              icon: Icons.history_outlined,
              label: l10n.orderHistoryTitle,
              onTap: () => Navigator.of(context)
                  .push(fadeSlideRoute(OrderHistoryScreen(customerId: appUser.id))),
            ),
            AccountMenuItem(
              icon: Icons.favorite_border_outlined,
              label: l10n.favoritesTitle,
              onTap: () => Navigator.of(context).push(fadeSlideRoute(const FavoritesScreen())),
            ),
            AccountMenuItem(
              icon: Icons.account_balance_wallet_outlined,
              label: l10n.paymentMethodsTitle,
              onTap: () => Navigator.of(context).push(fadeSlideRoute(
                  PlaceholderScreen(title: l10n.paymentMethodsTitle, icon: Icons.payment_outlined))),
            ),
            AccountMenuItem(
              icon: Icons.location_on_outlined,
              label: l10n.deliveryAddressLabel,
              onTap: () => Navigator.of(context)
                  .push(fadeSlideRoute(DeliveryAddressesScreen(customerId: appUser.id))),
            ),
            AccountMenuItem(
              icon: Icons.support_agent_outlined,
              label: l10n.helpSupportTitle,
              onTap: () => Navigator.of(context).push(fadeSlideRoute(PlaceholderScreen(
                  title: l10n.helpSupportTitle, icon: Icons.support_agent_outlined))),
            ),
            AccountMenuItem(
              icon: Icons.description_outlined,
              label: l10n.termsPrivacyTitle,
              onTap: () => Navigator.of(context).push(fadeSlideRoute(PlaceholderScreen(
                  title: l10n.termsPrivacyTitle, icon: Icons.description_outlined))),
            ),
          ],
        ),
      ],
    );
  }
}
