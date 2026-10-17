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
}
