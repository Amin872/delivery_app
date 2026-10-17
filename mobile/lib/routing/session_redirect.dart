import 'package:flutter/foundation.dart';

import '../features/auth/providers/session_provider.dart';
import '../models/app_user.dart';

const loginPath = '/login';
const signupPath = '/signup';
const forgotPasswordPath = '/forgot-password';
const homePath = '/';

/// Shown while a signed-in user's profile loads, but only with guest browsing
/// on: a child of `/`, so it sits above any screens a guest had open (keeping
/// them for later) instead of being hidden underneath them.
const signingInPath = '/signing-in';

/// Routes reachable without a signed-in user.
const authPaths = {loginPath, signupPath, forgotPasswordPath};

/// Whether a signed-out guest may browse the customer home at `/` instead of
/// being sent to `/login`. Off until the customer screens prompt guests to
/// sign in for protected actions (G1-E2); the router reads it through
/// `guestBrowsingEnabledProvider`, which tests can override.
const guestBrowsingEnabledByDefault = false;

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
/// - Guest: only the auth routes; sent to `/login` from anywhere else.
/// - Anything else — signed in (profile loading, ready, missing, profile
///   error) or an auth error — belongs on `/`, where the role gate shows the
///   role's home, a spinner, or an error screen with Retry and Sign out.
///   An error is never treated as a guest.
///
/// With [guestBrowsing] on, see [_guestBrowsingRedirect] instead; off (the
/// default) is exactly the behaviour above.
String? sessionRedirect(
  SessionRouteKey session,
  String location, {
  bool guestBrowsing = guestBrowsingEnabledByDefault,
}) {
  final onAuthRoute = authPaths.contains(location);
  if (guestBrowsing) return _guestBrowsingRedirect(session, location, onAuthRoute);
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

/// The redirect with guest browsing on. Only a confirmed [SessionGuest] is a
/// guest — unresolved, loading, missing and error states never are.
///
/// - Unresolved: stay put, as with it off.
/// - Guest: `/` (the guest home) and the auth routes; `/signing-in` returns
///   to `/`; anywhere else goes to `/login`.
/// - Profile loading: `/signing-in`, from anywhere. It's pushed above `/`,
///   so whatever a guest was browsing stays underneath while the loading
///   state stays visible.
/// - Ready, missing profile, or an error: `/`, leaving the auth routes and
///   `/signing-in`. For a customer that reveals the screens a guest had open;
///   the role gate clears them for any other role, and for a missing profile
///   or an error, so they never cover its Retry / Sign out screen.
String? _guestBrowsingRedirect(SessionRouteKey session, String location, bool onAuthRoute) {
  final onSigningIn = location == signingInPath;
  switch (session.kind) {
    case SessionRouteKind.unresolved:
      return null;
    case SessionRouteKind.guest:
      if (onAuthRoute || location == homePath) return null;
      return onSigningIn ? homePath : loginPath;
    case SessionRouteKind.profileLoading:
      return onSigningIn ? null : signingInPath;
    case SessionRouteKind.ready:
    case SessionRouteKind.profileMissing:
    case SessionRouteKind.authError:
    case SessionRouteKind.profileError:
      return onAuthRoute || onSigningIn ? homePath : null;
  }
}
