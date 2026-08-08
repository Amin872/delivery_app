import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/push_notification_service.dart';
import '../../auth/providers/auth_provider.dart';

final pushNotificationServiceProvider =
    Provider<PushNotificationService>((ref) => PushNotificationService());

final pushForegroundMessageProvider = StreamProvider<RemoteMessage>((ref) {
  return FirebaseMessaging.onMessage;
});

/// Side-effect provider: registers/keeps the signed-in user's FCM token in
/// sync with `users/{uid}.fcmToken`. Has no meaningful value of its own —
/// something (e.g. `app.dart`) just needs to watch it to keep it alive for
/// the app's lifetime. Re-runs on every auth-state change, so it covers both
/// a fresh sign-in and an app restart with an existing session.
final pushNotificationSyncProvider = Provider<void>((ref) {
  final service = ref.watch(pushNotificationServiceProvider);
  final firebaseUser = ref.watch(authStateChangesProvider).valueOrNull;
  if (firebaseUser == null) return;

  final uid = firebaseUser.uid;
  // A failed registration (denied permission, unsupported platform, ...)
  // shouldn't disrupt anything else in the app — push notifications are an
  // enhancement, not on the critical path.
  unawaited(service.registerToken(uid).catchError((_) {}));

  final subscription = service.onTokenRefresh.listen(
    (token) => service.saveToken(uid, token).catchError((_) {}),
  );
  ref.onDispose(subscription.cancel);
});
