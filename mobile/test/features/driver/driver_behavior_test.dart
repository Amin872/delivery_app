import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:delivery_app/features/driver/screens/driver_home_screen.dart';
import 'package:delivery_app/l10n/app_localizations.dart';
import 'package:delivery_app/models/order.dart';

import '../../support/real_theme_harness.dart';
import 'driver_test_support.dart';

final _l10n = lookupAppLocalizations(const Locale('en'));

Future<void> _pump(WidgetTester tester, List<Override> overrides) async {
  await pumpWithRealTheme(tester, const DriverHomeScreen(), locale: const Locale('en'), overrides: overrides);
  await tester.pumpAndSettle();
}

Switch _switch(WidgetTester tester) => tester.widget<Switch>(find.byKey(const ValueKey('driver_available_switch')));

Future<void> _tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await revealInHome(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void _expectErrorSnackBar(String message) {
  expect(find.widgetWithText(SnackBar, message), findsOneWidget);
  expect(find.textContaining('raw backend detail'), findsNothing);
}

DeliveryOrder _delivering(String id) => driverOrder(id, OrderStatus.delivering, driverId: driverId);

void main() {
  group('availability switch', () {
    testWidgets('success: awaited, disabled while saving, no error', (tester) async {
      final firestore = ControlledFirestore()..gate = Completer<void>();
      await _pump(tester, driverHomeOverrides(firestore: firestore));
      expect(_switch(tester).value, isTrue);

      await tester.tap(find.byKey(const ValueKey('driver_available_switch')));
      await tester.pump();
      expect(firestore.availabilityWrites, [false]);
      // Shows the new value and can't be toggled again mid-write.
      expect(_switch(tester).value, isFalse);
      expect(_switch(tester).onChanged, isNull);

      firestore.gate.complete();
      await tester.pumpAndSettle();
      expect(_switch(tester).onChanged, isNotNull);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('failure: switch restored and a localized snackbar shown', (tester) async {
      final firestore = ControlledFirestore(fail: true);
      await _pump(tester, driverHomeOverrides(firestore: firestore));

      await tester.tap(find.byKey(const ValueKey('driver_available_switch')));
      await tester.pumpAndSettle();
      expect(firestore.availabilityWrites, [false]);
      expect(_switch(tester).value, isTrue);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('raw backend detail'), findsNothing);
    });
  });

  group('proof picker', () {
    List<Override> deliveringWith(FakeProofPicker picker, {RecordingStorage? storage, RecordingFunctions? functions}) =>
        driverHomeOverrides(
          activeOrders: Stream.value(_delivering('order-a')),
          picker: picker,
          storage: storage,
          functions: functions,
        );

    testWidgets('camera and gallery each ask for their own source', (tester) async {
      final picker = FakeProofPicker(result: File('a.jpg'));
      await _pump(tester, deliveringWith(picker));

      await _tapKey(tester, 'driver_proof_camera');
      await _tapKey(tester, 'driver_proof_gallery');
      expect(picker.sources, [ImageSource.camera, ImageSource.gallery]);
    });

    testWidgets('permission denied: localized permission message', (tester) async {
      final picker = FakeProofPicker(error: PlatformException(code: 'camera_access_denied', message: 'raw backend detail'));
      await _pump(tester, deliveringWith(picker));

      await _tapKey(tester, 'driver_proof_camera');
      _expectErrorSnackBar(_l10n.proofPermissionDeniedMessage);
    });

    testWidgets('no camera: suggests the gallery', (tester) async {
      final picker = FakeProofPicker(error: PlatformException(code: 'no_available_camera'));
      await _pump(tester, deliveringWith(picker));

      await _tapKey(tester, 'driver_proof_camera');
      _expectErrorSnackBar(_l10n.proofCameraUnavailableMessage);
    });

    testWidgets('unexpected picker error: generic localized message', (tester) async {
      final picker = FakeProofPicker(error: StateError('raw backend detail'));
      await _pump(tester, deliveringWith(picker));

      await _tapKey(tester, 'driver_proof_gallery');
      _expectErrorSnackBar(_l10n.proofPickFailedMessage);
    });

    testWidgets('advance stays disabled until a photo is picked', (tester) async {
      await _pump(tester, deliveringWith(FakeProofPicker(result: File('a.jpg'))));
      final advance = find.byKey(const ValueKey('driver_advance_button'));
      await revealInHome(tester, advance);
      expect(tester.widget<FilledButton>(advance).onPressed, isNull);

      await _tapKey(tester, 'driver_proof_gallery');
      expect(tester.widget<FilledButton>(advance).onPressed, isNotNull);
    });
  });

  group('final Delivered step', () {
    testWidgets('asks for confirmation; Cancel does not advance or upload', (tester) async {
      final storage = RecordingStorage();
      final functions = RecordingFunctions();
      await _pump(
        tester,
        driverHomeOverrides(
          activeOrders: Stream.value(_delivering('order-a')),
          picker: FakeProofPicker(result: File('a.jpg')),
          storage: storage,
          functions: functions,
        ),
      );
      await _tapKey(tester, 'driver_proof_gallery');
      await _tapKey(tester, 'driver_advance_button');

      expect(find.text(_l10n.confirmDeliveredTitle), findsOneWidget);
      expect(find.text(_l10n.confirmDeliveredMessage), findsOneWidget);
      await tester.tap(find.text(_l10n.cancelButton));
      await tester.pumpAndSettle();

      expect(storage.uploads, isEmpty);
      expect(functions.advanced, isEmpty);
    });

    testWidgets('Confirm uploads the proof for this order, then advances it', (tester) async {
      final storage = RecordingStorage();
      final functions = RecordingFunctions();
      await _pump(
        tester,
        driverHomeOverrides(
          activeOrders: Stream.value(_delivering('order-a')),
          picker: FakeProofPicker(result: File('a.jpg')),
          storage: storage,
          functions: functions,
        ),
      );
      await _tapKey(tester, 'driver_proof_gallery');
      await _tapKey(tester, 'driver_advance_button');
      await tester.tap(find.text(_l10n.confirmButton));
      await tester.pumpAndSettle();

      expect(storage.uploads, [(orderId: 'order-a', path: 'a.jpg')]);
      expect(functions.advanced, [
        (orderId: 'order-a', proofImageUrl: 'https://example.test/orderProofs/order-a/proof.jpg'),
      ]);
    });

    testWidgets('earlier steps advance without a confirmation', (tester) async {
      final functions = RecordingFunctions();
      await _pump(
        tester,
        driverHomeOverrides(
          activeOrders: Stream.value(driverOrder('order-a', OrderStatus.driverAssigned, driverId: driverId)),
          functions: functions,
        ),
      );
      await _tapKey(tester, 'driver_advance_button');

      expect(find.text(_l10n.confirmDeliveredTitle), findsNothing);
      expect(functions.advanced, [(orderId: 'order-a', proofImageUrl: null)]);
    });
  });

  group('proof belongs to one order', () {
    testWidgets('a new active order clears the old photo; it is never uploaded for it', (tester) async {
      final orders = StreamController<DeliveryOrder?>();
      addTearDown(orders.close);
      final storage = RecordingStorage();
      final functions = RecordingFunctions();
      final picker = FakeProofPicker(result: File('for-a.jpg'));
      await _pump(
        tester,
        driverHomeOverrides(activeOrders: orders.stream, picker: picker, storage: storage, functions: functions),
      );
      orders.add(_delivering('order-a'));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'driver_proof_gallery');
      final advance = find.byKey(const ValueKey('driver_advance_button'));
      expect(tester.widget<FilledButton>(advance).onPressed, isNotNull);

      // The active delivery becomes a different order (e.g. reassigned).
      orders.add(_delivering('order-b'));
      await tester.pumpAndSettle();
      await revealInHome(tester, advance);
      // The photo taken for order-a is gone: order-b needs its own.
      expect(tester.widget<FilledButton>(advance).onPressed, isNull);
      expect(storage.uploads, isEmpty);

      picker.result = File('for-b.jpg');
      await _tapKey(tester, 'driver_proof_gallery');
      await _tapKey(tester, 'driver_advance_button');
      await tester.tap(find.text(_l10n.confirmButton));
      await tester.pumpAndSettle();

      expect(storage.uploads, [(orderId: 'order-b', path: 'for-b.jpg')]);
      expect(functions.advanced.single.orderId, 'order-b');
    });
  });
}
