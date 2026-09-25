import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:delivery_app/features/admin/screens/admin_driver_detail_screen.dart';
import 'package:delivery_app/features/admin/screens/admin_drivers_screen.dart';
import 'package:delivery_app/models/approval_status.dart';

import 'admin_test_harness.dart';

DriverRow _row(String id, String name, ApprovalStatus status) => DriverRow(
      driverId: id,
      name: name,
      email: '$id@example.com',
      isAvailable: false,
      averageRating: null,
      ratingCount: 0,
      approvalStatus: status,
    );

final _rows = [
  _row('p1', 'Pending Paul', ApprovalStatus.pending),
  _row('p2', 'Pending Rana', ApprovalStatus.pending),
  _row('a1', 'Approved Adam', ApprovalStatus.approved),
  _row('r1', 'Rejected Rami', ApprovalStatus.rejected),
];

// Wide enough that the whole chip row is on screen, still below
// AdminScaffold's 840dp side-nav breakpoint.
const _wide = Size(700, 900);

List<String> _ids(List<DriverRow> rows) => rows.map((r) => r.driverId).toList();

Future<FakeFirebaseFirestore> _db() async {
  final db = FakeFirebaseFirestore();
  await seedDriver(db, 'p1', 'Pending Paul', approval: 'pending');
  await seedDriver(db, 'p2', 'Pending Rana', approval: 'pending');
  await seedDriver(db, 'a1', 'Approved Adam', approval: 'approved', available: true);
  await seedDriver(db, 'r1', 'Rejected Rami', approval: 'rejected');
  return db;
}

Future<void> _tapChip(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
}

void main() {
  group('filterDriverRows', () {
    test('no status and no query keeps everything', () {
      expect(_ids(filterDriverRows(_rows, query: '')), ['p1', 'p2', 'a1', 'r1']);
    });

    test('each approval status', () {
      expect(_ids(filterDriverRows(_rows, query: '', status: ApprovalStatus.pending)), ['p1', 'p2']);
      expect(_ids(filterDriverRows(_rows, query: '', status: ApprovalStatus.approved)), ['a1']);
      expect(_ids(filterDriverRows(_rows, query: '', status: ApprovalStatus.rejected)), ['r1']);
    });

    test('search and status must both match (name or email)', () {
      expect(_ids(filterDriverRows(_rows, query: 'rana', status: ApprovalStatus.pending)), ['p2']);
      expect(_ids(filterDriverRows(_rows, query: 'a1@', status: ApprovalStatus.approved)), ['a1']);
      expect(filterDriverRows(_rows, query: 'rana', status: ApprovalStatus.approved), isEmpty);
    });
  });

  group('AdminDriversScreen approval chips', () {
    testWidgets('All / Pending / Approved / Rejected filter the list', (tester) async {
      await pumpAdminScreen(tester, const AdminDriversScreen(), await _db(), size: _wide);

      expect(find.byType(ListTile), findsNWidgets(4));

      await _tapChip(tester, 'driver_filter_pending');
      expect(find.text('Pending Paul'), findsOneWidget);
      expect(find.text('Pending Rana'), findsOneWidget);
      expect(find.text('Approved Adam'), findsNothing);
      expect(find.text('Rejected Rami'), findsNothing);

      await _tapChip(tester, 'driver_filter_approved');
      expect(find.byType(ListTile), findsOneWidget);
      expect(find.text('Approved Adam'), findsOneWidget);

      await _tapChip(tester, 'driver_filter_rejected');
      expect(find.byType(ListTile), findsOneWidget);
      expect(find.text('Rejected Rami'), findsOneWidget);

      await _tapChip(tester, 'driver_filter_all');
      expect(find.byType(ListTile), findsNWidgets(4));
    });

    testWidgets('chip labels reuse the localized approval states', (tester) async {
      await pumpAdminScreen(tester, const AdminDriversScreen(), await _db(), size: _wide);

      for (final label in [
        adminTestL10n.allStatusesLabel,
        adminTestL10n.vendorStatusPending,
        adminTestL10n.vendorStatusApproved,
        adminTestL10n.vendorStatusRejected,
      ]) {
        expect(find.widgetWithText(ChoiceChip, label), findsOneWidget, reason: label);
      }
    });

    testWidgets('search and the filter combine; no match shows the empty message', (tester) async {
      await pumpAdminScreen(tester, const AdminDriversScreen(), await _db(), size: _wide);

      await _tapChip(tester, 'driver_filter_pending');
      await tester.enterText(find.byType(TextField), 'rana');
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsOneWidget);
      expect(find.text('Pending Rana'), findsOneWidget);

      await _tapChip(tester, 'driver_filter_approved');
      expect(find.byType(ListTile), findsNothing);
      expect(find.text(adminTestL10n.noDriversFoundMessage), findsOneWidget);
    });

    testWidgets('rows still open the driver detail, rating/availability intact', (tester) async {
      await pumpAdminScreen(tester, const AdminDriversScreen(), await _db(), size: _wide);

      await _tapChip(tester, 'driver_filter_approved');
      expect(find.text(adminTestL10n.driverAvailableStatusLabel), findsOneWidget);

      await tester.tap(find.text('Approved Adam'));
      await tester.pumpAndSettle();
      expect(tester.widget<AdminDriverDetailScreen>(find.byType(AdminDriverDetailScreen)).driverId, 'a1');
    });
  });
}
