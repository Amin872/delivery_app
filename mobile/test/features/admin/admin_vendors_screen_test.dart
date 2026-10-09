import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:delivery_app/features/admin/screens/admin_vendors_screen.dart';
import 'package:delivery_app/models/approval_status.dart';
import 'package:delivery_app/services/firestore_service.dart';

import 'admin_test_harness.dart';

const _rawError = 'permission-denied: raw backend detail';

/// The real FirestoreService over an in-memory Firestore (so the vendor
/// stream and every non-overridden write behave for real), with the
/// approval write held open until a test completes or fails it, and the
/// open/closed write optionally failing.
class _ControlledVendorService extends FirestoreService {
  _ControlledVendorService(this.db, {this.failOpenWrites = false}) : super(firestore: db);

  final FakeFirebaseFirestore db;
  final bool failOpenWrites;
  final approvalWrites = <(String, ApprovalStatus)>[];
  final openWrites = <(String, bool)>[];
  Completer<void> approval = Completer<void>();

  @override
  Future<void> setVendorApprovalStatus(String vendorId, ApprovalStatus status) {
    approvalWrites.add((vendorId, status));
    return approval.future;
  }

  @override
  Future<void> setVendorOpen(String vendorId, bool isOpen) async {
    openWrites.add((vendorId, isOpen));
    if (failOpenWrites) throw Exception(_rawError);
    return super.setVendorOpen(vendorId, isOpen);
  }
}

Future<FakeFirebaseFirestore> _db() async {
  final db = FakeFirebaseFirestore();
  Future<void> vendor(String id, String name, String status, {bool open = false}) =>
      db.collection('vendors').doc(id).set({
        'ownerId': 'owner-$id',
        'name': name,
        'description': '',
        'isOpen': open,
        'approvalStatus': status,
        'etaMinMinutes': 20,
        'etaMaxMinutes': 40,
      });
  await vendor('v-pending', 'Pending Pizza', 'pending');
  await vendor('v-approved', 'Approved Shawarma', 'approved', open: true);
  await vendor('v-rejected', 'Rejected Grill', 'rejected');
  return db;
}

Future<_ControlledVendorService> _pump(WidgetTester tester, {bool failOpenWrites = false}) async {
  final db = await _db();
  final service = _ControlledVendorService(db, failOpenWrites: failOpenWrites);
  await pumpAdminScreen(tester, const AdminVendorsScreen(), db, service: service, size: const Size(400, 1400));
  return service;
}

Finder _approve(String id) => find.byKey(ValueKey('admin_vendor_approve_$id'));
Finder _reject(String id) => find.byKey(ValueKey('admin_vendor_reject_$id'));
Finder _menu(String id) => find.byKey(ValueKey('admin_vendor_actions_$id'));
Finder _busy(String id) => find.byKey(ValueKey('admin_vendor_busy_$id'));

Switch _openSwitch(WidgetTester tester, String id) => tester.widget<Switch>(
    find.descendant(of: find.byKey(ValueKey('admin_vendor_open_$id')), matching: find.byType(Switch)));

Finder _formScrollable() => find
    .descendant(of: find.byKey(const ValueKey('admin_vendor_edit_form')), matching: find.byType(Scrollable))
    .first;

/// A localized error snackbar is showing, without the raw exception text.
void _expectLocalizedError() {
  expect(find.byType(SnackBar), findsOneWidget);
  expect(find.textContaining('permission-denied'), findsNothing);
  expect(find.textContaining('raw backend detail'), findsNothing);
}

