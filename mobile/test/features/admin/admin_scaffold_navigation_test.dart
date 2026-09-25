import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:delivery_app/features/admin/screens/admin_dashboard_screen.dart';
import 'package:delivery_app/features/admin/screens/admin_driver_detail_screen.dart';
import 'package:delivery_app/features/admin/screens/admin_drivers_screen.dart';
import 'package:delivery_app/features/admin/screens/admin_orders_screen.dart';
import 'package:delivery_app/features/admin/screens/admin_promotions_screen.dart';
import 'package:delivery_app/features/admin/screens/admin_vendors_screen.dart';
import 'package:delivery_app/features/admin/widgets/admin_scaffold.dart';

import 'admin_test_harness.dart';

/// Every AdminScaffold in the tree, including routes covered by the one on
/// top — i.e. how many admin destination routes are stacked.
int _stackedAdminScaffolds(WidgetTester tester) =>
    find.byType(AdminScaffold, skipOffstage: false).evaluate().length;

AdminDestination _visibleDestination(WidgetTester tester) =>
    tester.widget<AdminScaffold>(find.byType(AdminScaffold)).selected;

/// Opens the drawer (phone width) and picks [destination].
Future<void> _go(WidgetTester tester, AdminDestination destination) async {
  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
  final label = destination.label(adminTestL10n);
  await tester.tap(find.descendant(of: find.byType(Drawer), matching: find.text(label)));
  await tester.pumpAndSettle();
}

Future<FakeFirebaseFirestore> _db() async {
  final db = FakeFirebaseFirestore();
  await seedDriver(db, 'd1', 'Driver One', approval: 'approved');
  return db;
}

void main() {
  testWidgets('Orders and Promotions render inside AdminScaffold with their own destination', (tester) async {
    await pumpAdminScreen(tester, const AdminDashboardScreen(), await _db());

    await _go(tester, AdminDestination.orders);
    expect(find.byType(AdminOrdersScreen), findsOneWidget);
    expect(_visibleDestination(tester), AdminDestination.orders);

    await _go(tester, AdminDestination.promotions);
    expect(find.byType(AdminPromotionsScreen), findsOneWidget);
    expect(_visibleDestination(tester), AdminDestination.promotions);
    // The add action survived the move into the shell.
    expect(find.byTooltip(adminTestL10n.addPromotionTitle), findsOneWidget);
  });

  testWidgets('hopping between destinations never stacks more than dashboard + one', (tester) async {
    await pumpAdminScreen(tester, const AdminDashboardScreen(), await _db());
    expect(_stackedAdminScaffolds(tester), 1);

    for (final destination in [
      AdminDestination.orders,
      AdminDestination.vendors,
      AdminDestination.drivers,
      AdminDestination.promotions,
      AdminDestination.users,
      AdminDestination.orders,
    ]) {
      await _go(tester, destination);
      expect(_visibleDestination(tester), destination);
      expect(_stackedAdminScaffolds(tester), 2, reason: destination.name);
    }

    // System back from any destination lands on the dashboard...
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(AdminDashboardScreen), findsOneWidget);
    expect(_stackedAdminScaffolds(tester), 1);

    // ...and so does picking Dashboard in the nav.
    await _go(tester, AdminDestination.vendors);
    expect(find.byType(AdminVendorsScreen), findsOneWidget);
    await _go(tester, AdminDestination.dashboard);
    expect(_visibleDestination(tester), AdminDestination.dashboard);
    expect(_stackedAdminScaffolds(tester), 1);
  });

  testWidgets('a detail screen pushed from a destination still goes back to that destination', (tester) async {
    await pumpAdminScreen(tester, const AdminDashboardScreen(), await _db());
    await _go(tester, AdminDestination.drivers);

    await tester.tap(find.text('Driver One'));
    await tester.pumpAndSettle();
    expect(find.byType(AdminDriverDetailScreen), findsOneWidget);

    await tester.pageBack(); // the detail screen has its own back arrow
    await tester.pumpAndSettle();
    expect(find.byType(AdminDriverDetailScreen), findsNothing);
    expect(find.byType(AdminDriversScreen), findsOneWidget);
    expect(_stackedAdminScaffolds(tester), 2);
  });
}
