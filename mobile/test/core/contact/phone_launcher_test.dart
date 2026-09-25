import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:delivery_app/core/contact/phone_launcher.dart';
import 'package:delivery_app/core/errors/app_exception.dart';
import 'package:delivery_app/l10n/app_localizations.dart';
import 'package:delivery_app/models/order.dart';

DeliveryOrder _order(OrderStatus status, {String? driverId = 'driver-1'}) => DeliveryOrder(
      id: 'o1',
      customerId: 'customer-1',
      vendorId: 'vendor-1',
      driverId: driverId,
      items: const [],
      status: status,
      total: 1,
      deliveryAddress: 'a',
      createdAt: DateTime(2026),
    );

/// Records launches; returns [result] (or throws when [throws]).
class _FakeLauncher {
  _FakeLauncher({this.result = true, this.throws = false});

  final bool result;
  final bool throws;
  final launched = <Uri>[];
  final modes = <LaunchMode>[];

  Future<bool> call(Uri uri, {LaunchMode mode = LaunchMode.platformDefault}) async {
    launched.add(uri);
    modes.add(mode);
    if (throws) throw Exception('no dialer');
    return result;
  }
}

Future<void> _pumpAction(
  WidgetTester tester, {
  required Future<String> Function() fetchPhone,
  required _FakeLauncher launcher,
}) {
  return tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: PhoneCallAction(
            fetchPhone: fetchPhone,
            launch: launcher.call,
            builder: (context, onPressed, busy) =>
                TextButton(onPressed: onPressed, child: Text(busy ? 'busy' : 'Call')),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('launchPhoneCall', () {
    test('dials a tel: link in an external app', () async {
      final launcher = _FakeLauncher();

      expect(await launchPhoneCall('+963 900 000 001', launch: launcher.call), isTrue);
      expect(launcher.launched.single, Uri(scheme: 'tel', path: '+963 900 000 001'));
      expect(launcher.modes.single, LaunchMode.externalApplication);
    });

    test('returns false when nothing can dial, and never throws', () async {
      expect(await launchPhoneCall('123', launch: _FakeLauncher(result: false).call), isFalse);
      expect(await launchPhoneCall('123', launch: _FakeLauncher(throws: true).call), isFalse);
    });
  });

  group('call-button status windows (mirror of functions/src/contacts.ts)', () {
    test('customer -> driver: assigned driver in driverAssigned/pickedUp/delivering', () {
      final allowed = OrderStatus.values.where((s) => customerCanCallDriver(_order(s))).toSet();
      expect(allowed, {OrderStatus.driverAssigned, OrderStatus.pickedUp, OrderStatus.delivering});
      expect(customerCanCallDriver(_order(OrderStatus.delivering, driverId: null)), isFalse);
    });

    test('driver -> customer: driverAssigned/pickedUp/delivering', () {
      final allowed = OrderStatus.values.where((s) => driverCanCallCustomer(_order(s))).toSet();
      expect(allowed, {OrderStatus.driverAssigned, OrderStatus.pickedUp, OrderStatus.delivering});
    });

    test('vendor -> customer: pending through driverAssigned', () {
      final allowed = OrderStatus.values.where((s) => vendorCanCallCustomer(_order(s))).toSet();
      expect(allowed, {
        OrderStatus.pending,
        OrderStatus.accepted,
        OrderStatus.preparing,
        OrderStatus.readyForPickup,
        OrderStatus.driverAssigned,
      });
    });

    test('vendor -> driver: assigned driver in driverAssigned/pickedUp', () {
      final allowed = OrderStatus.values.where((s) => vendorCanCallDriver(_order(s))).toSet();
      expect(allowed, {OrderStatus.driverAssigned, OrderStatus.pickedUp});
      expect(vendorCanCallDriver(_order(OrderStatus.driverAssigned, driverId: null)), isFalse);
    });
  });

  group('PhoneCallAction', () {
    testWidgets('fetches the number, then dials it', (tester) async {
      final launcher = _FakeLauncher();
      await _pumpAction(tester, fetchPhone: () async => '+963 900 000 001', launcher: launcher);

      await tester.tap(find.text('Call'));
      await tester.pumpAndSettle();

      expect(launcher.launched.single, Uri(scheme: 'tel', path: '+963 900 000 001'));
    });

    testWidgets('busy while looking up: a second tap does nothing', (tester) async {
      final pending = Completer<String>();
      var fetches = 0;
      final launcher = _FakeLauncher();
      await _pumpAction(
        tester,
        fetchPhone: () {
          fetches++;
          return pending.future;
        },
        launcher: launcher,
      );

      await tester.tap(find.text('Call'));
      await tester.pump();
      expect(find.text('busy'), findsOneWidget);
      await tester.tap(find.text('busy'));
      await tester.pump();
      expect(fetches, 1);

      pending.complete('123');
      await tester.pumpAndSettle();
      expect(launcher.launched, hasLength(1));
      expect(find.text('Call'), findsOneWidget);
    });

    testWidgets('no phone on file: localized "unavailable" message, no dialing', (tester) async {
      final launcher = _FakeLauncher();
      await _pumpAction(
        tester,
        fetchPhone: () async => throw const AppException('phone-unavailable'),
        launcher: launcher,
      );

      await tester.tap(find.text('Call'));
      await tester.pumpAndSettle();

      expect(find.text('No phone number is available for this person.'), findsOneWidget);
      expect(launcher.launched, isEmpty);
    });

    testWidgets('refused by the server: localized "can\'t contact" message', (tester) async {
      await _pumpAction(
        tester,
        fetchPhone: () async => throw const AppException('contact-not-authorized'),
        launcher: _FakeLauncher(),
      );

      await tester.tap(find.text('Call'));
      await tester.pumpAndSettle();

      expect(find.text("You can't contact this person for this order right now."), findsOneWidget);
    });

    testWidgets('dialer failure: "couldn\'t start the call"', (tester) async {
      await _pumpAction(tester, fetchPhone: () async => '123', launcher: _FakeLauncher(result: false));

      await tester.tap(find.text('Call'));
      await tester.pumpAndSettle();

      expect(find.text("Couldn't start the call."), findsOneWidget);
    });
  });
}
