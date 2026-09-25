import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:delivery_app/core/l10n/enum_labels.dart';
import 'package:delivery_app/features/admin/screens/admin_order_detail_screen.dart';
import 'package:delivery_app/features/admin/screens/admin_orders_screen.dart';
import 'package:delivery_app/features/admin/widgets/admin_scaffold.dart';
import 'package:delivery_app/models/order.dart';

import 'admin_test_harness.dart';

/// One order per status, ids `o-<status>`, newest last.
Future<FakeFirebaseFirestore> _db() async {
  final db = FakeFirebaseFirestore();
  for (final (i, status) in OrderStatus.values.indexed) {
    await db.collection('orders').doc('o-${status.name}').set(DeliveryOrder(
          id: 'o-${status.name}',
          customerId: 'customer-1',
          vendorId: 'vendor-1',
          items: const [],
          status: status,
          total: 1000,
          deliveryAddress: 'Mezzeh',
          createdAt: DateTime(2026, 9, 1 + i),
        ).toMap());
  }
  return db;
}

Finder _row(String id) => find.text(adminTestL10n.orderLabel(id));

/// Selects the filter chip labelled [label] (scrolling the chip row to it).
Future<void> _selectChip(WidgetTester tester, String label, {bool backwards = false}) async {
  final chip = find.widgetWithText(ChoiceChip, label);
  // The chip row is a lazy horizontal list: build the chip, then bring
  // it fully on screen so the tap lands.
  final chipRow = find.ancestor(of: find.byType(ChoiceChip).first, matching: find.byType(Scrollable)).first;
  await tester.scrollUntilVisible(chip, backwards ? -100 : 100, scrollable: chipRow);
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders inside the shared AdminScaffold as the Orders destination', (tester) async {
    await pumpAdminScreen(tester, const AdminOrdersScreen(), await _db());

    final scaffold = tester.widget<AdminScaffold>(find.byType(AdminScaffold));
    expect(scaffold.selected, AdminDestination.orders);
    expect(find.text(adminTestL10n.adminOrdersTitle), findsWidgets);
  });

  testWidgets('"All" lists every order, each with its localized status', (tester) async {
    await pumpAdminScreen(tester, const AdminOrdersScreen(), await _db(), size: const Size(400, 2400));

    final context = tester.element(find.byType(AdminOrdersScreen));
    for (final status in OrderStatus.values) {
      expect(_row('o-${status.name}'), findsOneWidget, reason: status.name);
      expect(find.textContaining(orderStatusLabel(context, status)), findsWidgets, reason: status.name);
    }
  });

  testWidgets('each status chip shows only that status, and All restores the full list', (tester) async {
    await pumpAdminScreen(tester, const AdminOrdersScreen(), await _db(), size: const Size(400, 2400));
    final context = tester.element(find.byType(AdminOrdersScreen));

    for (final status in OrderStatus.values) {
      await _selectChip(tester, orderStatusLabel(context, status));
      for (final other in OrderStatus.values) {
        expect(_row('o-${other.name}'), other == status ? findsOneWidget : findsNothing,
            reason: 'filter ${status.name}, row ${other.name}');
      }
    }

    await _selectChip(tester, adminTestL10n.allStatusesLabel, backwards: true);
    expect(find.byType(ListTile), findsNWidgets(OrderStatus.values.length));
  });

  testWidgets('tapping an order opens its AdminOrderDetailScreen; back returns to the list', (tester) async {
    await pumpAdminScreen(tester, const AdminOrdersScreen(), await _db(), size: const Size(400, 2400));

    await tester.tap(_row('o-preparing'));
    await tester.pumpAndSettle();
    expect(tester.widget<AdminOrderDetailScreen>(find.byType(AdminOrderDetailScreen)).orderId, 'o-preparing');

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(AdminOrderDetailScreen), findsNothing);
    expect(find.byType(AdminOrdersScreen), findsOneWidget);
  });
}
