import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:delivery_app/core/errors/app_exception.dart';
import 'package:delivery_app/features/auth/providers/auth_provider.dart';
import 'package:delivery_app/features/auth/providers/session_provider.dart';
import 'package:delivery_app/models/app_user.dart';
import 'package:delivery_app/services/auth_service.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

User _user(String uid) {
  final user = _MockUser();
  when(() => user.uid).thenReturn(uid);
  return user;
}

AppUser _appUser(String uid, {UserRole role = UserRole.customer}) =>
    AppUser(id: uid, email: '$uid@example.com', displayName: uid, role: role);

/// Drives [sessionProvider] through the production provider chain: the
/// mocked FirebaseAuth.authStateChanges() → AuthService.authStateChanges
/// (guardStream error mapping) → authStateChangesProvider, and users/{uid}
/// in [firestore] → AuthService.watchAppUser → currentAppUserProvider.
/// Only [profileOverride], when given, bypasses the real profile path.
class _Harness {
  _Harness({FakeFirebaseFirestore? firestore, Stream<AppUser?>? profileOverride})
      : firestore = firestore ?? FakeFirebaseFirestore() {
    when(() => _auth.authStateChanges()).thenAnswer((_) => authEvents.stream);
    // Tear-downs run last-registered-first: the container (and with it every
    // provider subscription) is disposed before the auth stream is closed.
    addTearDown(authEvents.close);
    container = ProviderContainer(overrides: [
      authServiceProvider.overrideWithValue(AuthService(auth: _auth, firestore: this.firestore)),
      if (profileOverride != null) currentAppUserProvider.overrideWith((ref) => profileOverride),
    ]);
    addTearDown(container.dispose);
    container.listen<SessionState>(sessionProvider, _record, fireImmediately: true);
  }

  final FakeFirebaseFirestore firestore;
  final _auth = _MockFirebaseAuth();
  final authEvents = StreamController<User?>.broadcast();
  late final ProviderContainer container;

  /// Every session state the listener has observed, in order.
  final states = <SessionState>[];
  final _waiters = <(bool Function(SessionState), Completer<SessionState>)>[];

  void _record(SessionState? previous, SessionState next) {
    states.add(next);
    for (final waiter in [..._waiters]) {
      if (waiter.$1(next)) {
        _waiters.remove(waiter);
        waiter.$2.complete(next);
      }
    }
  }

  /// Completes with the first observed state matching [matches] — the
  /// current one if it already matches — and fails after a timeout instead
  /// of hanging or returning an unmatched state.
  Future<SessionState> waitFor(String description, bool Function(SessionState) matches) {
    final current = container.read(sessionProvider);
    if (matches(current)) return Future.value(current);
    final completer = Completer<SessionState>();
    _waiters.add((matches, completer));
    return completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => fail('Timed out waiting for $description; observed: $states'),
    );
  }
}

/// The uid a state is about, or null when it isn't about any signed-in user.
String? _uidOf(SessionState state) => switch (state) {
      SessionUnresolved() => null,
      SessionGuest() => null,
      SessionProfileLoading(:final uid) => uid,
      SessionProfileMissing(:final uid) => uid,
      SessionReady(:final user) => user.id,
      SessionError(:final uid) => uid,
    };

bool _isReadyFor(SessionState state, String uid) => state is SessionReady && state.user.id == uid;

Future<void> _writeProfile(FakeFirebaseFirestore firestore, AppUser user) =>
    firestore.collection('users').doc(user.id).set(user.toMap());

