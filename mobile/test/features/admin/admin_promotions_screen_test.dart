import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:delivery_app/features/admin/screens/admin_promotions_screen.dart';
import 'package:delivery_app/models/approval_status.dart';
import 'package:delivery_app/models/vendor.dart';
import 'package:delivery_app/services/firestore_service.dart';

import 'admin_test_harness.dart';

const _rawError = 'permission-denied: raw backend detail';

/// Real FirestoreService over an in-memory Firestore, with the delete and
/// enable writes optionally failing.
class _PromotionService extends FirestoreService {
  _PromotionService(this.db, {this.failWrites = false}) : super(firestore: db);

  final FakeFirebaseFirestore db;
  final bool failWrites;

  @override
  Future<void> deletePromotion(String promotionId) async {
    if (failWrites) throw Exception(_rawError);
    return super.deletePromotion(promotionId);
  }

  @override
  Future<void> setPromotionEnabled(String promotionId, bool enabled) async {
    if (failWrites) throw Exception(_rawError);
    return super.setPromotionEnabled(promotionId, enabled);
  }
}

Vendor _vendor(String id, String name, ApprovalStatus status) =>
    Vendor(id: id, ownerId: 'o', name: name, description: '', isOpen: true, approvalStatus: status);

/// A video promotion (no network image, so the screen settles) linked to
/// [ctaAction].
Future<FakeFirebaseFirestore> _db({String? ctaAction, String? ctaLabel}) async {
  final db = FakeFirebaseFirestore();
  Future<void> vendor(String id, String name, String status) => db.collection('vendors').doc(id).set({
        'ownerId': 'owner-$id',
        'name': name,
        'description': '',
        'isOpen': true,
        'approvalStatus': status,
      });
  await vendor('v-zaatar', 'Zaatar House', 'approved');
  await vendor('v-burger', 'Burger Spot', 'approved');
  await vendor('v-pending', 'Pending Pizza', 'pending');
  await db.collection('promotions').doc('p1').set({
    'title': 'Weekend deal',
    'description': null,
    'mediaUrl': 'https://example.com/promo.mp4',
    'mediaType': 'video',
    'ctaLabel': ctaLabel,
    'ctaAction': ctaAction,
    'order': 1,
    'enabled': true,
  });
  return db;
}

Future<_PromotionService> _pump(WidgetTester tester, FakeFirebaseFirestore db, {bool failWrites = false}) async {
  final service = _PromotionService(db, failWrites: failWrites);
  await pumpAdminScreen(tester, const AdminPromotionsScreen(), db, service: service, size: const Size(400, 1000));
  return service;
}

