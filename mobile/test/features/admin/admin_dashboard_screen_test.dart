import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:delivery_app/features/admin/screens/admin_dashboard_screen.dart';
import 'package:delivery_app/features/admin/screens/admin_drivers_screen.dart';

import 'admin_test_harness.dart';

Finder _card() => find.byKey(const ValueKey('dashboard_pending_drivers'));

void main() {
  testWidgets('counts pending drivers (legacy docs without a status count as pending)', (tester) async {
    final db = FakeFirebaseFirestore();
    await seedDriver(db, 'd1', 'Pending One', approval: 'pending');
    await seedDriver(db, 'd2', 'Legacy Two'); // no approvalStatus
    await seedDriver(db, 'd3', 'Approved Three', approval: 'approved');
    await seedDriver(db, 'd4', 'Rejected Four', approval: 'rejected');

    await pumpAdminScreen(tester, const AdminDashboardScreen(), db);

    expect(find.descendant(of: _card(), matching: find.text(adminTestL10n.driverApprovalsTitle)), findsOneWidget);
    expect(
      find.descendant(of: _card(), matching: find.text(adminTestL10n.pendingDriverApprovalsCountLabel(2))),
      findsOneWidget,
    );
  });

  testWidgets('zero pending drivers shows 0, not a loading state', (tester) async {
    final db = FakeFirebaseFirestore();
    await seedDriver(db, 'd3', 'Approved Three', approval: 'approved');

    await pumpAdminScreen(tester, const AdminDashboardScreen(), db);

    expect(
      find.descendant(of: _card(), matching: find.text(adminTestL10n.pendingDriverApprovalsCountLabel(0))),
      findsOneWidget,
    );
    expect(find.descendant(of: _card(), matching: find.text(adminTestL10n.loadingLabel)), findsNothing);
  });

  testWidgets('the vendor-approvals card is still there', (tester) async {
    await pumpAdminScreen(tester, const AdminDashboardScreen(), FakeFirebaseFirestore());

    expect(find.text(adminTestL10n.vendorApprovalsTitle), findsOneWidget);
    expect(find.text(adminTestL10n.pendingApprovalsCountLabel(0)), findsOneWidget);
  });

  testWidgets('tapping the card opens the Drivers destination; back returns to the dashboard', (tester) async {
    final db = FakeFirebaseFirestore();
    await seedDriver(db, 'd1', 'Pending One', approval: 'pending');
    await pumpAdminScreen(tester, const AdminDashboardScreen(), db);

    await tester.tap(_card());
    await tester.pumpAndSettle();
    expect(find.byType(AdminDriversScreen), findsOneWidget);
    expect(find.text('Pending One'), findsOneWidget);

    // System back: on narrow screens AdminScaffold's AppBar shows the
    // drawer button rather than a back arrow.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(AdminDriversScreen), findsNothing);
    expect(find.byType(AdminDashboardScreen), findsOneWidget);
  });
}
