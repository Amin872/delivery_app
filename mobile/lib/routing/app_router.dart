import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/errors/error_messages.dart';
import '../core/widgets/app_spinner.dart';
import '../features/admin/screens/admin_dashboard_screen.dart';
import '../features/auth/providers/auth_provider.dart';
import '../features/auth/providers/session_provider.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/auth/screens/signup_screen.dart';
import '../features/auth/screens/forgot_password_screen.dart';
import '../features/customer/screens/customer_home_screen.dart';
import '../features/driver/screens/driver_home_screen.dart';
import '../features/notifications/widgets/notification_tap_handler.dart';
import '../features/vendor/screens/vendor_dashboard_screen.dart';
import '../l10n/app_localizations.dart';
import '../models/app_user.dart';
import 'page_transitions.dart';
import 'session_redirect.dart';

/// Shared fade+slide transition applied to every route so navigation feels
/// consistent app-wide rather than only on individually-styled screens.
CustomTransitionPage<void> _fadeSlidePage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: fadeSlideTransitionDuration,
    transitionsBuilder: buildFadeSlideTransition,
  );
}

/// The home screen for a ready user's role. Exposed as a provider only so
/// router tests can stand in lightweight homes for the real, Firestore-backed
/// ones; the app itself always uses [roleHome].
final roleHomeProvider = Provider<Widget Function(AppUser user)>((ref) => roleHome);

Widget roleHome(AppUser user) => switch (user.role) {
      UserRole.customer => const CustomerHomeScreen(),
      UserRole.driver => const DriverHomeScreen(),
      UserRole.vendor => VendorDashboardScreen(vendorId: user.id),
      UserRole.admin => const AdminDashboardScreen(),
    };

/// Whether a confirmed guest may browse the customer home at `/` (see
/// [guestBrowsingEnabledByDefault]). A provider so tests can turn it on.
final guestBrowsingEnabledProvider = Provider<bool>((ref) => guestBrowsingEnabledByDefault);

/// The home a guest browses when guest browsing is on: the customer home,
/// with no [NotificationTapHandler] — a guest never gets a notification
/// destination. A provider only so router tests can stand in a lightweight
/// home; it can only ever yield the customer home, never a vendor, driver or
/// admin one.
final guestHomeProvider = Provider<Widget Function()>((ref) => guestHome);

Widget guestHome() => const CustomerHomeScreen();

/// The routing-relevant part of [sessionProvider], as a [Listenable] for
/// [GoRouter.refreshListenable]. [ValueNotifier] only notifies when the
/// [SessionRouteKey] actually changes, so profile-only updates never re-run
/// the redirect.
final sessionRouteKeyProvider = Provider<ValueNotifier<SessionRouteKey>>((ref) {
  final notifier = ValueNotifier(SessionRouteKey.of(ref.read(sessionProvider)));
  ref.listen<SessionState>(
    sessionProvider,
    (previous, next) => notifier.value = SessionRouteKey.of(next),
  );
  ref.onDispose(notifier.dispose);
  return notifier;
});