/// Lets the in-flight spinner animate without waiting for it to settle.
Future<void> _pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('approval actions', () {
    testWidgets('a pending vendor shows Approve and Reject; decided vendors do not', (tester) async {
      await _pump(tester);

      expect(_approve('v-pending'), findsOneWidget);
      expect(_reject('v-pending'), findsOneWidget);
      expect(_approve('v-approved'), findsNothing);
      expect(_reject('v-rejected'), findsNothing);
    });

    testWidgets('approve asks for confirmation; Cancel sends nothing', (tester) async {
      final service = await _pump(tester);

      await tester.tap(_approve('v-pending'));
      await tester.pumpAndSettle();
      expect(find.text(adminTestL10n.vendorApproveConfirmTitle), findsOneWidget);
      expect(find.text(adminTestL10n.vendorApproveConfirmMessage('Pending Pizza')), findsOneWidget);

      await tester.tap(find.text(adminTestL10n.cancelButton));
      await tester.pumpAndSettle();
      expect(service.approvalWrites, isEmpty);
    });

    testWidgets('confirmed approve: busy blocks a second submission, success only once it lands', (tester) async {
      final service = await _pump(tester);

      await tester.tap(_approve('v-pending'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(adminTestL10n.confirmButton));
      await _pumpFrames(tester);

      expect(service.approvalWrites, [('v-pending', ApprovalStatus.approved)]);
      expect(_busy('v-pending'), findsOneWidget);
      final approveButton = find.ancestor(
        of: find.text(adminTestL10n.approveTooltip),
        matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
      );
      expect(tester.widget<ButtonStyleButton>(approveButton.first).onPressed, isNull);
      // No success is reported while the write is still in flight.
      expect(find.text(adminTestL10n.vendorApprovedMessage), findsNothing);

      // A second tap while busy does nothing.
      await tester.tap(_approve('v-pending'), warnIfMissed: false);
      await _pumpFrames(tester);
      expect(find.text(adminTestL10n.vendorApproveConfirmTitle), findsNothing);

      service.approval.complete();
      await tester.pumpAndSettle();
      expect(find.text(adminTestL10n.vendorApprovedMessage), findsOneWidget);
      expect(_busy('v-pending'), findsNothing);
      expect(service.approvalWrites, hasLength(1));
    });

    testWidgets('reject is confirmed as destructive; a failed write shows a localized error', (tester) async {
      final service = await _pump(tester);

      await tester.tap(_reject('v-pending'));
      await tester.pumpAndSettle();
      expect(find.text(adminTestL10n.vendorRejectConfirmTitle), findsOneWidget);
      final confirm = tester.widget<FilledButton>(find.widgetWithText(FilledButton, adminTestL10n.confirmButton));
      final dialogContext = tester.element(find.byType(AlertDialog));
      expect(
        confirm.style?.backgroundColor?.resolve(<WidgetState>{}),
        Theme.of(dialogContext).colorScheme.error,
      );

      await tester.tap(find.text(adminTestL10n.confirmButton));
      await _pumpFrames(tester);
      expect(service.approvalWrites, [('v-pending', ApprovalStatus.rejected)]);

      service.approval.completeError(Exception(_rawError));
      await tester.pumpAndSettle();
      _expectLocalizedError();
      expect(find.text(adminTestL10n.vendorRejectedByAdminMessage), findsNothing);
      // Actions are available again after the failure.
      expect(_busy('v-pending'), findsNothing);
      expect(_reject('v-pending'), findsOneWidget);
    });

    testWidgets('an approved vendor can be reversed (reject) from its menu, with confirmation', (tester) async {
      final service = await _pump(tester);

      await tester.tap(_menu('v-approved'));
      await tester.pumpAndSettle();
      expect(find.text(adminTestL10n.editStoreDetailsTooltip), findsOneWidget);
      // No "Approve" in an approved vendor's menu: the only one on screen
      // is the pending card's button.
      expect(find.text(adminTestL10n.approveTooltip), findsOneWidget);
      // "Reject" is both the pending card's button and the menu entry; the
      // open menu is on top, so last.
      expect(find.text(adminTestL10n.rejectTooltip), findsNWidgets(2));
      await tester.tap(find.text(adminTestL10n.rejectTooltip).last);
      await tester.pumpAndSettle();

      expect(find.text(adminTestL10n.vendorRejectConfirmMessage('Approved Shawarma')), findsOneWidget);
      await tester.tap(find.text(adminTestL10n.confirmButton));
      await _pumpFrames(tester);
      expect(service.approvalWrites, [('v-approved', ApprovalStatus.rejected)]);
      service.approval.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('a rejected vendor can be approved again from its menu, with confirmation', (tester) async {
      final service = await _pump(tester);

      await tester.tap(_menu('v-rejected'));
      await tester.pumpAndSettle();
      // The pending card's button plus this menu's entry (on top, so last);
      // no "Reject" entry for an already-rejected vendor.
      expect(find.text(adminTestL10n.approveTooltip), findsNWidgets(2));
      expect(find.text(adminTestL10n.rejectTooltip), findsOneWidget);
      await tester.tap(find.text(adminTestL10n.approveTooltip).last);
      await tester.pumpAndSettle();

      expect(find.text(adminTestL10n.vendorApproveConfirmMessage('Rejected Grill')), findsOneWidget);
      await tester.tap(find.text(adminTestL10n.confirmButton));
      await _pumpFrames(tester);
      expect(service.approvalWrites, [('v-rejected', ApprovalStatus.approved)]);
      service.approval.complete();
      await tester.pumpAndSettle();
      expect(find.text(adminTestL10n.vendorApprovedMessage), findsOneWidget);
    });
  });

  group('open / closed switch', () {
    testWidgets('closing asks first; backing out rolls the switch back with no write', (tester) async {
      final service = await _pump(tester);
      expect(_openSwitch(tester, 'v-approved').value, isTrue);

      await tester.tap(find.byKey(const ValueKey('admin_vendor_open_v-approved')));
      await tester.pumpAndSettle();
      expect(find.text(adminTestL10n.vendorCloseConfirmMessage('Approved Shawarma')), findsOneWidget);
      await tester.tap(find.text(adminTestL10n.cancelButton));
      await tester.pumpAndSettle();

      expect(service.openWrites, isEmpty);
      expect(_openSwitch(tester, 'v-approved').value, isTrue);
    });

    testWidgets('a failed write shows a localized error and the switch keeps the real state', (tester) async {
      final service = await _pump(tester, failOpenWrites: true);

      await tester.tap(find.byKey(const ValueKey('admin_vendor_open_v-approved')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(adminTestL10n.confirmButton));
      await tester.pumpAndSettle();

      expect(service.openWrites, [('v-approved', false)]);
      _expectLocalizedError();
      expect(_openSwitch(tester, 'v-approved').value, isTrue);
    });

    testWidgets('a successful close is written and reflected', (tester) async {
      final service = await _pump(tester);

      await tester.tap(find.byKey(const ValueKey('admin_vendor_open_v-approved')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(adminTestL10n.confirmButton));
      await tester.pumpAndSettle();

      expect(service.openWrites, [('v-approved', false)]);
      expect((await service.db.collection('vendors').doc('v-approved').get()).data()!['isOpen'], isFalse);
      expect(_openSwitch(tester, 'v-approved').value, isFalse);
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('edit details form', () {
    Future<void> openForm(WidgetTester tester, String id) async {
      await tester.tap(_menu(id));
      await tester.pumpAndSettle();
      await tester.tap(find.text(adminTestL10n.editStoreDetailsTooltip));
      await tester.pumpAndSettle();
    }

    testWidgets('an out-of-order ETA gets the ETA message, not "invalid price"', (tester) async {
      await _pump(tester);
      await openForm(tester, 'v-approved');

      await tester.enterText(find.widgetWithText(TextFormField, adminTestL10n.etaMinFieldLabel), '50');
      await tester.enterText(find.widgetWithText(TextFormField, adminTestL10n.etaMaxFieldLabel), '20');
      final save = find.text(adminTestL10n.saveButton);
      await tester.scrollUntilVisible(save, 150, scrollable: _formScrollable());
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(find.text(adminTestL10n.invalidEtaError, skipOffstage: false), findsWidgets);
      expect(find.text(adminTestL10n.invalidPriceError, skipOffstage: false), findsNothing);
    });

    testWidgets('a non-numeric ETA also gets the ETA message', (tester) async {
      await _pump(tester);
      await openForm(tester, 'v-approved');

      await tester.enterText(find.widgetWithText(TextFormField, adminTestL10n.etaMinFieldLabel), 'abc');
      final save = find.text(adminTestL10n.saveButton);
      await tester.scrollUntilVisible(save, 150, scrollable: _formScrollable());
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(find.text(adminTestL10n.invalidEtaError, skipOffstage: false), findsOneWidget);
    });

    testWidgets('scrolls on a short phone with the keyboard open, reaching Save', (tester) async {
      await _pump(tester);
      await openForm(tester, 'v-approved');

      // A 320×568 phone (iPhone SE class) with a typical 216px keyboard:
      // the sheet gets ~350px for a ~700px form, so it must scroll. Sized so
      // the vendors list behind the sheet (search + chips) still fits its
      // shrunken body — this test is about the sheet, not that list.
      tester.view.physicalSize = const Size(320, 568);
      tester.view.viewInsets = const FakeViewPadding(bottom: 216);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();

      // The sheet really is taller than the space it has.
      final scrollable = tester.state<ScrollableState>(_formScrollable());
      expect(scrollable.position.maxScrollExtent, greaterThan(0));

      final save = find.text(adminTestL10n.saveButton);
      await tester.scrollUntilVisible(save, 100, scrollable: _formScrollable());
      expect(save.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
