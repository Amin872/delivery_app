import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:delivery_app/core/errors/app_exception.dart';
import 'package:delivery_app/core/location/distance_estimator.dart';
import 'package:delivery_app/core/location/navigation_launcher.dart' show UrlLaunchFn;
import 'package:url_launcher/url_launcher.dart' show LaunchMode;
import 'package:delivery_app/core/providers/formatters_provider.dart';
import 'package:delivery_app/features/customer/screens/customer_home_screen.dart'
    show allCitiesProvider;
import 'package:delivery_app/features/driver/widgets/driver_active_delivery_card.dart';
import 'package:delivery_app/features/driver/widgets/driver_available_order_card.dart';
import 'package:delivery_app/l10n/app_localizations.dart';
import 'package:delivery_app/features/driver/widgets/driver_order_summary.dart';
import 'package:delivery_app/models/city.dart';
import 'package:delivery_app/models/coordinates.dart';
import 'package:delivery_app/models/driver.dart';
import 'package:delivery_app/models/order.dart';

final _currency = NumberFormat.currency(locale: 'en', name: 'SYP');

/// An order as createOrder writes it (Phase 21): vendor snapshot + price
/// breakdown.
DeliveryOrder _fullOrder({OrderStatus status = OrderStatus.readyForPickup}) => DeliveryOrder(
      id: 'order-1',
      customerId: 'customer-1',
      vendorId: 'vendor-1',
      items: const [
        OrderItem(menuItemId: 'falafel', name: 'Falafel wrap', quantity: 2, unitPrice: 2000),
        OrderItem(menuItemId: 'hummus', name: 'Hummus', quantity: 1, unitPrice: 3000),
      ],
      status: status,
      subtotal: 7000,
      deliveryFee: 1500,
      total: 8500,
      deliveryAddress: 'Mezzeh, Building 4',
      cityId: 'damascus',
      deliveryInstructions: 'Ring twice',
      driverNote: 'Leave at door',
      vendorName: 'Abu Kamal Falafel',
      pickupAddress: 'Hamra St, Damascus',
      createdAt: DateTime(2026, 9, 22),
    );

/// An order placed before Phase 21: no snapshot, no breakdown, no city.
DeliveryOrder _legacyOrder({OrderStatus status = OrderStatus.readyForPickup}) => DeliveryOrder(
      id: 'legacy-1',
      customerId: 'customer-1',
      vendorId: 'vendor-1',
      items: const [OrderItem(menuItemId: 'x', name: 'Old item', quantity: 3, unitPrice: 1000)],
      status: status,
      total: 3000,
      deliveryAddress: 'Old address',
      createdAt: DateTime(2026, 1, 1),
    );

