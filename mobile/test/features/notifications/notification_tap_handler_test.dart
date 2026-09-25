import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:delivery_app/core/providers/formatters_provider.dart';
import 'package:delivery_app/core/providers/preferences_provider.dart';
import 'package:delivery_app/features/customer/screens/customer_home_screen.dart'
    show firestoreServiceProvider;
import 'package:delivery_app/features/customer/screens/order_tracking_screen.dart';
import 'package:delivery_app/features/notifications/providers/push_notification_provider.dart';
import 'package:delivery_app/features/notifications/widgets/notification_tap_handler.dart';
import 'package:delivery_app/features/vendor/screens/vendor_order_detail_screen.dart';
import 'package:delivery_app/l10n/app_localizations.dart';
import 'package:delivery_app/models/app_user.dart';
import 'package:delivery_app/services/firestore_service.dart';

AppUser _user(UserRole role) =>
    AppUser(id: '${role.name}-1', email: 'x@example.com', displayName: 'X', role: role);

const _target = NotificationOrderTarget(type: 'order_status', orderId: 'order-9');

/// Pumps [NotificationTapHandler] around a stand-in home screen. Firestore
/// is an empty in-memory instance, so any order screen opened from a
/// notification sees the order as missing.
Future<ProviderContainer> _pump(WidgetTester tester, AppUser user, {NotificationOrderTarget? pending}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    firestoreServiceProvider.overrideWithValue(FirestoreService(firestore: FakeFirebaseFirestore())),
    currencyFormatProvider.overrideWithValue(NumberFormat.currency(locale: 'en', name: 'SYP')),
  ]);
  addTearDown(container.dispose);
  if (pending != null) container.read(pendingNotificationTargetProvider.notifier).state = pending;

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: NotificationTapHandler(
          user: user,
          child: const Scaffold(body: Text('role home')),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  group('notificationDestination (role-based)', () {
    test('customer -> the existing OrderTrackingScreen for that order', () {
      final screen = notificationDestination(_user(UserRole.customer), _target);
      expect(screen, isA<OrderTrackingScreen>());
      expect((screen! as OrderTrackingScreen).orderId, 'order-9');
    });

    test('vendor -> the existing VendorOrderDetailScreen, scoped to their own store', () {
      final screen = notificationDestination(_user(UserRole.vendor), _target);
      expect(screen, isA<VendorOrderDetailScreen>());
      expect((screen! as VendorOrderDetailScreen).orderId, 'order-9');
      expect((screen as VendorOrderDetailScreen).vendorId, 'vendor-1');
    });

    test('driver and admin stay on their home (the driver active flow lives there)', () {
      expect(notificationDestination(_user(UserRole.driver), _target), isNull);
      expect(notificationDestination(_user(UserRole.admin), _target), isNull);
    });

    test('the role decides, not the notification type', () {
      const vendorType = NotificationOrderTarget(type: 'order_created', orderId: 'order-9');
      expect(notificationDestination(_user(UserRole.customer), vendorType), isA<OrderTrackingScreen>());
    });
  });

  group('NotificationTapHandler', () {
    testWidgets('customer: a tap that arrives later opens the order and is consumed', (tester) async {
      final container = await _pump(tester, _user(UserRole.customer));
      expect(find.text('role home'), findsOneWidget);

      container.read(pendingNotificationTargetProvider.notifier).state = _target;
      await tester.pumpAndSettle();

      expect(find.byType(OrderTrackingScreen), findsOneWidget);
      expect(container.read(pendingNotificationTargetProvider), isNull);
    });

    testWidgets('customer: a tap pending before the home built (launch) is opened', (tester) async {
      final container = await _pump(tester, _user(UserRole.customer), pending: _target);

      expect(find.byType(OrderTrackingScreen), findsOneWidget);
      expect(container.read(pendingNotificationTargetProvider), isNull);
    });

    testWidgets('customer: a missing order fails safely with the localized error', (tester) async {
      await _pump(tester, _user(UserRole.customer), pending: _target);

      expect(find.byType(OrderTrackingScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
    });

    testWidgets('vendor: opens their order detail; a missing order shows the existing message', (tester) async {
      await _pump(tester, _user(UserRole.vendor), pending: _target);

      expect(find.byType(VendorOrderDetailScreen), findsOneWidget);
      expect(find.text('This order is no longer in your list.'), findsOneWidget);
    });

    testWidgets('driver: stays on the home screen (active delivery flow) and consumes the tap', (tester) async {
      final container = await _pump(tester, _user(UserRole.driver), pending: _target);

      expect(find.text('role home'), findsOneWidget);
      expect(find.byType(OrderTrackingScreen), findsNothing);
      expect(container.read(pendingNotificationTargetProvider), isNull);
    });

    testWidgets('repeated taps replace the opened order instead of stacking screens', (tester) async {
      final container = await _pump(tester, _user(UserRole.customer), pending: _target);
      container.read(pendingNotificationTargetProvider.notifier).state =
          const NotificationOrderTarget(type: 'order_delivered', orderId: 'order-10');
      await tester.pumpAndSettle();

      expect(find.byType(OrderTrackingScreen), findsOneWidget);
      expect(tester.widget<OrderTrackingScreen>(find.byType(OrderTrackingScreen)).orderId, 'order-10');
    });
  });
}
