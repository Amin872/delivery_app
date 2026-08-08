import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// A typed, stable-coded exception every service method throws instead of
/// letting a raw Firebase exception reach the UI. [code] is looked up
/// against a localized message table (see `core/errors/error_messages.dart`)
/// — screens should never display [cause] or `toString()` directly to a user.
class AppException implements Exception {
  const AppException(this.code, {this.cause});

  final String code;
  final Object? cause;

  /// Wraps [error] into an [AppException], mapping known Firebase error
  /// codes to a small stable vocabulary. Unrecognized codes fall back to
  /// `'unknown'` rather than leaking SDK-specific text to callers.
  factory AppException.fromError(Object error) {
    if (error is AppException) return error;
    if (error is FirebaseAuthException) {
      return AppException(_authCode(error.code), cause: error);
    }
    if (error is FirebaseFunctionsException) {
      return AppException(_sharedCode(error.code), cause: error);
    }
    if (error is FirebaseException) {
      return AppException(_sharedCode(error.code), cause: error);
    }
    return AppException('unknown', cause: error);
  }

  static String _authCode(String code) {
    switch (code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'invalid-credential';
      case 'email-already-in-use':
        return 'email-already-in-use';
      case 'weak-password':
        return 'weak-password';
      case 'invalid-email':
        return 'invalid-email';
      case 'user-disabled':
        return 'user-disabled';
      case 'too-many-requests':
        return 'too-many-requests';
      case 'network-request-failed':
        return 'network-error';
      default:
        return 'unknown';
    }
  }

  static String _sharedCode(String code) {
    switch (code) {
      case 'permission-denied':
        return 'permission-denied';
      case 'not-found':
        return 'not-found';
      case 'failed-precondition':
      case 'aborted':
        return 'action-no-longer-available';
      case 'unavailable':
      case 'network-request-failed':
      case 'deadline-exceeded':
        return 'network-error';
      default:
        return 'unknown';
    }
  }

  @override
  String toString() => 'AppException($code)';
}
