import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_emulators.dart';
import '../../../core/providers/preferences_provider.dart';
import '../../../services/push_notification_service.dart';
import '../../auth/providers/auth_provider.dart';

final pushNotificationServiceProvider =
    Provider<PushNotificationService>((ref) => PushNotificationService());

final pushForegroundMessageProvider = StreamProvider<RemoteMessage>((ref) {
  return FirebaseMessaging.onMessage;
});

/// Side-effect provider: registers/keeps the signed-in user's FCM token in
/// sync with `users/{uid}.fcmToken`, and the app language with
/// `users/{uid}.locale` (so server pushes arrive in Arabic or English). Has
/// no meaningful value of its own — something (e.g. `app.dart`) just needs
/// to watch it to keep it alive for the app's lifetime. Re-runs on every
/// auth-state change, so it covers both a fresh sign-in and an app restart
/// with an existing session.
final pushNotificationSyncProvider = Provider<void>((ref) {
  final service = ref.watch(pushNotificationServiceProvider);
  final firebaseUser = ref.watch(authStateChangesProvider).valueOrNull;
  if (firebaseUser == null) return;

  final uid = firebaseUser.uid;
  // Local emulator browsing (USE_FIREBASE_EMULATORS): no FCM token is
  // requested or stored — that would reach the live project's FCM service.
  // The language sync below still runs; it only touches Firestore.
  if (!useFirebaseEmulators) {
    // A failed registration (denied permission, unsupported platform, ...)
    // shouldn't disrupt anything else in the app — push notifications are an
    // enhancement, not on the critical path.
    unawaited(service.registerToken(uid).catchError((_) {}));

    final subscription = service.onTokenRefresh.listen(
      (token) => service.saveToken(uid, token).catchError((_) {}),
    );
    ref.onDispose(subscription.cancel);
  }

  // Language: now, and whenever the user switches it.
  unawaited(service.saveLocale(uid, ref.read(localeProvider).languageCode).catchError((_) {}));
  ref.listen(localeProvider, (previous, next) {
    if (previous?.languageCode != next.languageCode) {
      unawaited(service.saveLocale(uid, next.languageCode).catchError((_) {}));
    }
  });
});

/// Where a tapped order notification wants to take the user: the data
/// payload `{type, orderId}` sent by functions/src/notifications.ts.
class NotificationOrderTarget {
  const NotificationOrderTarget({required this.type, required this.orderId});

  final String type;
  final String orderId;

  @override
  bool operator ==(Object other) =>
      other is NotificationOrderTarget && other.type == type && other.orderId == orderId;

  @override
  int get hashCode => Object.hash(type, orderId);
}

/// The notification types the server sends (notifications.ts
/// NotificationType).
const orderNotificationTypes = {
  'order_created',
  'order_status',
  'driver_assigned',
  'order_delivered',
  'order_cancelled',
  'driver_reassigned',
};

/// Reads a notification's data payload, or null when it isn't a
/// well-formed order notification — so a malformed or foreign payload is
/// simply ignored.
NotificationOrderTarget? parseNotificationData(Map<String, dynamic> data) {
  final type = data['type'];
  final orderId = data['orderId'];
  if (type is! String || !orderNotificationTypes.contains(type)) return null;
  if (orderId is! String || orderId.trim().isEmpty) return null;
  return NotificationOrderTarget(type: type, orderId: orderId);
}

/// The order a tapped notification is waiting to open. Set by
/// [pushNotificationTapProvider]; consumed (and cleared) by
/// NotificationTapHandler once the signed-in user's role is known.
final pendingNotificationTargetProvider = StateProvider<NotificationOrderTarget?>((ref) => null);

/// Side-effect provider (watched by `app.dart`): turns a notification tap —
/// the one that launched the app, or one tapped while it was in the
/// background — into a [pendingNotificationTargetProvider] value.
final pushNotificationTapProvider = Provider<void>((ref) {
  final service = ref.watch(pushNotificationServiceProvider);
  void handle(RemoteMessage? message) {
    final target = message == null ? null : parseNotificationData(message.data);
    if (target != null) ref.read(pendingNotificationTargetProvider.notifier).state = target;
  }

  unawaited(service.getInitialMessage().then(handle).catchError((_) {}));
  final subscription = service.onMessageOpenedApp.listen(handle, onError: (_) {});
  ref.onDispose(subscription.cancel);
});