Future<void> _openMenuAction(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const ValueKey('admin_promotion_actions_p1')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Finder _formScrollable() => find
    .descendant(of: find.byKey(const ValueKey('admin_promotion_form')), matching: find.byType(Scrollable))
    .first;

Future<void> _save(WidgetTester tester) async {
  final save = find.text(adminTestL10n.saveButton);
  await tester.scrollUntilVisible(save, 150, scrollable: _formScrollable());
  await tester.tap(save);
  await tester.pumpAndSettle();
}

Future<void> _pickCtaVendor(WidgetTester tester, String label) async {
  final field = find.byKey(const ValueKey('admin_promotion_cta_vendor'));
  await tester.scrollUntilVisible(field, 100, scrollable: _formScrollable());
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Switch _enabledSwitch(WidgetTester tester) => tester.widget<Switch>(find.descendant(
    of: find.byKey(const ValueKey('admin_promotion_enabled_p1')), matching: find.byType(Switch)));

void _expectLocalizedError() {
  expect(find.byType(SnackBar), findsOneWidget);
  expect(find.textContaining('permission-denied'), findsNothing);
  expect(find.textContaining('raw backend detail'), findsNothing);
}

void main() {
  group('ctaVendorChoices / validatePromotionCta', () {
    final vendors = [
      _vendor('b', 'beta', ApprovalStatus.approved),
      _vendor('p', 'pending', ApprovalStatus.pending),
      _vendor('a', 'Alpha', ApprovalStatus.approved),
      _vendor('r', 'rejected', ApprovalStatus.rejected),
    ];

    test('offers approved vendors only, by name', () {
      expect(ctaVendorChoices(vendors).map((v) => v.id), ['a', 'b']);
    });

    test('no label and no store is valid', () {
      expect(validatePromotionCta(label: '  ', vendorId: null, vendors: vendors), isNull);
    });

    test('label and an approved store is valid', () {
      expect(validatePromotionCta(label: 'Order now', vendorId: 'a', vendors: vendors), isNull);
    });

    test('a label without a store, or a store without a label, is incomplete', () {
      expect(validatePromotionCta(label: 'Order now', vendorId: null, vendors: vendors), PromotionCtaError.incomplete);
      expect(validatePromotionCta(label: '', vendorId: 'a', vendors: vendors), PromotionCtaError.incomplete);
    });

    test('a non-approved, unknown, or unverifiable store is rejected', () {
      expect(validatePromotionCta(label: 'Go', vendorId: 'p', vendors: vendors), PromotionCtaError.unavailableVendor);
      expect(validatePromotionCta(label: 'Go', vendorId: 'gone', vendors: vendors), PromotionCtaError.unavailableVendor);
      expect(validatePromotionCta(label: 'Go', vendorId: 'a', vendors: null), PromotionCtaError.unavailableVendor);
    });
  });

  group('CTA store selector', () {
    testWidgets('lists approved stores only and saves the chosen vendor id', (tester) async {
      final db = await _db();
      await _pump(tester, db);
      await _openMenuAction(tester, adminTestL10n.editTooltip);

      await tester.enterText(find.widgetWithText(TextFormField, adminTestL10n.ctaLabelFieldLabel), 'Order now');
      final field = find.byKey(const ValueKey('admin_promotion_cta_vendor'));
      await tester.scrollUntilVisible(field, 100, scrollable: _formScrollable());
      await tester.tap(field);
      await tester.pumpAndSettle();
      expect(find.text('Zaatar House'), findsWidgets);
      expect(find.text('Burger Spot'), findsWidgets);
      expect(find.text('Pending Pizza'), findsNothing);
      await tester.tap(find.text('Zaatar House').last);
      await tester.pumpAndSettle();

      await _save(tester);

      final saved = (await db.collection('promotions').doc('p1').get()).data()!;
      expect(saved['ctaAction'], 'v-zaatar');
      expect(saved['ctaLabel'], 'Order now');
      expect(find.text(adminTestL10n.promotionSavedMessage), findsOneWidget);
    });

    testWidgets('a store without a button label is not saved', (tester) async {
      final db = await _db();
      await _pump(tester, db);
      await _openMenuAction(tester, adminTestL10n.editTooltip);

      await _pickCtaVendor(tester, 'Burger Spot');
      await _save(tester);

      expect(find.text(adminTestL10n.ctaIncompleteError, skipOffstage: false), findsOneWidget);
      expect((await db.collection('promotions').doc('p1').get()).data()!['ctaAction'], isNull);
    });

    testWidgets('a saved link to a no-longer-approved store is kept visible but must be fixed', (tester) async {
      final db = await _db(ctaAction: 'v-pending', ctaLabel: 'Order now');
      await _pump(tester, db);
      await _openMenuAction(tester, adminTestL10n.editTooltip);

      // Shown by name, not silently dropped.
      expect(find.text('Pending Pizza', skipOffstage: false), findsOneWidget);
      await _save(tester);
      expect(find.text(adminTestL10n.ctaVendorUnavailableError, skipOffstage: false), findsOneWidget);

      await _pickCtaVendor(tester, adminTestL10n.ctaNoVendorOption);
      await tester.enterText(find.widgetWithText(TextFormField, adminTestL10n.ctaLabelFieldLabel), '');
      await _save(tester);
      final saved = (await db.collection('promotions').doc('p1').get()).data()!;
      expect(saved['ctaAction'], isNull);
      expect(saved['ctaLabel'], isNull);
    });
  });

  group('delete', () {
    testWidgets('asks for confirmation; Cancel keeps the promotion', (tester) async {
      final db = await _db();
      await _pump(tester, db);
      await _openMenuAction(tester, adminTestL10n.deleteTooltip);

      expect(find.text(adminTestL10n.deletePromotionConfirmMessage), findsOneWidget);
      await tester.tap(find.text(adminTestL10n.cancelButton));
      await tester.pumpAndSettle();
      expect((await db.collection('promotions').doc('p1').get()).exists, isTrue);
    });

    testWidgets('confirmed: deleted, then success feedback', (tester) async {
      final db = await _db();
      await _pump(tester, db);
      await _openMenuAction(tester, adminTestL10n.deleteTooltip);
      await tester.tap(find.text(adminTestL10n.confirmButton));
      await tester.pumpAndSettle();

      expect((await db.collection('promotions').doc('p1').get()).exists, isFalse);
      expect(find.text(adminTestL10n.promotionDeletedMessage), findsOneWidget);
    });

    testWidgets('a failed delete shows a localized error and keeps the row', (tester) async {
      final db = await _db();
      await _pump(tester, db, failWrites: true);
      await _openMenuAction(tester, adminTestL10n.deleteTooltip);
      await tester.tap(find.text(adminTestL10n.confirmButton));
      await tester.pumpAndSettle();

      _expectLocalizedError();
      expect(find.text(adminTestL10n.promotionDeletedMessage), findsNothing);
      expect(find.byKey(const ValueKey('admin_promotion_p1')), findsOneWidget);
    });
  });

  testWidgets('a failed enable toggle shows a localized error and rolls the switch back', (tester) async {
    final db = await _db();
    await _pump(tester, db, failWrites: true);
    expect(_enabledSwitch(tester).value, isTrue);

    await tester.tap(find.byKey(const ValueKey('admin_promotion_enabled_p1')));
    await tester.pumpAndSettle();

    _expectLocalizedError();
    expect(_enabledSwitch(tester).value, isTrue);
    expect((await db.collection('promotions').doc('p1').get()).data()!['enabled'], isTrue);
  });
}
