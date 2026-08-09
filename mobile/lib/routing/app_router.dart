import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/errors/error_messages.dart';
import '../core/widgets/animated_async.dart';
import '../core/widgets/app_spinner.dart';
import '../features/admin/screens/admin_dashboard_screen.dart';
import '../features/auth/providers/auth_provider.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/auth/screens/signup_screen.dart';
import '../features/auth/screens/forgot_password_screen.dart';
import '../features/customer/screens/customer_home_screen.dart';
import '../features/driver/screens/driver_home_screen.dart';
import '../features/vendor/screens/vendor_dashboard_screen.dart';
import '../l10n/app_localizations.dart';
import '../models/app_user.dart';
import 'page_transitions.dart';

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

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateChangesProvider);

  return GoRouter(
    initialLocation: '/login',
    redirect: (context, state) {
      final isLoggedIn = authState.valueOrNull != null;
      final isAuthRoute = state.matchedLocation == '/login' ||
          state.matchedLocation == '/signup' ||
          state.matchedLocation == '/forgot-password';

      if (!isLoggedIn && !isAuthRoute) return '/login';
      if (isLoggedIn && isAuthRoute) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) => _fadeSlidePage(state, const LoginScreen()),
      ),
      GoRoute(
        path: '/signup',
        pageBuilder: (context, state) => _fadeSlidePage(state, const SignupScreen()),
      ),
      GoRoute(
        path: '/forgot-password',
        pageBuilder: (context, state) => _fadeSlidePage(state, const ForgotPasswordScreen()),
      ),
      GoRoute(
        path: '/',
        pageBuilder: (context, state) => _fadeSlidePage(state, const _RoleGate()),
      ),
    ],
  );
});

/// Routes a signed-in user to their role's home screen once their
/// Firestore user document (and [UserRole]) has loaded.
class _RoleGate extends ConsumerWidget {
  const _RoleGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appUserAsync = ref.watch(currentAppUserProvider);

    return appUserAsync.animatedWhen(
      data: (appUser) {
        if (appUser == null) {
          final l10n = AppLocalizations.of(context)!;
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l10n.noProfileFoundMessage),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => ref.invalidate(currentAppUserProvider),
                    child: Text(l10n.retryButton),
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
        switch (appUser.role) {
          case UserRole.customer:
            return const CustomerHomeScreen();
          case UserRole.driver:
            return const DriverHomeScreen();
          case UserRole.vendor:
            return VendorDashboardScreen(vendorId: appUser.id);
          case UserRole.admin:
            return const AdminDashboardScreen();
        }
      },
      loading: () => Scaffold(body: Center(child: screenSpinner(context))),
      error: (error, _) => Scaffold(
        body: Center(child: Text(localizedErrorMessage(context, error))),
      ),
    );
  }
}