void main() {
  group('resolveSession', () {
    const error = AppException('unavailable');
    final stackTrace = StackTrace.empty;

    test('auth loading is unresolved, never guest', () {
      expect(
        resolveSession(const AsyncLoading(), const AsyncData(null)),
        isA<SessionUnresolved>(),
      );
    });

    // Riverpod 2 keeps the previous value while re-loading: a refresh is an
    // AsyncData with isLoading set, a watch-triggered reload an AsyncLoading
    // with hasValue. Neither may be read as a settled "no user".
    for (final isRefresh in [true, false]) {
      test('auth re-loading over a previous null user is unresolved, not guest '
          '(isRefresh: $isRefresh)', () {
        final reloading = const AsyncLoading<User?>()
            .copyWithPrevious(const AsyncData<User?>(null), isRefresh: isRefresh);
        expect(reloading.isLoading, isTrue);
        expect(resolveSession(reloading, const AsyncData(null)), isA<SessionUnresolved>());
      });
    }

    test('auth error is an auth SessionError, never guest', () {
      final state = resolveSession(AsyncError<User?>(error, stackTrace), const AsyncData(null));
      expect(state, isA<SessionError>());
      state as SessionError;
      expect(state.error, same(error));
      expect(state.uid, isNull);
      expect(state.isAuthError, isTrue);
    });

    test('auth error carrying a previous null user is still an error, not guest', () {
      final failed = AsyncError<User?>(error, stackTrace)
          .copyWithPrevious(const AsyncData<User?>(null));
      expect(resolveSession(failed, const AsyncData(null)), isA<SessionError>());
    });

    test('resolved auth with no user is guest', () {
      expect(
        resolveSession(const AsyncData(null), const AsyncData(null)),
        isA<SessionGuest>(),
      );
    });

    test('signed in with the profile loading is profile-loading', () {
      final state = resolveSession(AsyncData(_user('u1')), const AsyncLoading());
      expect(state, isA<SessionProfileLoading>());
      expect((state as SessionProfileLoading).uid, 'u1');
    });

    test('signed in with a loaded profile is ready, with that role', () {
      final state = resolveSession(
        AsyncData(_user('u1')),
        AsyncData(_appUser('u1', role: UserRole.driver)),
      );
      expect(state, isA<SessionReady>());
      expect((state as SessionReady).role, UserRole.driver);
      expect(state.user.id, 'u1');
    });

    test('signed in with no profile doc is profile-missing, not guest', () {
      final state = resolveSession(AsyncData(_user('u1')), const AsyncData(null));
      expect(state, isA<SessionProfileMissing>());
      expect((state as SessionProfileMissing).uid, 'u1');
    });

    test('signed in with a profile error is a profile SessionError, not guest', () {
      final state = resolveSession(AsyncData(_user('u1')), AsyncError(error, stackTrace));
      expect(state, isA<SessionError>());
      state as SessionError;
      expect(state.uid, 'u1');
      expect(state.isAuthError, isFalse);
    });

    test('a profile error carrying a previous profile is still an error', () {
      final failed = AsyncError<AppUser?>(error, stackTrace)
          .copyWithPrevious(AsyncData<AppUser?>(_appUser('u1')));
      expect(resolveSession(AsyncData(_user('u1')), failed), isA<SessionError>());
    });

    for (final isRefresh in [true, false]) {
      test('a profile re-loading over a previous profile is profile-loading '
          '(isRefresh: $isRefresh)', () {
        final reloading = const AsyncLoading<AppUser?>()
            .copyWithPrevious(AsyncData<AppUser?>(_appUser('u1')), isRefresh: isRefresh);
        expect(resolveSession(AsyncData(_user('u1')), reloading), isA<SessionProfileLoading>());
      });

      test('a profile re-loading over a previous missing doc is profile-loading, not missing '
          '(isRefresh: $isRefresh)', () {
        final reloading = const AsyncLoading<AppUser?>()
            .copyWithPrevious(const AsyncData<AppUser?>(null), isRefresh: isRefresh);
        expect(resolveSession(AsyncData(_user('u1')), reloading), isA<SessionProfileLoading>());
      });
    }

    test("another uid's profile (stale after an account switch) is profile-loading", () {
      final state = resolveSession(AsyncData(_user('u2')), AsyncData(_appUser('u1')));
      expect(state, isA<SessionProfileLoading>());
      expect((state as SessionProfileLoading).uid, 'u2');
    });

    test('guest is produced only by successfully resolved signed-out auth', () {
      final authInputs = <AsyncValue<User?>>[
        const AsyncLoading(),
        const AsyncLoading<User?>().copyWithPrevious(const AsyncData<User?>(null)),
        const AsyncLoading<User?>()
            .copyWithPrevious(const AsyncData<User?>(null), isRefresh: false),
        AsyncError(error, stackTrace),
        AsyncError<User?>(error, stackTrace).copyWithPrevious(const AsyncData<User?>(null)),
        AsyncData(_user('u1')),
        const AsyncData(null),
      ];
      // The only settled signed-out input — guards against the list above
      // accidentally losing its one positive case.
      expect(authInputs.where((a) => a is AsyncData<User?> && !a.isLoading && a.value == null),
          hasLength(1));
      final profileInputs = <AsyncValue<AppUser?>>[
        const AsyncLoading(),
        AsyncError(error, stackTrace),
        const AsyncData(null),
        AsyncData(_appUser('u1')),
      ];
      for (final auth in authInputs) {
        final isResolvedSignedOut =
            auth is AsyncData<User?> && !auth.isLoading && auth.value == null;
        for (final profile in profileInputs) {
          expect(
            resolveSession(auth, profile) is SessionGuest,
            isResolvedSignedOut,
            reason: 'auth=$auth profile=$profile',
          );
        }
      }
    });
  });

  group('sessionProvider (production auth/profile provider chain)', () {
    test('is unresolved until auth emits, then guest once it resolves signed out', () async {
      final harness = _Harness();
      expect(harness.states.single, isA<SessionUnresolved>());

      // A full event-loop turn with no auth event: still unresolved.
      await Future<void>.delayed(Duration.zero);
      expect(harness.container.read(sessionProvider), isA<SessionUnresolved>());

      harness.authEvents.add(null);
      await harness.waitFor('guest', (s) => s is SessionGuest);
      expect(harness.states.last, isA<SessionGuest>());
      expect(harness.states.sublist(0, harness.states.length - 1),
          everyElement(isA<SessionUnresolved>()));
    });

    test('a FirebaseAuth stream error is a mapped auth SessionError, never guest', () async {
      final harness = _Harness();

      harness.authEvents.addError(FirebaseAuthException(code: 'network-request-failed'));
      final state = await harness.waitFor('auth error', (s) => s is SessionError);

      state as SessionError;
      expect(state.isAuthError, isTrue);
      // Mapped by AuthService.authStateChanges' guardStream, not injected.
      expect((state.error as AppException).code, 'network-error');
      expect(harness.states, isNot(contains(isA<SessionGuest>())));
    });

    test('an auth error after a resolved guest is an error, not a retained guest', () async {
      final harness = _Harness();
      harness.authEvents.add(null);
      await harness.waitFor('guest', (s) => s is SessionGuest);

      harness.authEvents.addError(FirebaseAuthException(code: 'network-request-failed'));
      final state = await harness.waitFor('auth error', (s) => s is SessionError);

      expect((state as SessionError).isAuthError, isTrue);
      expect(harness.container.read(sessionProvider), isA<SessionError>());
    });

    test('a users/{uid} doc passes through profile-loading, then is ready with its role',
        () async {
      final harness = _Harness();
      await _writeProfile(harness.firestore, _appUser('u1', role: UserRole.vendor));

      harness.authEvents.add(_user('u1'));
      final state = await harness.waitFor('ready for u1', (s) => _isReadyFor(s, 'u1'));

      expect((state as SessionReady).role, UserRole.vendor);
      final loadingIndex = harness.states
          .indexWhere((s) => s is SessionProfileLoading && s.uid == 'u1');
      expect(loadingIndex, isNonNegative, reason: 'observed: ${harness.states}');
      expect(loadingIndex, lessThan(harness.states.indexOf(state)));
      expect(harness.states, isNot(contains(isA<SessionGuest>())));
      expect(harness.states, isNot(contains(isA<SessionProfileMissing>())));
    });

    test('a missing users/{uid} doc is profile-missing, not guest', () async {
      final harness = _Harness();

      harness.authEvents.add(_user('u1'));
      final state = await harness.waitFor('profile missing', (s) => s is SessionProfileMissing);

      expect((state as SessionProfileMissing).uid, 'u1');
      expect(harness.states, isNot(contains(isA<SessionGuest>())));
    });

    for (final (label, role) in [('an unknown', 'superuser'), ('a missing', null)]) {
      test('$label role is a malformed-data SessionError, never a customer', () async {
        final harness = _Harness();
        await harness.firestore.collection('users').doc('u1').set({
          'email': 'u1@example.com',
          'displayName': 'u1',
          if (role != null) 'role': role,
        });

        harness.authEvents.add(_user('u1'));
        final state = await harness.waitFor(
          'profile error or ready',
          (s) => s is SessionError || s is SessionReady,
        );

        expect(state, isA<SessionError>());
        state as SessionError;
        expect(state.uid, 'u1');
        expect((state.error as AppException).code, 'malformed-data');
        expect(harness.states, isNot(contains(isA<SessionGuest>())));
      });
    }

    // ISOLATED: fake_cloud_firestore 3.1.0's DocumentReference.snapshots()
    // consults neither its security rules nor whenCalling() hooks, so a
    // failing users/{uid} listener can't be produced through the real
    // AuthService.watchAppUser path. Auth still runs through the real chain;
    // only currentAppUserProvider is overridden here (see also the
    // resolveSession profile-error tests above).
    test('ISOLATED: a profile stream error is a profile SessionError, not guest', () async {
      final harness = _Harness(
        profileOverride: Stream<AppUser?>.error(const AppException('permission-denied')),
      );

      harness.authEvents.add(_user('u1'));
      final state = await harness.waitFor('profile error', (s) => s is SessionError);

      state as SessionError;
      expect(state.uid, 'u1');
      expect((state.error as AppException).code, 'permission-denied');
      expect(harness.states, isNot(contains(isA<SessionGuest>())));
    });
  });

  group('sessionProvider account transitions', () {
    test('u1 ready → signed out → u2 never shows u1 as ready, then u2 is ready', () async {
      final harness = _Harness();
      await _writeProfile(harness.firestore, _appUser('u1', role: UserRole.driver));

      harness.authEvents.add(_user('u1'));
      await harness.waitFor('ready for u1', (s) => _isReadyFor(s, 'u1'));

      harness.authEvents.add(null);
      await harness.waitFor('guest', (s) => s is SessionGuest);

      // u2 has no profile yet, so u2's profile stays unresolved (loading,
      // then missing) until it is written below.
      final u2SignInIndex = harness.states.length;
      harness.authEvents.add(_user('u2'));
      await harness.waitFor(
        'u2 profile missing',
        (s) => s is SessionProfileMissing && s.uid == 'u2',
      );
      expect(harness.states.sublist(u2SignInIndex).map(_uidOf), everyElement('u2'));

      await _writeProfile(harness.firestore, _appUser('u2', role: UserRole.vendor));
      final state = await harness.waitFor('ready for u2', (s) => _isReadyFor(s, 'u2'));

      expect((state as SessionReady).role, UserRole.vendor);
      final afterU2 = harness.states.sublist(u2SignInIndex);
      expect(afterU2.map(_uidOf), everyElement('u2'), reason: 'observed: $afterU2');
      expect(afterU2.where((s) => _isReadyFor(s, 'u1')), isEmpty);
    });

    test('a direct u1 → u2 switch never shows u1 as ready while u2 is signed in', () async {
      final harness = _Harness();
      await _writeProfile(harness.firestore, _appUser('u1'));
      await _writeProfile(harness.firestore, _appUser('u2', role: UserRole.vendor));

      harness.authEvents.add(_user('u1'));
      await harness.waitFor('ready for u1', (s) => _isReadyFor(s, 'u1'));

      final u2SignInIndex = harness.states.length;
      harness.authEvents.add(_user('u2'));
      final state = await harness.waitFor('ready for u2', (s) => _isReadyFor(s, 'u2'));

      expect((state as SessionReady).role, UserRole.vendor);
      final afterU2 = harness.states.sublist(u2SignInIndex);
      expect(afterU2.map(_uidOf), everyElement('u2'), reason: 'observed: $afterU2');
      expect(afterU2, isNot(contains(isA<SessionGuest>())));
    });
  });
}