/// One router for the app's lifetime: it reads (never watches) the session,
/// and is refreshed through [sessionRouteKeyProvider] instead of being
/// rebuilt — so auth/profile events don't reset navigation.
final appRouterProvider = Provider<GoRouter>((ref) {
  final sessionKey = ref.watch(sessionRouteKeyProvider);
  final guestBrowsing = ref.watch(guestBrowsingEnabledProvider);

  final router = GoRouter(
    // `/` rather than `/login`: while auth is unresolved the role gate shows
    // a spinner there, and a returning user goes straight to their home.
    initialLocation: homePath,
    refreshListenable: sessionKey,
    redirect: (context, state) => sessionRedirect(
      sessionKey.value,
      state.matchedLocation,
      guestBrowsing: guestBrowsing,
    ),
    routes: [
      GoRoute(
        path: loginPath,
        pageBuilder: (context, state) => _fadeSlidePage(state, const LoginScreen()),
      ),
      GoRoute(
        path: signupPath,
        pageBuilder: (context, state) => _fadeSlidePage(state, const SignupScreen()),
      ),
      GoRoute(
        path: forgotPasswordPath,
        pageBuilder: (context, state) => _fadeSlidePage(state, const ForgotPasswordScreen()),
      ),
      GoRoute(
        path: homePath,
        pageBuilder: (context, state) => _fadeSlidePage(state, const _RoleGate()),
        routes: [
          // Only with guest browsing on, so the route table with it off is
          // exactly G1-D's. A child of `/`, so it's stacked above `/` and any
          // screens a guest pushed there, which stay put underneath.
          if (guestBrowsing)
            GoRoute(
              path: signingInPath.substring(1),
              pageBuilder: (context, state) => _fadeSlidePage(state, const _SigningInScreen()),
            ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

/// Shows what `/` means for the current [SessionState]: the role's home once
/// the user's Firestore user document (and [UserRole]) has loaded, a spinner
/// while that's pending, or a Retry / Sign out screen for a missing profile
/// or an auth/profile error — never guest content.
class _RoleGate extends ConsumerStatefulWidget {
  const _RoleGate();

  @override
  ConsumerState<_RoleGate> createState() => _RoleGateState();
}

class _RoleGateState extends ConsumerState<_RoleGate> {
  // The router is no longer rebuilt per auth event, which used to discard
  // every screen pushed over a role's home. Keep that guarantee here:
  // - a change of signed-in account pops back to this gate, so nothing
  //   opened by one uid stays on top for another. The uid is remembered
  //   across states that carry none (an auth error, unresolved), so
  //   ready(A) → auth error → ready(B) still counts as a switch;
  // - signing out: with guest browsing off, the redirect to /login replaces
  //   this page (disposing this state with it). With it on, this page stays
  //   for the guest home, so it pops back here itself;
  // - a guest who signs in keeps what they were browsing if they turn out to
  //   be a customer, and has it cleared if they're a vendor, driver or admin
  //   (decided once the role is known, i.e. at ready) — or if the sign-in
  //   ends in a missing profile or an error, whose screen it would cover.
  String? _lastSignedInUid;
  bool _browsedAsGuest = false;
  bool _popToRootScheduled = false;

  @override
  void initState() {
    super.initState();
    final session = ref.read(sessionProvider);
    _lastSignedInUid = SessionRouteKey.of(session).uid;
    _browsedAsGuest = session is SessionGuest && ref.read(guestBrowsingEnabledProvider);
  }

  void _onSessionChanged(SessionState? previous, SessionState next) {
    if (next is SessionGuest) {
      // With guest browsing off, the redirect to /login handles sign-out
      // exactly as before.
      if (!ref.read(guestBrowsingEnabledProvider)) return;
      if (_lastSignedInUid != null) _schedulePopToRoot();
      _lastSignedInUid = null;
      _browsedAsGuest = true;
      return;
    }

    // While a sign-in's profile loads, the guest's screens wait under
    // /signing-in. They must never cover a missing-profile or error screen
    // (Retry / Sign out) — including an auth error, which carries no uid.
    if (_browsedAsGuest && (next is SessionProfileMissing || next is SessionError)) {
      _browsedAsGuest = false;
      _schedulePopToRoot();
    }

    final uid = SessionRouteKey.of(next).uid;
    if (uid == null) return;
    final lastUid = _lastSignedInUid;
    _lastSignedInUid = uid;
    if (lastUid != null && lastUid != uid) {
      _browsedAsGuest = false;
      _schedulePopToRoot();
      return;
    }
    if (_browsedAsGuest && next is SessionReady) {
      _browsedAsGuest = false;
      // Only customers may keep the customer screens a guest opened.
      if (next.user.role != UserRole.customer) _schedulePopToRoot();
    }
  }

  /// Pops back to this role gate after the current frame rather than from
  /// inside the provider notification, so the Navigator is never mutated
  /// mid-frame. At most one pop is pending, and it does nothing once this
  /// state is disposed (e.g. the page was replaced by a redirect).
  void _schedulePopToRoot() {
    if (_popToRootScheduled) return;
    _popToRootScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _popToRootScheduled = false;
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<SessionState>(sessionProvider, _onSessionChanged);
    final session = ref.watch(sessionProvider);
    final l10n = AppLocalizations.of(context)!;

    final Widget child = switch (session) {
      // With guest browsing on, a confirmed guest browses the customer home
      // (no notification handler). Otherwise a guest is redirected to
      // /login, and the spinner only covers the frame before that lands.
      SessionGuest() when ref.watch(guestBrowsingEnabledProvider) =>
        ref.watch(guestHomeProvider)(),
      SessionUnresolved() || SessionGuest() || SessionProfileLoading() =>
        Scaffold(body: Center(child: screenSpinner(context))),
      SessionReady(:final user) => NotificationTapHandler(
          // Opens the order behind a tapped push notification, per this
          // role — only ever mounted for a ready session.
          user: user,
          child: ref.watch(roleHomeProvider)(user),
        ),
      SessionProfileMissing() => _SessionProblemScreen(
          message: l10n.noProfileFoundMessage,
          onRetry: () => ref.invalidate(currentAppUserProvider),
        ),
      SessionError(:final error, :final isAuthError) => _SessionProblemScreen(
          message: localizedErrorMessage(context, error),
          // Re-subscribe to whichever stream failed.
          onRetry: () {
            if (isAuthError) {
              ref.invalidate(authStateChangesProvider);
            } else {
              ref.invalidate(currentAppUserProvider);
            }
          },
        ),
    };

    // Cross-fades only when the routing-relevant state changes (keyed like
    // the router's refresh), not on every profile update.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: KeyedSubtree(key: ValueKey(SessionRouteKey.of(session)), child: child),
    );
  }
}

/// Profile loading after a sign-in, with guest browsing on: covers whatever
/// a guest was browsing so the loading state is always visible, and back
/// can't dismiss it. The redirect replaces it with `/` once the session is
/// ready, missing or failed.
class _SigningInScreen extends StatelessWidget {
  const _SigningInScreen();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        key: const ValueKey('signing_in_screen'),
        body: Center(child: screenSpinner(context)),
      ),
    );
  }
}

/// A missing profile or an auth/profile error: [message] plus Retry and
/// Sign out.
class _SessionProblemScreen extends ConsumerWidget {
  const _SessionProblemScreen({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onRetry,
                child: Text(l10n.retryButton),
              ),
            ),
            TextButton(
              onPressed: () => ref.read(authServiceProvider).signOut(),
              child: Text(l10n.signOutButton),
            ),
          ],
        ),
      ),
    );
  }
}
