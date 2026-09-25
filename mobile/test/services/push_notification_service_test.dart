import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:delivery_app/services/push_notification_service.dart';

// PushNotificationService's constructor evaluates `messaging ?? FirebaseMessaging.instance`
// even when only `firestore` is injected, so a mock must always be supplied here to avoid
// touching the real (uninitialized) Firebase singleton in a unit test.
class MockFirebaseMessaging extends Mock implements FirebaseMessaging {}

void main() {
  test('saveToken writes the token to users/{uid}.fcmToken', () async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('users').doc('user-1').set({
      'email': 'a@b.com',
      'displayName': 'A',
      'role': 'customer',
    });
    final service = PushNotificationService(
      messaging: MockFirebaseMessaging(),
      firestore: firestore,
    );

    await service.saveToken('user-1', 'token-abc');

    final doc = await firestore.collection('users').doc('user-1').get();
    expect(doc.data()!['fcmToken'], 'token-abc');
  });

  group('locale (Phase 28)', () {
    test('pushLocaleCode keeps en, maps everything else to ar', () {
      expect(pushLocaleCode('en'), 'en');
      expect(pushLocaleCode('ar'), 'ar');
      expect(pushLocaleCode('fr'), 'ar');
      expect(pushLocaleCode(''), 'ar');
    });

    for (final (languageCode, stored) in [('en', 'en'), ('ar', 'ar'), ('de', 'ar')]) {
      test('saveLocale("$languageCode") writes users/{uid}.locale = "$stored" only', () async {
        final firestore = FakeFirebaseFirestore();
        final original = {'email': 'a@b.com', 'displayName': 'A', 'role': 'customer'};
        await firestore.collection('users').doc('user-1').set(original);
        final service = PushNotificationService(messaging: MockFirebaseMessaging(), firestore: firestore);

        await service.saveLocale('user-1', languageCode);

        final doc = await firestore.collection('users').doc('user-1').get();
        expect(doc.data(), {...original, 'locale': stored});
      });
    }
  });
}
