import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:delivery_app/core/providers/preferences_provider.dart';
import 'package:delivery_app/features/auth/providers/auth_provider.dart';
import 'package:delivery_app/features/notifications/providers/push_notification_provider.dart';
import 'package:delivery_app/services/push_notification_service.dart';

class _MockFirebaseMessaging extends Mock implements FirebaseMessaging {}

class _MockUser extends Mock implements User {}

/// Records what the providers ask of the service; tap sources are
/// controllable.
class _FakePushService extends PushNotificationService {
  _FakePushService({this.initialMessage})
      : super(messaging: _MockFirebaseMessaging(), firestore: FakeFirebaseFirestore());

  final RemoteMessage? initialMessage;
  final openedController = StreamController<RemoteMessage>.broadcast();
  final locales = <(String, String)>[];
  final registered = <String>[];

  @override
  Future<void> registerToken(String uid) async => registered.add(uid);

  @override
  Future<void> saveLocale(String uid, String languageCode) async => locales.add((uid, languageCode));

  @override
  Stream<String> get onTokenRefresh => const Stream.empty();

  @override
  Stream<RemoteMessage> get onMessageOpenedApp => openedController.stream;

  @override
  Future<RemoteMessage?> getInitialMessage() async => initialMessage;
}

Future<ProviderContainer> _container(_FakePushService service, {String? locale}) async {
  SharedPreferences.setMockInitialValues({if (locale != null) 'locale': locale});
  final prefs = await SharedPreferences.getInstance();
  final user = _MockUser();
  when(() => user.uid).thenReturn('user-1');
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    pushNotificationServiceProvider.overrideWithValue(service),
    authStateChangesProvider.overrideWith((ref) => Stream.value(user)),
  ]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('parseNotificationData', () {
    test('reads a well-formed order payload', () {
      expect(
        parseNotificationData({'type': 'order_status', 'orderId': 'o1'}),
        const NotificationOrderTarget(type: 'order_status', orderId: 'o1'),
      );
      for (final type in orderNotificationTypes) {
        expect(parseNotificationData({'type': type, 'orderId': 'o1'}), isNotNull, reason: type);
      }
    });

    test('ignores malformed or foreign payloads', () {
      for (final data in <Map<String, dynamic>>[
        {},
        {'type': 'order_status'},
        {'orderId': 'o1'},
        {'type': 'marketing', 'orderId': 'o1'},
        {'type': 'order_status', 'orderId': ''},
        {'type': 'order_status', 'orderId': '  '},
        {'type': 1, 'orderId': 'o1'},
        {'type': 'order_status', 'orderId': 42},
      ]) {
        expect(parseNotificationData(data), isNull, reason: '$data');
      }
    });
  });

  group('pushNotificationSyncProvider — locale (Phase 28)', () {
    test('writes the current language on sign-in, and again when it changes', () async {
      final service = _FakePushService();
      final container = await _container(service, locale: 'en');
      container.listen(pushNotificationSyncProvider, (_, __) {});
      await container.read(authStateChangesProvider.future);
      await pumpEventQueue();

      expect(service.registered, ['user-1']);
      expect(service.locales, [('user-1', 'en')]);

      container.read(localeProvider.notifier).setLocale(const Locale('ar'));
      await pumpEventQueue();

      expect(service.locales, [('user-1', 'en'), ('user-1', 'ar')]);
    });

    test('defaults to Arabic when no language was ever chosen', () async {
      final service = _FakePushService();
      final container = await _container(service);
      container.listen(pushNotificationSyncProvider, (_, __) {});
      await container.read(authStateChangesProvider.future);
      await pumpEventQueue();

      expect(service.locales, [('user-1', 'ar')]);
    });
  });

  group('pushNotificationTapProvider (Phase 28)', () {
    test('a notification that launched the app becomes the pending target', () async {
      final service = _FakePushService(
        initialMessage: const RemoteMessage(data: {'type': 'order_delivered', 'orderId': 'o1'}),
      );
      final container = await _container(service);
      container.listen(pushNotificationTapProvider, (_, __) {});
      await pumpEventQueue();

      expect(
        container.read(pendingNotificationTargetProvider),
        const NotificationOrderTarget(type: 'order_delivered', orderId: 'o1'),
      );
    });

    test('a notification tapped while in the background becomes the pending target', () async {
      final service = _FakePushService();
      final container = await _container(service);
      container.listen(pushNotificationTapProvider, (_, __) {});
      await pumpEventQueue();
      expect(container.read(pendingNotificationTargetProvider), isNull);

      service.openedController.add(const RemoteMessage(data: {'type': 'driver_assigned', 'orderId': 'o2'}));
      await pumpEventQueue();

      expect(
        container.read(pendingNotificationTargetProvider),
        const NotificationOrderTarget(type: 'driver_assigned', orderId: 'o2'),
      );
    });

    test('a malformed tapped payload is ignored safely', () async {
      final service = _FakePushService(initialMessage: const RemoteMessage(data: {'type': 'nope'}));
      final container = await _container(service);
      container.listen(pushNotificationTapProvider, (_, __) {});
      await pumpEventQueue();
      service.openedController.add(const RemoteMessage(data: {'orderId': 'o3'}));
      await pumpEventQueue();

      expect(container.read(pendingNotificationTargetProvider), isNull);
    });
  });
}