Future<void> _pump(WidgetTester tester, Widget child, {bool settle = true}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currencyFormatProvider.overrideWithValue(_currency),
        allCitiesProvider.overrideWith(
          (ref) => Stream.value(const [
            CityOption(id: 'damascus', nameEn: 'Damascus', nameAr: 'دمشق', enabled: true, order: 0),
          ]),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
  settle ? await tester.pumpAndSettle() : await tester.pump();
}

void main() {
  group('DriverAvailableOrderCard', () {
    testWidgets('shows store, pickup, drop-off with city, item count and cash total',
        (tester) async {
      await _pump(
        tester,
        DriverAvailableOrderCard(order: _fullOrder(), isAccepting: false, onAccept: () {}),
      );

      expect(find.text('Abu Kamal Falafel'), findsOneWidget);
      expect(find.text('Hamra St, Damascus'), findsOneWidget);
      expect(find.text('Mezzeh, Building 4 · Damascus'), findsOneWidget);
      expect(find.text('3 items'), findsOneWidget); // 2 + 1
      expect(find.text('To collect (cash)'), findsOneWidget);
      expect(find.text(_currency.format(8500)), findsOneWidget);
    });

    testWidgets('a legacy order hides the missing rows but still renders', (tester) async {
      await _pump(
        tester,
        DriverAvailableOrderCard(order: _legacyOrder(), isAccepting: false, onAccept: () {}),
      );

      expect(find.text('Old address'), findsOneWidget);
      expect(find.text('3 items'), findsOneWidget);
      expect(find.text(_currency.format(3000)), findsOneWidget);
      expect(find.byTooltip('Store'), findsNothing);
      expect(find.byTooltip('Pickup location'), findsNothing);
    });

    testWidgets('Accept calls back; while accepting it is disabled', (tester) async {
      var accepted = 0;
      await _pump(
        tester,
        DriverAvailableOrderCard(order: _fullOrder(), isAccepting: false, onAccept: () => accepted++),
      );
      await tester.tap(find.text('Accept'));
      expect(accepted, 1);

      await _pump(
        tester,
        DriverAvailableOrderCard(order: _fullOrder(), isAccepting: true, onAccept: () => accepted++),
        settle: false, // the busy spinner animates forever
      );
      expect(find.text('Accept'), findsNothing); // spinner instead
      await tester.tap(find.byType(FilledButton));
      expect(accepted, 1);
    });
  });

  group('DriverActiveDeliveryCard', () {
    Widget card({
      required DeliveryOrder order,
      OrderStatus? next = OrderStatus.pickedUp,
      bool needsProof = false,
      bool canAdvance = true,
      VoidCallback? onAdvance,
      ValueChanged<File>? onProofPicked,
      Coordinates? driverPosition,
      ValueChanged<Coordinates>? onNavigate,
      Future<String> Function()? fetchCustomerPhone,
      UrlLaunchFn? launch,
    }) =>
        DriverActiveDeliveryCard(
          fetchCustomerPhone: fetchCustomerPhone,
          launchUrlForCall: launch ?? (uri, {mode = LaunchMode.platformDefault}) async => true,
          order: order,
          nextStatus: next,
          needsProof: needsProof,
          canAdvance: canAdvance,
          advancing: false,
          proofImage: null,
          onProofPicked: onProofPicked ?? (_) {},
          onAdvance: onAdvance ?? () {},
          driverPosition: driverPosition,
          onNavigate: onNavigate ?? (_) {},
        );

    DeliveryOrder pinned(OrderStatus status, {bool pickupPin = true, bool dropOffPin = true}) =>
        DeliveryOrder(
          id: 'pinned-1',
          customerId: 'customer-1',
          vendorId: 'vendor-1',
          items: const [],
          status: status,
          total: 100,
          deliveryAddress: 'Drop street',
          createdAt: DateTime(2026, 9, 22),
          pickupLatitude: pickupPin ? 33.51 : null,
          pickupLongitude: pickupPin ? 36.27 : null,
          deliveryLatitude: dropOffPin ? 33.50 : null,
          deliveryLongitude: dropOffPin ? 36.25 : null,
        );

    const driverNearby = Coordinates(latitude: 33.52, longitude: 36.29);

    group('navigation (Phase 26)', () {
      testWidgets('before pickup: "Navigate to pickup" with the pickup pin', (tester) async {
        Coordinates? target;
        await _pump(
          tester,
          card(order: pinned(OrderStatus.driverAssigned), onNavigate: (c) => target = c),
        );

        expect(find.byKey(const ValueKey('navigate_to_drop_off')), findsNothing);
        await tester.tap(find.text('Navigate to pickup'));
        expect(target, const Coordinates(latitude: 33.51, longitude: 36.27));
      });

      testWidgets('before pickup with no pickup pin: no navigate button', (tester) async {
        await _pump(tester, card(order: pinned(OrderStatus.driverAssigned, pickupPin: false)));

        expect(find.byKey(const ValueKey('navigate_to_pickup')), findsNothing);
        expect(find.byKey(const ValueKey('navigate_to_drop_off')), findsNothing);
      });

      for (final status in [OrderStatus.pickedUp, OrderStatus.delivering]) {
        testWidgets('${status.name}: "Navigate to drop-off" with the drop-off pin', (tester) async {
          Coordinates? target;
          await _pump(tester, card(order: pinned(status), onNavigate: (c) => target = c));

          expect(find.byKey(const ValueKey('navigate_to_pickup')), findsNothing);
          await tester.tap(find.text('Navigate to drop-off'));
          expect(target, const Coordinates(latitude: 33.50, longitude: 36.25));
        });
      }

      testWidgets('legacy order with no drop-off pin: no navigate button', (tester) async {
        await _pump(tester, card(order: pinned(OrderStatus.delivering, dropOffPin: false)));

        expect(find.byKey(const ValueKey('navigate_to_drop_off')), findsNothing);
      });
    });

    group('call customer (Phase 27)', () {
      for (final status in [OrderStatus.driverAssigned, OrderStatus.pickedUp, OrderStatus.delivering]) {
        testWidgets('${status.name}: tapping asks the resolver, then dials', (tester) async {
          var fetches = 0;
          final dialed = <Uri>[];
          await _pump(
            tester,
            card(
              order: pinned(status),
              fetchCustomerPhone: () async {
                fetches++;
                return '+963 900 000 001';
              },
              launch: (uri, {mode = LaunchMode.platformDefault}) async {
                dialed.add(uri);
                return true;
              },
            ),
          );

          await tester.tap(find.text('Call customer'));
          await tester.pumpAndSettle();

          expect(fetches, 1);
          expect(dialed.single, Uri(scheme: 'tel', path: '+963 900 000 001'));
        });
      }

      for (final status in [OrderStatus.delivered, OrderStatus.cancelled]) {
        testWidgets('hidden once the order is ${status.name}', (tester) async {
          await _pump(
            tester,
            card(order: pinned(status), next: null, fetchCustomerPhone: () async => '1'),
          );

          expect(find.text('Call customer'), findsNothing);
        });
      }

      testWidgets('no phone on file: localized message', (tester) async {
        await _pump(
          tester,
          card(
            order: pinned(OrderStatus.delivering),
            fetchCustomerPhone: () async => throw const AppException('phone-unavailable'),
          ),
        );

        await tester.tap(find.text('Call customer'));
        await tester.pumpAndSettle();

        expect(find.text('No phone number is available for this person.'), findsOneWidget);
      });

      testWidgets('dialer failure: localized message', (tester) async {
        await _pump(
          tester,
          card(
            order: pinned(OrderStatus.delivering),
            fetchCustomerPhone: () async => '123',
            launch: (uri, {mode = LaunchMode.platformDefault}) async => false,
          ),
        );

        await tester.tap(find.text('Call customer'));
        await tester.pumpAndSettle();

        expect(find.text("Couldn't start the call."), findsOneWidget);
      });
    });

    group('approximate distance/ETA (Phase 26)', () {
      testWidgets('before pickup: estimate to the pickup, labeled approximate', (tester) async {
        await _pump(
          tester,
          card(order: pinned(OrderStatus.driverAssigned), driverPosition: driverNearby),
        );

        final expected = estimateTrip(driverNearby, const Coordinates(latitude: 33.51, longitude: 36.27))!;
        expect(
          find.text('≈ ${expected.distanceKmLabel} km to pickup · estimated ${expected.etaMinutes} min'),
          findsOneWidget,
        );
      });

      testWidgets('after pickup: the estimate switches to the drop-off', (tester) async {
        await _pump(tester, card(order: pinned(OrderStatus.pickedUp), driverPosition: driverNearby));

        final expected = estimateTrip(driverNearby, const Coordinates(latitude: 33.50, longitude: 36.25))!;
        expect(
          find.text('≈ ${expected.distanceKmLabel} km to drop-off · estimated ${expected.etaMinutes} min'),
          findsOneWidget,
        );
        expect(find.textContaining('to pickup'), findsNothing);
      });

      testWidgets('hidden without a driver position', (tester) async {
        await _pump(tester, card(order: pinned(OrderStatus.delivering)));

        expect(find.byKey(const ValueKey('driver_trip_estimate')), findsNothing);
      });

      testWidgets('hidden without a target pin', (tester) async {
        await _pump(
          tester,
          card(order: pinned(OrderStatus.driverAssigned, pickupPin: false), driverPosition: driverNearby),
        );

        expect(find.byKey(const ValueKey('driver_trip_estimate')), findsNothing);
      });
    });

    testWidgets('shows store, pickup, drop-off, notes, items and the price breakdown',
        (tester) async {
      await _pump(tester, card(order: _fullOrder(status: OrderStatus.driverAssigned)));

      expect(find.text('Driver on the way to pick up'), findsOneWidget);
      expect(find.text('Abu Kamal Falafel'), findsOneWidget);
      expect(find.text('Hamra St, Damascus'), findsOneWidget);
      expect(find.text('Mezzeh, Building 4 · Damascus'), findsOneWidget);
      expect(find.text('Ring twice'), findsOneWidget);
      expect(find.text('Leave at door'), findsOneWidget);
      expect(find.text('Falafel wrap'), findsOneWidget);
      expect(find.text('2 × ${_currency.format(2000)}'), findsOneWidget);
      expect(find.text(_currency.format(4000)), findsOneWidget); // line total
      expect(find.text('Subtotal'), findsOneWidget);
      expect(find.text(_currency.format(7000)), findsOneWidget);
      expect(find.text(_currency.format(1500)), findsOneWidget);
      expect(find.text('To collect (cash)'), findsOneWidget);
      expect(find.text(_currency.format(8500)), findsOneWidget);
    });

    testWidgets('a legacy order falls back to subtotal = total and a 0 fee', (tester) async {
      await _pump(tester, card(order: _legacyOrder(status: OrderStatus.driverAssigned)));

      expect(find.text('Old address'), findsOneWidget);
      // Line total, subtotal and total are all 3000.
      expect(find.text(_currency.format(3000)), findsNWidgets(3));
      expect(find.text(_currency.format(0)), findsOneWidget);
      expect(find.byTooltip('Store'), findsNothing);
    });

    testWidgets('the advance button calls back', (tester) async {
      var advanced = 0;
      await _pump(
        tester,
        card(order: _fullOrder(status: OrderStatus.driverAssigned), onAdvance: () => advanced++),
      );

      await tester.tap(find.text('Move to Picked up'));
      expect(advanced, 1);
    });

    testWidgets('proof step: photo picker shown, advance disabled until a photo exists',
        (tester) async {
      var advanced = 0;
      await _pump(
        tester,
        card(
          order: _fullOrder(status: OrderStatus.delivering),
          next: OrderStatus.delivered,
          needsProof: true,
          canAdvance: false,
          onAdvance: () => advanced++,
        ),
      );

      expect(find.byIcon(Icons.add_a_photo_outlined), findsOneWidget);
      await tester.tap(find.text('Move to Delivered'));
      expect(advanced, 0);
    });

    testWidgets('no action button once there is no next step', (tester) async {
      await _pump(tester, card(order: _fullOrder(status: OrderStatus.delivered), next: null));

      expect(find.textContaining('Move to'), findsNothing);
    });
  });

  group('driverNextStop / recentDriverPosition (Phase 26)', () {
    DeliveryOrder order(OrderStatus status) => DeliveryOrder(
          id: 'o',
          customerId: 'c',
          vendorId: 'v',
          items: const [],
          status: status,
          total: 1,
          deliveryAddress: 'a',
          createdAt: DateTime(2026),
          pickupLatitude: 1,
          pickupLongitude: 2,
          deliveryLatitude: 3,
          deliveryLongitude: 4,
        );

    test('heads to the pickup until picked up, then to the drop-off', () {
      final assigned = driverNextStop(order(OrderStatus.driverAssigned))!;
      expect(assigned.kind, DriverStopKind.pickup);
      expect(assigned.coordinates, const Coordinates(latitude: 1, longitude: 2));

      for (final status in [OrderStatus.pickedUp, OrderStatus.delivering]) {
        final stop = driverNextStop(order(status))!;
        expect(stop.kind, DriverStopKind.dropOff);
        expect(stop.coordinates, const Coordinates(latitude: 3, longitude: 4));
      }
    });

    test('has no next stop outside the driver legs', () {
      for (final status in [
        OrderStatus.pending,
        OrderStatus.readyForPickup,
        OrderStatus.delivered,
        OrderStatus.cancelled,
      ]) {
        expect(driverNextStop(order(status)), isNull, reason: status.name);
      }
    });

    test('uses the last published position only while it is recent', () {
      final now = DateTime(2026, 9, 22, 12);
      DriverLocation at(Duration age) =>
          DriverLocation(latitude: 33.5, longitude: 36.3, updatedAt: now.subtract(age));

      expect(recentDriverPosition(at(const Duration(minutes: 1)), now),
          const Coordinates(latitude: 33.5, longitude: 36.3));
      expect(recentDriverPosition(at(driverPositionMaxAge), now), isNotNull);
      expect(recentDriverPosition(at(driverPositionMaxAge + const Duration(seconds: 1)), now), isNull);
      expect(recentDriverPosition(null, now), isNull);
    });
  });
}
