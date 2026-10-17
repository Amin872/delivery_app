import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../../routing/session_redirect.dart';
import '../providers/auth_provider.dart';
import '../providers/session_provider.dart';

/// Opens the sign-in flow over the current screen. Pushed (not `go`) so a
/// guest who signs in as a customer comes back to whatever they were
/// browsing — the router keeps the screens under `/` (see app_router.dart).
/// A provider only so widget tests without a GoRouter can record the call.
final signInLauncherProvider = Provider<void Function(BuildContext context)>(
  (ref) => (context) => GoRouter.of(context).push(loginPath),
);

/// Gate for an action that needs a signed-in user. Returns true when there
/// is one (the action may go ahead). Otherwise returns false, and — for a
/// confirmed guest — first asks them to sign in, opening the sign-in flow if
/// they agree, so the action never just silently does nothing.
///
/// While a session is still loading or has failed there is no prompt: the
/// router covers those states with its own loading / error screens.
Future<bool> requireSignIn(BuildContext context, WidgetRef ref) async {
  if (ref.read(currentAppUserProvider).valueOrNull != null) return true;
  if (ref.read(sessionProvider) is! SessionGuest) return false;

  final l10n = AppLocalizations.of(context)!;
  final signIn = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const ValueKey('sign_in_prompt'),
      title: Text(l10n.signInRequiredTitle),
      content: Text(l10n.signInRequiredMessage),
      actions: [
        TextButton(
          key: const ValueKey('sign_in_prompt_cancel'),
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(l10n.cancelButton),
        ),
        FilledButton(
          key: const ValueKey('sign_in_prompt_confirm'),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(l10n.signInTitle),
        ),
      ],
    ),
  );
  if (signIn == true && context.mounted) ref.read(signInLauncherProvider)(context);
  return false;
}
