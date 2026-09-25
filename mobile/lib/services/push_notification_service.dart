import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../core/errors/guard.dart';

/// Wraps FCM for the app. `functions/src/notifications.ts`'s `notifyUser`
/// reads `fcmToken` (and `locale`, to pick Arabic or English text) off
/// `users/{userId}` and no-ops if the token is absent — this is the client
/// side that keeps both fields populated, plus the two ways a user can open
/// the app from a notification.
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

  /// Stores the app language on `users/{uid}.locale` so server-sent pushes
  /// arrive in it. Only 'ar' or 'en' is ever written ([pushLocaleCode]).
  Future<void> saveLocale(String uid, String languageCode) {
    return guardFuture(
      () => _firestore.collection('users').doc(uid).update({'locale': pushLocaleCode(languageCode)}),
    );
  }

  Stream<String> get onTokenRefresh => guardStream(_messaging.onTokenRefresh);

  /// A notification tapped while the app was in the background.
  Stream<RemoteMessage> get onMessageOpenedApp => FirebaseMessaging.onMessageOpenedApp;

  /// The notification (if any) whose tap launched the app from terminated.
  Future<RemoteMessage?> getInitialMessage() => _messaging.getInitialMessage();
}

/// 'en' stays 'en'; everything else — including 'ar' — is 'ar', the app's
/// default language (see LocaleController).
String pushLocaleCode(String languageCode) => languageCode == 'en' ? 'en' : 'ar';
