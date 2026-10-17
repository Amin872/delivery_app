import 'package:flutter/foundation.dart';

import '../features/auth/providers/session_provider.dart';
import '../models/app_user.dart';

const loginPath = '/login';
const signupPath = '/signup';
const forgotPasswordPath = '/forgot-password';
const homePath = '/';

/// Routes reachable without a signed-in user.
const authPaths = {loginPath, signupPath, forgotPasswordPath};

/// Which [SessionState] case a [SessionRouteKey] stands for. An auth error
/// and a profile error are kept apart: only the latter has a known uid.
enum SessionRouteKind {
  unresolved,
  guest,
  profileLoading,
  ready,
  profileMissing,
  authError,
  profileError,
}

/// The routing-relevant part of a [SessionState]: its kind, uid and role,
/// and nothing else. Equal keys mean routing can't have changed, so a
/// profile-only update (e.g. a toggled favorite, a renamed display name)
/// produces an equal key and doesn't re-run the router's redirect.
@immutable
class SessionRouteKey {
  const SessionRouteKey(this.kind, {this.uid, this.role});

  factory SessionRouteKey.of(SessionState session) => switch (session) {
        SessionUnresolved() => const SessionRouteKey(SessionRouteKind.unresolved),
        SessionGuest() => const SessionRouteKey(SessionRouteKind.guest),
        SessionProfileLoading(:final uid) =>
          SessionRouteKey(SessionRouteKind.profileLoading, uid: uid),
        SessionReady(:final user) =>
          SessionRouteKey(SessionRouteKind.ready, uid: user.id, role: user.role),
        SessionProfileMissing(:final uid) =>
          SessionRouteKey(SessionRouteKind.profileMissing, uid: uid),
        SessionError(:final uid) => uid == null
            ? const SessionRouteKey(SessionRouteKind.authError)
            : SessionRouteKey(SessionRouteKind.profileError, uid: uid),
      };

  final SessionRouteKind kind;
  final String? uid;
  final UserRole? role;

  @override
  bool operator ==(Object other) =>
      other is SessionRouteKey && other.kind == kind && other.uid == uid && other.role == role;

  @override
  int get hashCode => Object.hash(kind, uid, role);

  @override
  String toString() => 'SessionRouteKey($kind, uid: $uid, role: $role)';
}

/// The router's redirect, as a pure function of the session and the
/// matched location. Returns the location to go to, or null to stay.
///
/// - Unresolved: stay put. `/` shows a spinner (it's the initial location),
///   so a returning user never flashes the login screen while Firebase Auth
///   restores their session.
/// - Guest: only the auth routes (G1-D keeps guests on `/login`; there is
///   no guest browsing yet).
/// - Anything else — signed in (profile loading, ready, missing, profile
///   error) or an auth error — belongs on `/`, where the role gate shows the
///   role's home, a spinner, or an error screen with Retry and Sign out.
///   An error is never treated as a guest.
String? sessionRedirect(SessionRouteKey session, String location) {
  final onAuthRoute = authPaths.contains(location);
  switch (session.kind) {
    case SessionRouteKind.unresolved:
      return null;
    case SessionRouteKind.guest:
      return onAuthRoute ? null : loginPath;
    case SessionRouteKind.profileLoading:
    case SessionRouteKind.ready:
    case SessionRouteKind.profileMissing:
    case SessionRouteKind.authError:
    case SessionRouteKind.profileError:
      return onAuthRoute ? homePath : null;
  }
}
