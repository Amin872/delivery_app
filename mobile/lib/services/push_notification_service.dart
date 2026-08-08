import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../core/errors/guard.dart';

/// Wraps FCM token registration. `functions/src/notifications.ts`'s
/// `notifyUser` reads `fcmToken` off `users/{userId}` and no-ops if it's
/// absent — this is the client side that keeps that field populated.
class PushNotificationService {
  PushNotificationService({FirebaseMessaging? messaging, FirebaseFirestore? firestore})
      : _messaging = messaging ?? FirebaseMessaging.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseMessaging _messaging;
  final FirebaseFirestore _firestore;

  Future<void> registerToken(String uid) {
    return guardFuture(() async {
      await _messaging.requestPermission();
      final token = await _messaging.getToken();
      if (token != null) {
        await saveToken(uid, token);
      }
    });
  }

  Future<void> saveToken(String uid, String token) {
    return guardFuture(
      () => _firestore.collection('users').doc(uid).update({'fcmToken': token}),
    );
  }

  Stream<String> get onTokenRefresh => guardStream(_messaging.onTokenRefresh);
}
