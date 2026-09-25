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
    case 'already-exists':
      return l10n.duplicateIdError;
    case 'action-no-longer-available':
      return l10n.actionNoLongerAvailableMessage;
    case 'requires-recent-login':
      return l10n.requiresRecentLoginMessage;
    case 'invalid-order-input':
      return l10n.orderErrorInvalidInput;
    case 'vendor-not-found':
      return l10n.orderErrorVendorNotFound;
    case 'vendor-not-approved':
      return l10n.orderErrorVendorNotApproved;
    case 'vendor-closed':
      return l10n.orderErrorVendorClosed;
    case 'vendor-invalid-delivery-fee':
      return l10n.orderErrorVendorInvalidDeliveryFee;
    case 'vendor-invalid-minimum':
      return l10n.orderErrorVendorInvalidMinimum;
    case 'menu-item-not-found':
      return l10n.orderErrorMenuItemNotFound;
    case 'menu-item-unavailable':
      return l10n.orderErrorMenuItemUnavailable;
    case 'menu-item-invalid':
      return l10n.orderErrorMenuItemInvalid;
    case 'minimum-order-not-met':
      return l10n.orderErrorMinimumNotMet;
    case 'address-not-found':
      return l10n.orderErrorAddressNotFound;
    case 'address-missing-location':
      return l10n.orderErrorAddressMissingLocation;
    case 'driver-unavailable':
      return l10n.driverUnavailableAcceptError;
    case 'contact-not-authorized':
      return l10n.contactNotAvailableMessage;
    case 'phone-unavailable':
      return l10n.phoneUnavailableMessage;
    case 'invalid-contact-request':
      return l10n.genericErrorMessage;
    default:
      return l10n.genericErrorMessage;
  }
}
