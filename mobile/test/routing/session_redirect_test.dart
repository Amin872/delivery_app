import 'package:flutter_test/flutter_test.dart';

import 'package:delivery_app/core/errors/app_exception.dart';
import 'package:delivery_app/features/auth/providers/session_provider.dart';
import 'package:delivery_app/models/app_user.dart';
import 'package:delivery_app/routing/session_redirect.dart';

AppUser _appUser(String uid, UserRole role, {List<String> favorites = const []}) => AppUser(
      id: uid,
      email: '$uid@example.com',
      displayName: uid,
      role: role,
      favoriteVendorIds: favorites,
    );

const _error = AppException('network-error');

/// One representative [SessionState] per [SessionRouteKind].
final _sessions = <SessionRouteKind, SessionState>{
  SessionRouteKind.unresolved: const SessionUnresolved(),
  SessionRouteKind.guest: const SessionGuest(),
  SessionRouteKind.profileLoading: const SessionProfileLoading('u1'),
  SessionRouteKind.ready: SessionReady(_appUser('u1', UserRole.customer)),
  SessionRouteKind.profileMissing: const SessionProfileMissing('u1'),
  SessionRouteKind.authError: const SessionError(_error, StackTrace.empty),
  SessionRouteKind.profileError: const SessionError(_error, StackTrace.empty, uid: 'u1'),
};

const _allPaths = [homePath, loginPath, signupPath, forgotPasswordPath];

