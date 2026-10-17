import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:delivery_app/core/errors/app_exception.dart';
import 'package:delivery_app/core/errors/error_messages.dart';
import 'package:delivery_app/core/providers/formatters_provider.dart';
import 'package:delivery_app/core/providers/preferences_provider.dart';
import 'package:delivery_app/features/auth/providers/auth_provider.dart';
import 'package:delivery_app/features/auth/providers/session_provider.dart';
import 'package:delivery_app/features/auth/screens/forgot_password_screen.dart';
import 'package:delivery_app/features/auth/screens/login_screen.dart';
import 'package:delivery_app/features/auth/screens/signup_screen.dart';
import 'package:delivery_app/features/customer/screens/customer_home_screen.dart'
    show firestoreServiceProvider;
import 'package:delivery_app/features/customer/screens/order_tracking_screen.dart';
import 'package:delivery_app/features/notifications/providers/push_notification_provider.dart';
import 'package:delivery_app/l10n/app_localizations.dart';
import 'package:delivery_app/models/app_user.dart';
import 'package:delivery_app/routing/app_router.dart';
import 'package:delivery_app/routing/session_redirect.dart';
import 'package:delivery_app/services/auth_service.dart';
import 'package:delivery_app/services/firestore_service.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

/// Records sign-outs instead of reaching Firebase.
class _RecordingAuthService extends AuthService {
  _RecordingAuthService() : super(auth: _MockFirebaseAuth(), firestore: FakeFirebaseFirestore());

  int signOutCalls = 0;

  @override
  Future<void> signOut() async {
    signOutCalls++;
  }
}

/// The session the router sees; each test drives it directly.
final _session = StateProvider<SessionState>((ref) => const SessionUnresolved());

AppUser _appUser(
  String uid,
  UserRole role, {
  String? displayName,
  List<String> favorites = const [],
}) =>
    AppUser(
      id: uid,
      email: '$uid@example.com',
      displayName: displayName ?? uid,
      role: role,
      favoriteVendorIds: favorites,
    );

String _homeLabel(AppUser user) => 'home:${user.role.name}:${user.id}';

const _authError = AppException('network-error');
const _profileError = AppException('permission-denied');

class _Harness {
  _Harness(this.tester, this.container, this.authService);

  final WidgetTester tester;
  final ProviderContainer container;
  final _RecordingAuthService authService;
  int authStreamBuilds = 0;
  int profileStreamBuilds = 0;

  GoRouter get router => container.read(appRouterProvider);

  String get location => router.routerDelegate.currentConfiguration.uri.path;

  Future<void> setSession(SessionState session) async {
    container.read(_session.notifier).state = session;
    await settle();
  }

  /// Pumps past the role gate's cross-fade and the route transitions. The
  /// screen spinner animates forever, so pumpAndSettle can't be used.
  Future<void> settle() async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  AppLocalizations get l10n => lookupAppLocalizations(const Locale('en'));
}

Future<_Harness> _pumpRouter(WidgetTester tester, {SessionState? initial}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final authService = _RecordingAuthService();
  late final _Harness harness;
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    authServiceProvider.overrideWithValue(authService),
    sessionProvider.overrideWith((ref) => ref.watch(_session)),
    // Counted so Retry's invalidation of the right stream can be checked.
    authStateChangesProvider.overrideWith((ref) {
      harness.authStreamBuilds++;
      return const Stream<User?>.empty();
    }),
    currentAppUserProvider.overrideWith((ref) {
      harness.profileStreamBuilds++;
      return const Stream<AppUser?>.empty();
    }),
    roleHomeProvider.overrideWithValue(
      (user) => Scaffold(body: Center(child: Text(_homeLabel(user)))),
    ),
    // For the real OrderTrackingScreen a notification tap opens.
    firestoreServiceProvider.overrideWithValue(
      FirestoreService(firestore: FakeFirebaseFirestore()),
    ),
    currencyFormatProvider.overrideWithValue(NumberFormat.currency(locale: 'en', name: 'SYP')),
  ]);
  addTearDown(container.dispose);
  harness = _Harness(tester, container, authService);
  if (initial != null) container.read(_session.notifier).state = initial;
  // Keep both streams alive so an invalidation rebuilds them.
  container.listen(authStateChangesProvider, (previous, next) {});
  container.listen(currentAppUserProvider, (previous, next) {});

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: container.read(appRouterProvider),
      ),
    ),
  );
  await harness.settle();
  return harness;
}

