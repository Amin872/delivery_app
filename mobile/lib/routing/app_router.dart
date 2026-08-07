import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/providers/auth_provider.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/auth/screens/signup_screen.dart';
import '../features/customer/screens/customer_home_screen.dart';
import '../features/driver/screens/driver_home_screen.dart';
import '../features/vendor/screens/vendor_dashboard_screen.dart';
import '../models/app_user.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateChangesProvider);

  return GoRouter(
    initialLocation: '/login',
    redirect: (context, state) {
      final isLoggedIn = authState.valueOrNull != null;
      final isAuthRoute = state.matchedLocation == '/login' ||
          state.matchedLocation == '/signup';

      if (!isLoggedIn && !isAuthRoute) return '/login';
      if (isLoggedIn && isAuthRoute) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/signup',
        builder: (context, state) => const SignupScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) => const _RoleGate(),
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

    return appUserAsync.when(
      data: (appUser) {
        if (appUser == null) {
          return const Scaffold(
            body: Center(child: Text('No profile found for this account.')),
          );
        }
        switch (appUser.role) {
          case UserRole.customer:
            return const CustomerHomeScreen();
          case UserRole.driver:
            return const DriverHomeScreen();
          case UserRole.vendor:
            return VendorDashboardScreen(vendorId: appUser.id);
        }
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) =>
          Scaffold(body: Center(child: Text('Error: $error'))),
    );
  }
}
