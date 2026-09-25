import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:delivery_app/features/customer/screens/customer_home_screen.dart'
    show firestoreServiceProvider;
import 'package:delivery_app/features/vendor/widgets/vendor_order_actions.dart';
import 'package:delivery_app/l10n/app_localizations.dart';
import 'package:delivery_app/models/order.dart';
import 'package:delivery_app/services/firestore_service.dart';

/// Records status writes and lets each test decide when (and how) they
/// complete.
class _RecordingFirestoreService extends FirestoreService {
  _RecordingFirestoreService() : super(firestore: FakeFirebaseFirestore());

  final updates = <OrderStatus>[];
  final pending = Completer<void>();

  @override
  Future<void> updateOrderStatus(String orderId, OrderStatus status) {
    updates.add(status);
    return pending.future;
  }
}

DeliveryOrder _order(OrderStatus status) => DeliveryOrder(
      id: 'order-1',
      customerId: 'customer-1',
      vendorId: 'vendor-1',
      items: const [],
      status: status,
      total: 10,
      deliveryAddress: 'addr',
      createdAt: DateTime(2026, 9, 22),
    );

Future<void> _pump(
  WidgetTester tester,
  _RecordingFirestoreService service,
  DeliveryOrder order, {
  bool compact = false,
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [firestoreServiceProvider.overrideWithValue(service)],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Center(child: VendorOrderActions(order: order, compact: compact))),
      ),
    ),
  );
}

void main() {
  group('vendor status machine', () {
    test('advances only through the vendor stages', () {
      expect(nextVendorStatus(OrderStatus.pending), OrderStatus.accepted);
      expect(nextVendorStatus(OrderStatus.accepted), OrderStatus.preparing);
      expect(nextVendorStatus(OrderStatus.preparing), OrderStatus.readyForPickup);
      for (final status in [
        OrderStatus.readyForPickup,
        OrderStatus.driverAssigned,
        OrderStatus.pickedUp,
        OrderStatus.delivering,
        OrderStatus.delivered,
        OrderStatus.cancelled,
      ]) {
        expect(nextVendorStatus(status), isNull, reason: status.name);
      }
    });

    test('allows cancelling only before readyForPickup', () {
      final cancellable = OrderStatus.values.where(vendorCanCancel).toSet();
      expect(cancellable, {OrderStatus.pending, OrderStatus.accepted, OrderStatus.preparing});
    });
  });

  for (final compact in [false, true]) {
    final layout = compact ? 'list row' : 'detail';

    testWidgets('($layout) a second tap while advancing sends no second write', (tester) async {
      final service = _RecordingFirestoreService();
      await _pump(tester, service, _order(OrderStatus.pending), compact: compact);

      await tester.tap(find.text('Move to Accepted'));
      await tester.pump();
      // Busy: the label is replaced by a spinner and both actions are disabled.
      expect(find.text('Move to Accepted'), findsNothing);
      await tester.tap(find.byTooltip('Cancel order').evaluate().isEmpty
          ? find.text('Cancel order')
          : find.byTooltip('Cancel order'));
      await tester.pump();
      expect(find.byType(AlertDialog), findsNothing);
      expect(service.updates, [OrderStatus.accepted]);

      service.pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('Move to Accepted'), findsOneWidget);
      expect(service.updates, [OrderStatus.accepted]);
    });

    testWidgets('($layout) a failed status update shows a localized error', (tester) async {
      final service = _RecordingFirestoreService();
      await _pump(tester, service, _order(OrderStatus.preparing), compact: compact);

      await tester.tap(find.text('Move to Ready for pickup'));
      await tester.pump();
      service.pending.completeError(Exception('permission-denied'));
      await tester.pumpAndSettle();

      expect(find.text("Couldn't update the order. Please try again."), findsOneWidget);
      // Re-enabled so the vendor can retry.
      expect(find.text('Move to Ready for pickup'), findsOneWidget);
    });
  }

  testWidgets('renders nothing once the order has no vendor action left', (tester) async {
    await _pump(tester, _RecordingFirestoreService(), _order(OrderStatus.readyForPickup));

    expect(find.textContaining('Move to'), findsNothing);
    expect(find.text('Cancel order'), findsNothing);
    expect(find.byTooltip('Cancel order'), findsNothing);
  });

  testWidgets('cancel still asks for confirmation first', (tester) async {
    await _pump(tester, _RecordingFirestoreService(), _order(OrderStatus.accepted));

    await tester.tap(find.text('Cancel order'));
    await tester.pumpAndSettle();

    expect(find.text("Cancel this order? This can't be undone."), findsOneWidget);
  });
}
