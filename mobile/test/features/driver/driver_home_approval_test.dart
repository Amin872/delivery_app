import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:delivery_app/core/providers/preferences_provider.dart';
import 'package:delivery_app/features/auth/providers/auth_provider.dart';
import 'package:delivery_app/features/customer/screens/customer_home_screen.dart'
    show allCitiesProvider;
import 'package:delivery_app/models/city.dart';
import 'package:delivery_app/features/driver/providers/driver_location_provider.dart';
import 'package:delivery_app/features/driver/screens/driver_home_screen.dart';
import 'package:delivery_app/l10n/app_localizations.dart';
import 'package:delivery_app/models/app_user.dart';
import 'package:delivery_app/models/approval_status.dart';
import 'package:delivery_app/models/driver.dart';
import 'package:delivery_app/models/order.dart';

const _driverId = 'driver-1';

DeliveryOrder _order(String id, OrderStatus status, {String? driverId}) => DeliveryOrder(
      id: id,
      customerId: 'customer-1',
      vendorId: 'vendor-1',
      driverId: driverId,
      items: const [],
      status: status,
      total: 10,
      deliveryAddress: 'Queue address $id',
      createdAt: DateTime(2026, 9, 22),
    );

class _Harness {
  bool queueQueried = false;

  Future<void> pump(
    WidgetTester tester,
    ApprovalStatus status, {
    DeliveryOrder? activeOrder,
    bool isAvailable = true,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          // The order cards label cities (Phase 25); no live Firestore here.
          allCitiesProvider.overrideWith((ref) => Stream.value(const <CityOption>[])),
          currentAppUserProvider.overrideWith(
            (ref) => Stream.value(const AppUser(
              id: _driverId,
              email: 'driver@example.com',
              displayName: 'Driver One',
              role: UserRole.driver,
            )),
          ),
          driverSelfProvider(_driverId).overrideWith(
            (ref) => Stream.value(Driver(
              id: _driverId,
              userId: _driverId,
              isAvailable: isAvailable,
              approvalStatus: status,
            )),
          ),
          activeDriverOrderProvider(_driverId).overrideWith((ref) => Stream.value(activeOrder)),
          // No GPS in widget tests.
          driverLocationSyncProvider(_driverId).overrideWith((ref) {}),
          availableOrdersProvider.overrideWith((ref) {
            queueQueried = true;
            return Stream.value([_order('queued-1', OrderStatus.readyForPickup)]);
          }),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const DriverHomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }
}

/// Sign-out (with stats and language) lives in the AppBar's "more" menu.
Future<void> _expectSignOutInMoreMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('driver_more_menu')));
  await tester.pumpAndSettle();
  expect(find.text('Sign out'), findsOneWidget);
  expect(find.text('Earnings'), findsOneWidget);
  expect(find.text('Change language'), findsOneWidget);
}

void main() {
  testWidgets('approved: the existing queue, availability switch and Accept', (tester) async {
    final harness = _Harness();
    await harness.pump(tester, ApprovalStatus.approved);

    expect(find.text('Available deliveries'), findsOneWidget);
    expect(harness.queueQueried, isTrue);
    expect(find.text('Queue address queued-1'), findsOneWidget);
    expect(find.text('Accept'), findsOneWidget);
    expect(find.byKey(const ValueKey('driver_available_switch')), findsOneWidget);
    expect(find.byKey(const ValueKey('driver_approval_pending')), findsNothing);
  });

  testWidgets('pending: approval notice; no queue query, switch or Accept', (tester) async {
    final harness = _Harness();
    await harness.pump(tester, ApprovalStatus.pending);

    expect(find.byKey(const ValueKey('driver_approval_pending')), findsOneWidget);
    expect(find.text('Pending approval'), findsOneWidget); // AppBar title
    expect(find.text('Pending'), findsOneWidget); // ApprovalStatusBadge
    // The unclaimed queue is never even subscribed to.
    expect(harness.queueQueried, isFalse);
    expect(find.text('Accept'), findsNothing);
    expect(find.byKey(const ValueKey('driver_available_switch')), findsNothing);
    await _expectSignOutInMoreMenu(tester);
  });

  testWidgets('rejected: rejection notice; no queue query, switch or Accept', (tester) async {
    final harness = _Harness();
    await harness.pump(tester, ApprovalStatus.rejected);

    expect(find.byKey(const ValueKey('driver_approval_rejected')), findsOneWidget);
    expect(find.text('Not approved'), findsOneWidget); // AppBar title
    expect(find.text('Rejected'), findsOneWidget); // ApprovalStatusBadge
    expect(harness.queueQueried, isFalse);
    expect(find.text('Accept'), findsNothing);
    expect(find.byKey(const ValueKey('driver_available_switch')), findsNothing);
    await _expectSignOutInMoreMenu(tester);
  });

  for (final status in [ApprovalStatus.pending, ApprovalStatus.rejected]) {
    testWidgets('${status.name}: an in-flight delivery stays visible and advanceable',
        (tester) async {
      final harness = _Harness();
      await harness.pump(
        tester,
        status,
        activeOrder: _order('active-1', OrderStatus.driverAssigned, driverId: _driverId),
      );

      expect(find.byKey(ValueKey('driver_approval_${status.name}')), findsOneWidget);
      expect(find.textContaining('Queue address active-1'), findsOneWidget);
      expect(find.text('Move to Picked up'), findsOneWidget);
      expect(harness.queueQueried, isFalse);
    });
  }

  group('availability (Phase 25)', () {
    testWidgets('approved + offline: offline notice, no queue subscription, switch kept',
        (tester) async {
      final harness = _Harness();
      await harness.pump(tester, ApprovalStatus.approved, isAvailable: false);

      expect(find.byKey(const ValueKey('driver_offline')), findsOneWidget);
      expect(find.text("You're offline"), findsOneWidget); // AppBar title
      // The unclaimed queue is never even subscribed to while offline.
      expect(harness.queueQueried, isFalse);
      expect(find.text('Accept'), findsNothing);
      // The switch stays so the driver can go back online.
      expect(find.byKey(const ValueKey('driver_available_switch')), findsOneWidget);
      await _expectSignOutInMoreMenu(tester);
    });

    testWidgets('approved + offline: an in-flight delivery stays visible and advanceable',
        (tester) async {
      final harness = _Harness();
      await harness.pump(
        tester,
        ApprovalStatus.approved,
        isAvailable: false,
        activeOrder: _order('active-1', OrderStatus.driverAssigned, driverId: _driverId),
      );

      expect(find.byKey(const ValueKey('driver_offline')), findsOneWidget);
      expect(find.textContaining('Queue address active-1'), findsOneWidget);
      expect(find.text('Move to Picked up'), findsOneWidget);
      expect(harness.queueQueried, isFalse);
    });

    testWidgets('approved + online: the queue is shown with the richer order card', (tester) async {
      final harness = _Harness();
      await harness.pump(tester, ApprovalStatus.approved);

      expect(find.byKey(const ValueKey('driver_offline')), findsNothing);
      expect(harness.queueQueried, isTrue);
      expect(find.text('Queue address queued-1'), findsOneWidget);
      expect(find.text('To collect (cash)'), findsOneWidget);
    });
  });
}
