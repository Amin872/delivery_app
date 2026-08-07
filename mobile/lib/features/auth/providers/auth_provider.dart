import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/app_user.dart';
import '../../../services/auth_service.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final authStateChangesProvider = StreamProvider<fb_auth.User?>((ref) {
  return ref.watch(authServiceProvider).authStateChanges;
});

/// Resolves the signed-in Firebase [User] to the app's Firestore user
/// document, which carries the [UserRole] used for role-based routing.
final currentAppUserProvider = FutureProvider<AppUser?>((ref) async {
  final firebaseUser = ref.watch(authStateChangesProvider).valueOrNull;
  if (firebaseUser == null) return null;
  return ref.watch(authServiceProvider).fetchAppUser(firebaseUser.uid);
});
