import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';
import 'app_exception.dart';

/// Localized, user-facing message for [error] — the single place screens
/// should go instead of showing `error.toString()` / `e.toString()`.
String localizedErrorMessage(BuildContext context, Object error) {
  final code = AppException.fromError(error).code;
  final l10n = AppLocalizations.of(context)!;
  switch (code) {
    case 'invalid-credential':
      return l10n.invalidCredentialMessage;
    case 'email-already-in-use':
      return l10n.emailAlreadyInUseMessage;
    case 'weak-password':
      return l10n.weakPasswordMessage;
    case 'invalid-email':
      return l10n.invalidEmailMessage;
    case 'user-disabled':
      return l10n.userDisabledMessage;
    case 'too-many-requests':
      return l10n.tooManyRequestsMessage;
    case 'network-error':
      return l10n.networkErrorMessage;
    case 'permission-denied':
      return l10n.permissionDeniedMessage;
    case 'not-found':
      return l10n.notFoundMessage;
    case 'action-no-longer-available':
      return l10n.actionNoLongerAvailableMessage;
    default:
      return l10n.genericErrorMessage;
  }
}