void main() {
  group('SessionRouteKey.of', () {
    test('maps every SessionState case to its own kind', () {
      expect(_sessions.keys.toSet(), SessionRouteKind.values.toSet());
      _sessions.forEach((kind, session) {
        expect(SessionRouteKey.of(session).kind, kind, reason: '$session');
      });
    });

    test('an auth error has no uid; a profile error keeps its uid', () {
      final auth = SessionRouteKey.of(const SessionError(_error, StackTrace.empty));
      final profile = SessionRouteKey.of(const SessionError(_error, StackTrace.empty, uid: 'u1'));
      expect(auth, const SessionRouteKey(SessionRouteKind.authError));
      expect(profile, const SessionRouteKey(SessionRouteKind.profileError, uid: 'u1'));
    });

    test('ready carries uid and role', () {
      expect(
        SessionRouteKey.of(SessionReady(_appUser('u1', UserRole.vendor))),
        const SessionRouteKey(SessionRouteKind.ready, uid: 'u1', role: UserRole.vendor),
      );
    });

    test('profile-only changes give an equal key', () {
      final before = SessionRouteKey.of(SessionReady(_appUser('u1', UserRole.customer)));
      final after = SessionRouteKey.of(SessionReady(AppUser(
        id: 'u1',
        email: 'changed@example.com',
        displayName: 'Renamed',
        role: UserRole.customer,
        phoneNumber: '+963000000',
        favoriteVendorIds: const ['v1', 'v2'],
      )));
      expect(after, before);
      expect(after.hashCode, before.hashCode);
    });

    test('a different uid or role gives a different key', () {
      final base = SessionRouteKey.of(SessionReady(_appUser('u1', UserRole.customer)));
      expect(SessionRouteKey.of(SessionReady(_appUser('u2', UserRole.customer))), isNot(base));
      expect(SessionRouteKey.of(SessionReady(_appUser('u1', UserRole.driver))), isNot(base));
      expect(SessionRouteKey.of(const SessionProfileLoading('u1')), isNot(base));
    });
  });

  group('sessionRedirect', () {
    test('unresolved never redirects — no flash of /login on a cold start', () {
      for (final path in _allPaths) {
        expect(sessionRedirect(SessionRouteKey.of(const SessionUnresolved()), path), isNull,
            reason: path);
      }
    });

    test('a guest is sent to /login from / and may stay on any auth route (G1-D)', () {
      final guest = SessionRouteKey.of(const SessionGuest());
      expect(sessionRedirect(guest, homePath), loginPath);
      expect(sessionRedirect(guest, loginPath), isNull);
      expect(sessionRedirect(guest, signupPath), isNull);
      expect(sessionRedirect(guest, forgotPasswordPath), isNull);
    });

    for (final kind in [
      SessionRouteKind.profileLoading,
      SessionRouteKind.ready,
      SessionRouteKind.profileMissing,
      SessionRouteKind.authError,
      SessionRouteKind.profileError,
    ]) {
      test('$kind stays on / and leaves every auth route for /', () {
        final key = SessionRouteKey.of(_sessions[kind]!);
        expect(sessionRedirect(key, homePath), isNull);
        for (final path in authPaths) {
          expect(sessionRedirect(key, path), homePath, reason: path);
        }
      });
    }

    test('ready users of every role land on / (the role gate picks the home)', () {
      for (final role in UserRole.values) {
        final key = SessionRouteKey.of(SessionReady(_appUser('u1', role)));
        expect(sessionRedirect(key, loginPath), homePath, reason: '$role');
        expect(sessionRedirect(key, homePath), isNull, reason: '$role');
      }
    });

    test('errors are never routed like a guest', () {
      for (final kind in [SessionRouteKind.authError, SessionRouteKind.profileError]) {
        final key = SessionRouteKey.of(_sessions[kind]!);
        // A guest is sent from / to /login; an error stays on / (error screen).
        expect(sessionRedirect(key, homePath), isNull, reason: '$kind');
        // A guest may stay on the auth routes; an error is moved to /.
        for (final path in authPaths) {
          expect(sessionRedirect(key, path), homePath, reason: '$kind at $path');
        }
      }
    });
  });

  group('sessionRedirect with guest browsing (G1-E1)', () {
    final guest = SessionRouteKey.of(const SessionGuest());

    test('is off by default, and off keeps the G1-D redirect exactly', () {
      expect(guestBrowsingEnabledByDefault, isFalse);
      for (final MapEntry(key: kind, value: session) in _sessions.entries) {
        final key = SessionRouteKey.of(session);
        for (final path in _allPaths) {
          expect(
            sessionRedirect(key, path, guestBrowsing: false),
            sessionRedirect(key, path),
            reason: '$kind at $path',
          );
        }
      }
      expect(sessionRedirect(guest, homePath), loginPath);
    });

    test('on: a confirmed guest may stay on / and on every auth route', () {
      expect(sessionRedirect(guest, homePath, guestBrowsing: true), isNull);
      for (final path in authPaths) {
        expect(sessionRedirect(guest, path, guestBrowsing: true), isNull, reason: path);
      }
    });

    test('on: a guest leaves /signing-in for /, and anywhere unknown for /login', () {
      expect(sessionRedirect(guest, signingInPath, guestBrowsing: true), homePath);
      expect(sessionRedirect(guest, '/not-a-route', guestBrowsing: true), loginPath);
    });

    test('on: a loading profile always shows /signing-in, from anywhere', () {
      final loading = SessionRouteKey.of(const SessionProfileLoading('u1'));
      for (final path in _allPaths) {
        expect(sessionRedirect(loading, path, guestBrowsing: true), signingInPath, reason: path);
      }
      expect(sessionRedirect(loading, signingInPath, guestBrowsing: true), isNull);
    });

    test('on: ready, missing and error states leave auth routes and /signing-in for /', () {
      for (final kind in [
        SessionRouteKind.ready,
        SessionRouteKind.profileMissing,
        SessionRouteKind.authError,
        SessionRouteKind.profileError,
      ]) {
        final key = SessionRouteKey.of(_sessions[kind]!);
        expect(sessionRedirect(key, homePath, guestBrowsing: true), isNull, reason: '$kind');
        expect(sessionRedirect(key, signingInPath, guestBrowsing: true), homePath,
            reason: '$kind');
        for (final path in authPaths) {
          expect(sessionRedirect(key, path, guestBrowsing: true), homePath, reason: '$kind');
        }
      }
    });

    test('on: unresolved never redirects', () {
      final unresolved = SessionRouteKey.of(const SessionUnresolved());
      for (final path in [..._allPaths, signingInPath]) {
        expect(sessionRedirect(unresolved, path, guestBrowsing: true), isNull, reason: path);
      }
    });

    test('on: only a confirmed guest is ever allowed to stay on / as a guest', () {
      // Every non-guest state on an auth route is sent away from it, so none
      // of them can sit where a guest may.
      for (final MapEntry(key: kind, value: session) in _sessions.entries) {
        if (kind == SessionRouteKind.guest || kind == SessionRouteKind.unresolved) continue;
        final key = SessionRouteKey.of(session);
        for (final path in authPaths) {
          expect(sessionRedirect(key, path, guestBrowsing: true), isNotNull,
              reason: '$kind at $path');
        }
      }
    });
  });
}