/// Pushes a plain screen over the current one, the way role homes open
/// their detail screens (Navigator.push, not go_router).
void _pushOver(WidgetTester tester, Finder from, String label) {
  Navigator.of(tester.element(from)).push(
    MaterialPageRoute<void>(builder: (_) => Scaffold(body: Text(label))),
  );
}

void main() {
  group('cold start', () {
    testWidgets('unresolved auth shows a spinner on /, never the login screen', (tester) async {
      final harness = await _pumpRouter(tester);

      expect(harness.location, homePath);
      expect(find.byType(LoginScreen), findsNothing);

      // Auth resolves to a returning user: straight to their home, with the
      // login screen never built on the way.
      final user = _appUser('u1', UserRole.customer);
      harness.container.read(_session.notifier).state = const SessionProfileLoading('u1');
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byType(LoginScreen), findsNothing);
      }
      harness.container.read(_session.notifier).state = SessionReady(user);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byType(LoginScreen), findsNothing);
      }
      expect(find.text(_homeLabel(user)), findsOneWidget);
      expect(harness.location, homePath);
    });

    testWidgets('unresolved auth that resolves to a guest goes to /login', (tester) async {
      final harness = await _pumpRouter(tester);

      await harness.setSession(const SessionGuest());

      expect(harness.location, loginPath);
      expect(find.byType(LoginScreen), findsOneWidget);
    });
  });

  group('guest (G1-D: still sent to /login)', () {
    testWidgets('/ redirects to /login', (tester) async {
      final harness = await _pumpRouter(tester, initial: const SessionGuest());
      expect(harness.location, loginPath);

      harness.router.go(homePath);
      await harness.settle();

      expect(harness.location, loginPath);
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('signup and forgot-password stay reachable', (tester) async {
      final harness = await _pumpRouter(tester, initial: const SessionGuest());

      harness.router.go(signupPath);
      await harness.settle();
      expect(harness.location, signupPath);
      expect(find.byType(SignupScreen), findsOneWidget);

      harness.router.go(forgotPasswordPath);
      await harness.settle();
      expect(harness.location, forgotPasswordPath);
      expect(find.byType(ForgotPasswordScreen), findsOneWidget);
    });

    testWidgets('a pending notification tap does not open anything for a guest', (tester) async {
      final harness = await _pumpRouter(tester, initial: const SessionGuest());
      const target = NotificationOrderTarget(type: 'order_status', orderId: 'order-9');

      harness.container.read(pendingNotificationTargetProvider.notifier).state = target;
      await harness.settle();

      expect(find.byType(OrderTrackingScreen), findsNothing);
      expect(harness.container.read(pendingNotificationTargetProvider), target);
      expect(harness.location, loginPath);
    });
  });

  group('signed in', () {
    for (final role in UserRole.values) {
      testWidgets('a ready $role reaches only the $role home', (tester) async {
        final user = _appUser('${role.name}-1', role);
        final harness = await _pumpRouter(tester, initial: SessionReady(user));

        expect(harness.location, homePath);
        expect(find.text(_homeLabel(user)), findsOneWidget);
        for (final other in UserRole.values.where((r) => r != role)) {
          expect(find.textContaining('home:${other.name}:'), findsNothing);
        }
        expect(find.byType(LoginScreen), findsNothing);
      });
    }

    testWidgets('signing in on /login (loading, then ready) lands on the home', (tester) async {
      final harness = await _pumpRouter(tester, initial: const SessionGuest());
      expect(harness.location, loginPath);

      await harness.setSession(const SessionProfileLoading('u1'));
      expect(harness.location, homePath);
      expect(find.byType(LoginScreen), findsNothing);

      final user = _appUser('u1', UserRole.vendor);
      await harness.setSession(SessionReady(user));
      expect(find.text(_homeLabel(user)), findsOneWidget);
    });

    testWidgets('a signed-in user sent to an auth route is returned to /', (tester) async {
      final harness = await _pumpRouter(
        tester,
        initial: SessionReady(_appUser('u1', UserRole.customer)),
      );

      for (final path in authPaths) {
        harness.router.go(path);
        await harness.settle();
        expect(harness.location, homePath, reason: path);
      }
    });

    testWidgets('signing out drops screens pushed over the home and shows /login', (tester) async {
      final user = _appUser('u1', UserRole.customer);
      final harness = await _pumpRouter(tester, initial: SessionReady(user));
      _pushOver(tester, find.text(_homeLabel(user)), 'private screen');
      await harness.settle();
      expect(find.text('private screen'), findsOneWidget);

      await harness.setSession(const SessionGuest());

      expect(harness.location, loginPath);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('private screen'), findsNothing);
    });

    testWidgets('switching account drops screens the previous uid opened', (tester) async {
      final u1 = _appUser('u1', UserRole.customer);
      final harness = await _pumpRouter(tester, initial: SessionReady(u1));
      _pushOver(tester, find.text(_homeLabel(u1)), "u1's order");
      await harness.settle();

      await harness.setSession(const SessionProfileLoading('u2'));
      final u2 = _appUser('u2', UserRole.customer);
      await harness.setSession(SessionReady(u2));

      expect(find.text("u1's order"), findsNothing);
      expect(find.text(_homeLabel(u2)), findsOneWidget);
    });

    testWidgets('an account switch through an auth error drops the previous uid\'s screens',
        (tester) async {
      final u1 = _appUser('u1', UserRole.customer);
      final harness = await _pumpRouter(tester, initial: SessionReady(u1));
      _pushOver(tester, find.text(_homeLabel(u1)), "u1's order");
      await harness.settle();
      expect(find.text("u1's order"), findsOneWidget);

      // An auth error carries no uid and doesn't leave /, so the role gate
      // must remember u1 across it.
      await harness.setSession(const SessionError(_authError, StackTrace.empty));
      final u2 = _appUser('u2', UserRole.vendor);
      await harness.setSession(SessionReady(u2));

      expect(find.text("u1's order"), findsNothing);
      expect(find.text(_homeLabel(u2)), findsOneWidget);
      expect(find.textContaining('home:customer:'), findsNothing);
      expect(harness.location, homePath);
    });

    testWidgets('the same uid recovering from an auth error keeps its screens', (tester) async {
      final u1 = _appUser('u1', UserRole.customer);
      final harness = await _pumpRouter(tester, initial: SessionReady(u1));
      _pushOver(tester, find.text(_homeLabel(u1)), "u1's order");
      await harness.settle();

      await harness.setSession(const SessionError(_authError, StackTrace.empty));
      await harness.setSession(SessionReady(u1));

      expect(find.text("u1's order"), findsOneWidget);
    });

    testWidgets('a pending notification tap opens only once the session is ready', (tester) async {
      final harness = await _pumpRouter(tester, initial: const SessionProfileLoading('u1'));
      const target = NotificationOrderTarget(type: 'order_status', orderId: 'order-9');
      harness.container.read(pendingNotificationTargetProvider.notifier).state = target;
      await harness.settle();
      expect(find.byType(OrderTrackingScreen), findsNothing);

      await harness.setSession(SessionReady(_appUser('u1', UserRole.customer)));

      expect(find.byType(OrderTrackingScreen), findsOneWidget);
      expect(harness.container.read(pendingNotificationTargetProvider), isNull);
    });
  });

  group('router stability', () {
    testWidgets('one GoRouter instance across every session change', (tester) async {
      final harness = await _pumpRouter(tester);
      final router = harness.router;

      for (final session in <SessionState>[
        const SessionGuest(),
        const SessionProfileLoading('u1'),
        SessionReady(_appUser('u1', UserRole.customer)),
        const SessionError(_profileError, StackTrace.empty, uid: 'u1'),
        const SessionError(_authError, StackTrace.empty),
        const SessionGuest(),
        SessionReady(_appUser('u2', UserRole.admin)),
      ]) {
        await harness.setSession(session);
        expect(identical(harness.router, router), isTrue, reason: '$session');
      }
    });

    testWidgets('profile-only changes neither refresh the router nor disturb navigation',
        (tester) async {
      final user = _appUser('u1', UserRole.customer);
      final harness = await _pumpRouter(tester, initial: SessionReady(user));
      var refreshes = 0;
      final routeKey = harness.container.read(sessionRouteKeyProvider);
      void onRefresh() => refreshes++;
      routeKey.addListener(onRefresh);
      addTearDown(() => routeKey.removeListener(onRefresh));
      _pushOver(tester, find.text(_homeLabel(user)), 'detail screen');
      await harness.settle();

      await harness.setSession(SessionReady(
        _appUser('u1', UserRole.customer, displayName: 'Renamed', favorites: const ['v1']),
      ));

      expect(refreshes, 0);
      expect(harness.location, homePath);
      expect(find.text('detail screen'), findsOneWidget);

      // A routing-relevant change (the role) does refresh.
      await harness.setSession(SessionReady(_appUser('u1', UserRole.driver)));
      expect(refreshes, 1);
    });
  });

  group('missing profile and errors', () {
    testWidgets('a missing profile shows the existing message with Retry and Sign out',
        (tester) async {
      final harness = await _pumpRouter(tester, initial: const SessionProfileMissing('u1'));
      final l10n = harness.l10n;

      expect(harness.location, homePath);
      expect(find.text(l10n.noProfileFoundMessage), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);

      final profileBuilds = harness.profileStreamBuilds;
      await tester.tap(find.text(l10n.retryButton));
      await harness.settle();
      expect(harness.profileStreamBuilds, profileBuilds + 1);

      await tester.tap(find.text(l10n.signOutButton));
      await harness.settle();
      expect(harness.authService.signOutCalls, 1);
    });

    testWidgets('an auth error shows an error screen, not the guest login', (tester) async {
      final harness = await _pumpRouter(
        tester,
        initial: const SessionError(_authError, StackTrace.empty),
      );
      final l10n = harness.l10n;

      expect(harness.location, homePath);
      expect(find.byType(LoginScreen), findsNothing);
      final context = tester.element(find.text(l10n.retryButton));
      expect(find.text(localizedErrorMessage(context, _authError)), findsOneWidget);
      expect(find.text(l10n.signOutButton), findsOneWidget);

      // Retry re-subscribes to the auth stream, not the profile stream.
      final authBuilds = harness.authStreamBuilds;
      final profileBuilds = harness.profileStreamBuilds;
      await tester.tap(find.text(l10n.retryButton));
      await harness.settle();
      expect(harness.authStreamBuilds, authBuilds + 1);
      expect(harness.profileStreamBuilds, profileBuilds);

      await tester.tap(find.text(l10n.signOutButton));
      await harness.settle();
      expect(harness.authService.signOutCalls, 1);
    });

    testWidgets('an auth error while on /login moves to the error screen', (tester) async {
      final harness = await _pumpRouter(tester, initial: const SessionGuest());
      expect(harness.location, loginPath);

      await harness.setSession(const SessionError(_authError, StackTrace.empty));

      expect(harness.location, homePath);
      expect(find.byType(LoginScreen), findsNothing);
      expect(find.text(harness.l10n.retryButton), findsOneWidget);
    });

    testWidgets('a profile error shows an error screen whose Retry reloads the profile',
        (tester) async {
      final harness = await _pumpRouter(
        tester,
        initial: const SessionError(_profileError, StackTrace.empty, uid: 'u1'),
      );
      final l10n = harness.l10n;

      expect(harness.location, homePath);
      expect(find.byType(LoginScreen), findsNothing);
      final context = tester.element(find.text(l10n.retryButton));
      expect(find.text(localizedErrorMessage(context, _profileError)), findsOneWidget);

      final authBuilds = harness.authStreamBuilds;
      final profileBuilds = harness.profileStreamBuilds;
      await tester.tap(find.text(l10n.retryButton));
      await harness.settle();
      expect(harness.profileStreamBuilds, profileBuilds + 1);
      expect(harness.authStreamBuilds, authBuilds);
    });

    testWidgets('a pending notification tap does not open behind an error', (tester) async {
      final harness = await _pumpRouter(
        tester,
        initial: const SessionError(_profileError, StackTrace.empty, uid: 'u1'),
      );
      const target = NotificationOrderTarget(type: 'order_status', orderId: 'order-9');

      harness.container.read(pendingNotificationTargetProvider.notifier).state = target;
      await harness.settle();

      expect(find.byType(OrderTrackingScreen), findsNothing);
      expect(harness.container.read(pendingNotificationTargetProvider), target);
    });
  });
}
