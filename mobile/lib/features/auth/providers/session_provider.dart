import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/app_user.dart';
import 'auth_provider.dart';

/// Where the app stands on "who is using it", combining Firebase Auth
/// (*who* is signed in) with the users/{uid} profile (*what role* they
/// have) into one value that never conflates the two async steps.
///
/// [SessionGuest] is produced in exactly one case: Firebase Auth has
/// successfully resolved and reported no user. Unresolved auth, any auth or
/// profile error, and a signed-in user without a profile are each their own
/// state — none of them may be treated as a guest.
sealed class SessionState {
  const SessionState();
}

/// Firebase Auth hasn't reported yet (cold start, session being restored).
/// Not known to be signed in *or* signed out.
class SessionUnresolved extends SessionState {
  const SessionUnresolved();
}

/// Firebase Auth resolved successfully with no signed-in user.
class SessionGuest extends SessionState {
  const SessionGuest();
}

/// Signed in as [uid]; the users/{uid} profile hasn't loaded yet.
class SessionProfileLoading extends SessionState {
  const SessionProfileLoading(this.uid);

  final String uid;
}

/// Signed in with a loaded profile; [user]'s role is the one to route on.
class SessionReady extends SessionState {
  const SessionReady(this.user);

  final AppUser user;

  UserRole get role => user.role;
}

/// Signed in as [uid], but users/{uid} doesn't exist. Note this is also
/// briefly the state during AuthService.signUp, which writes users/{uid}
/// last — it is not necessarily terminal.
class SessionProfileMissing extends SessionState {
  const SessionProfileMissing(this.uid);

  final String uid;
}

/// Firebase Auth or the profile stream failed. [uid] is null for an auth
/// error (who is signed in is unknown) and set for a profile error. A
/// malformed profile (e.g. an unknown role, see AppUser.fromMap) lands here
/// rather than defaulting to any role.
class SessionError extends SessionState {
  const SessionError(this.error, this.stackTrace, {this.uid});

  final Object error;
  final StackTrace stackTrace;
  final String? uid;

  bool get isAuthError => uid == null;
}

/// Whether [value] is a settled, error-free result. Riverpod 2 keeps the
/// previous value across a refresh — as an [AsyncData] with `isLoading`
/// set, or an [AsyncLoading] with `hasValue` — so the type alone isn't
/// enough to trust it.
bool _isSettledData<T>(AsyncValue<T> value) =>
    value is AsyncData<T> && !value.isLoading && !value.hasError;

/// Pure combination of the auth and profile [AsyncValue]s. Only settled
/// data is trusted: a loading value carrying a previous result (e.g. an
/// earlier `null` user) is still treated as unresolved, so a stale value
/// can never surface as [SessionGuest] or as another user's profile.
SessionState resolveSession(
  AsyncValue<fb_auth.User?> auth,
  AsyncValue<AppUser?> profile,
) {
  if (auth is AsyncError<fb_auth.User?>) {
    return SessionError(auth.error, auth.stackTrace);
  }
  if (!_isSettledData(auth)) return const SessionUnresolved();

  final firebaseUser = auth.requireValue;
  if (firebaseUser == null) return const SessionGuest();
  final uid = firebaseUser.uid;

  if (profile is AsyncError<AppUser?>) {
    return SessionError(profile.error, profile.stackTrace, uid: uid);
  }
  if (!_isSettledData(profile)) return SessionProfileLoading(uid);

  final appUser = profile.requireValue;
  if (appUser == null) return SessionProfileMissing(uid);
  // A profile for a different uid is a stale value from before an account
  // switch — wait for the current user's own profile instead.
  if (appUser.id != uid) return SessionProfileLoading(uid);
  return SessionReady(appUser);
}

/// The current [SessionState], derived from [authStateChangesProvider] and
/// [currentAppUserProvider] — both stay the source of truth.
final sessionProvider = Provider<SessionState>((ref) {
  return resolveSession(
    ref.watch(authStateChangesProvider),
    ref.watch(currentAppUserProvider),
  );
});
