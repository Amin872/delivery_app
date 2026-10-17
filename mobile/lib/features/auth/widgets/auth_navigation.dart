import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../../routing/app_router.dart' show guestBrowsingEnabledProvider;

/// Whether the auth screens sit over a guest's browsing that should be kept:
/// only with guest browsing on, and only when there is something under them
/// to go back to (a sign-in prompt pushed them).
bool _overGuestBrowsing(BuildContext context, {required bool guestBrowsing}) =>
    guestBrowsing && GoRouter.of(context).canPop();

/// Moves between the auth screens (sign-in, sign-up, forgot password).
///
/// Over a guest's browsing (see [_overGuestBrowsing]) only the top auth
/// screen is swapped, keeping the browsing (and the `/` page) underneath.
/// Otherwise — always with guest browsing off — it navigates with `go`,
/// exactly as before.
void goToAuthScreen(BuildContext context, String location) {
  final guestBrowsing =
      ProviderScope.containerOf(context, listen: false).read(guestBrowsingEnabledProvider);
  final router = GoRouter.of(context);
  if (_overGuestBrowsing(context, guestBrowsing: guestBrowsing)) {
    router.pushReplacement(location);
  } else {
    router.go(location);
  }
}

/// Leaves the auth screens for the browsing underneath them. Only shown over
/// a guest's browsing (never with guest browsing off). It pops the way the
/// back button does — `maybePop`, which does nothing when there is nothing
/// left to pop — and the router's session checks still apply wherever the
/// guest lands.
class ContinueBrowsingButton extends ConsumerWidget {
  const ContinueBrowsingButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guestBrowsing = ref.watch(guestBrowsingEnabledProvider);
    if (!_overGuestBrowsing(context, guestBrowsing: guestBrowsing)) {
      return const SizedBox.shrink();
    }
    return TextButton(
      key: const ValueKey('auth_continue_browsing_button'),
      // Re-checked at the tap rather than trusted from build time.
      onPressed: () => Navigator.of(context).maybePop(),
      child: Text(AppLocalizations.of(context)!.continueBrowsingButton),
    );
  }
}
