import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:delivery_app/features/admin/screens/admin_locations_screen.dart';
import 'package:delivery_app/models/vendor.dart';
import 'package:delivery_app/services/firestore_service.dart';

import 'admin_test_harness.dart';

const _rawError = 'permission-denied: raw backend detail';

/// Real FirestoreService over an in-memory Firestore, with the three
/// enable/disable writes optionally failing, and the vendor list
/// optionally failing to load.
class _LocationService extends FirestoreService {
  _LocationService(this.db, {this.failWrites = false, this.failVendorList = false}) : super(firestore: db);

  final FakeFirebaseFirestore db;
  final bool failWrites;
  final bool failVendorList;

  @override
  Stream<List<Vendor>> watchAllVendors() =>
      failVendorList ? Stream.error(Exception(_rawError)) : super.watchAllVendors();

  @override
  Future<void> setGovernorateEnabled(String governorateId, bool enabled) async {
    if (failWrites) throw Exception(_rawError);
    return super.setGovernorateEnabled(governorateId, enabled);
  }

  @override
  Future<void> setCityEnabled(String cityId, bool enabled) async {
    if (failWrites) throw Exception(_rawError);
    return super.setCityEnabled(cityId, enabled);
  }

  @override
  Future<void> setNeighborhoodEnabled(String neighborhoodId, bool enabled) async {
    if (failWrites) throw Exception(_rawError);
    return super.setNeighborhoodEnabled(neighborhoodId, enabled);
  }
}

Future<FakeFirebaseFirestore> _db({bool cityEnabled = true}) async {
  final db = FakeFirebaseFirestore();
  await db.collection('governorates').doc('damascus_gov').set({
    'nameEn': 'Damascus Governorate',
    'nameAr': 'محافظة دمشق',
    'enabled': true,
    'order': 1,
  });
  await db.collection('cities').doc('damascus').set({
    'nameEn': 'Damascus',
    'nameAr': 'دمشق',
    'enabled': cityEnabled,
    'order': 1,
    'governorateId': 'damascus_gov',
  });
  await db.collection('neighborhoods').doc('mezzeh').set({
    'nameEn': 'Mezzeh',
    'nameAr': 'المزة',
    'cityId': 'damascus',
    'enabled': true,
    'order': 1,
  });
  return db;
}

Future<void> _pump(
  WidgetTester tester,
  FakeFirebaseFirestore db, {
  bool failWrites = false,
  bool failVendorList = false,
}) async {
  await pumpAdminScreen(tester, const AdminLocationsScreen(), db,
      service: _LocationService(db, failWrites: failWrites, failVendorList: failVendorList),
      size: const Size(400, 900));
}

Future<void> _seedVendorIn(FakeFirebaseFirestore db, String cityId) =>
    db.collection('vendors').doc('v1').set({
      'ownerId': 'o1',
      'name': 'Falafel House',
      'description': '',
      'isOpen': true,
      'approvalStatus': 'approved',
      'city': cityId,
    });

Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(Tab, label));
  await tester.pumpAndSettle();
}

bool _switchValue(WidgetTester tester, String key) => tester
    .widget<Switch>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Switch)))
    .value;

void _expectLocalizedError() {
  expect(find.byType(SnackBar), findsOneWidget);
  expect(find.textContaining('permission-denied'), findsNothing);
  expect(find.textContaining('raw backend detail'), findsNothing);
}

Future<bool?> _enabled(FakeFirebaseFirestore db, String collection, String id) async =>
    (await db.collection(collection).doc(id).get()).data()!['enabled'] as bool?;

void main() {
  testWidgets('the tab bar scrolls rather than squeezing three tabs', (tester) async {
    await _pump(tester, await _db());
    expect(tester.widget<TabBar>(find.byType(TabBar)).isScrollable, isTrue);
  });

  group('neighborhood switch', () {
    testWidgets('disabling asks first; Cancel keeps it enabled with no write', (tester) async {
      final db = await _db();
      await _pump(tester, db);
      await _openTab(tester, adminTestL10n.neighborhoodsTabLabel);

      await tester.tap(find.byKey(const ValueKey('admin_neighborhood_enabled_mezzeh')));
      await tester.pumpAndSettle();
      expect(find.text(adminTestL10n.disableNeighborhoodConfirmMessage), findsOneWidget);
      await tester.tap(find.text(adminTestL10n.cancelButton));
      await tester.pumpAndSettle();

      expect(await _enabled(db, 'neighborhoods', 'mezzeh'), isTrue);
      expect(_switchValue(tester, 'admin_neighborhood_enabled_mezzeh'), isTrue);
    });

    testWidgets('confirmed: disabled in Firestore and on screen', (tester) async {
      final db = await _db();
      await _pump(tester, db);
      await _openTab(tester, adminTestL10n.neighborhoodsTabLabel);

      await tester.tap(find.byKey(const ValueKey('admin_neighborhood_enabled_mezzeh')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(adminTestL10n.confirmButton));
      await tester.pumpAndSettle();

      expect(await _enabled(db, 'neighborhoods', 'mezzeh'), isFalse);
      expect(_switchValue(tester, 'admin_neighborhood_enabled_mezzeh'), isFalse);
    });

    testWidgets('a failed write shows a localized error and rolls back', (tester) async {
      final db = await _db();
      await _pump(tester, db, failWrites: true);
      await _openTab(tester, adminTestL10n.neighborhoodsTabLabel);

      await tester.tap(find.byKey(const ValueKey('admin_neighborhood_enabled_mezzeh')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(adminTestL10n.confirmButton));
      await tester.pumpAndSettle();

      _expectLocalizedError();
      expect(_switchValue(tester, 'admin_neighborhood_enabled_mezzeh'), isTrue);
    });
  });

  testWidgets('a failed city switch shows a localized error and rolls back', (tester) async {
    final db = await _db();
    await _pump(tester, db, failWrites: true);
    await _openTab(tester, adminTestL10n.citiesTabLabel);

    // No vendor uses the city, so disabling needs no confirmation.
    await tester.tap(find.byKey(const ValueKey('admin_city_enabled_damascus')));
    await tester.pumpAndSettle();

    _expectLocalizedError();
    expect(_switchValue(tester, 'admin_city_enabled_damascus'), isTrue);
    expect(await _enabled(db, 'cities', 'damascus'), isTrue);
  });

  // Locations is the first (and only) screen opened here, so nothing else
  // has loaded the city or vendor lists — the warning must still be based
  // on real data.
  testWidgets('disabling a governorate used by a vendor warns first', (tester) async {
    final db = await _db();
    await _seedVendorIn(db, 'damascus');
    await _pump(tester, db);

    await tester.tap(find.byKey(const ValueKey('admin_governorate_enabled_damascus_gov')));
    await tester.pumpAndSettle();
    expect(find.text(adminTestL10n.disableLocationInUseWarning(1)), findsOneWidget);
    await tester.tap(find.text(adminTestL10n.cancelButton));
    await tester.pumpAndSettle();
    expect(await _enabled(db, 'governorates', 'damascus_gov'), isTrue);
    expect(_switchValue(tester, 'admin_governorate_enabled_damascus_gov'), isTrue);
  });

  testWidgets('disabling a city used by a vendor warns first', (tester) async {
    final db = await _db();
    await _seedVendorIn(db, 'damascus');
    await _pump(tester, db);
    await _openTab(tester, adminTestL10n.citiesTabLabel);

    await tester.tap(find.byKey(const ValueKey('admin_city_enabled_damascus')));
    await tester.pumpAndSettle();
    expect(find.text(adminTestL10n.disableLocationInUseWarning(1)), findsOneWidget);
    await tester.tap(find.text(adminTestL10n.confirmButton));
    await tester.pumpAndSettle();
    expect(await _enabled(db, 'cities', 'damascus'), isFalse);
  });

  testWidgets('a governorate not used by any vendor disables without a warning', (tester) async {
    final db = await _db();
    await _seedVendorIn(db, 'somewhere_else');
    await _pump(tester, db);

    await tester.tap(find.byKey(const ValueKey('admin_governorate_enabled_damascus_gov')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(await _enabled(db, 'governorates', 'damascus_gov'), isFalse);
  });

  testWidgets('if usage can\'t be checked, disabling still asks first', (tester) async {
    final db = await _db();
    await _pump(tester, db, failVendorList: true);

    await tester.tap(find.byKey(const ValueKey('admin_governorate_enabled_damascus_gov')));
    await tester.pumpAndSettle();
    expect(find.text(adminTestL10n.disableLocationUsageUnknownWarning), findsOneWidget);
    await tester.tap(find.text(adminTestL10n.cancelButton));
    await tester.pumpAndSettle();
    expect(await _enabled(db, 'governorates', 'damascus_gov'), isTrue);
    expect(_switchValue(tester, 'admin_governorate_enabled_damascus_gov'), isTrue);
  });

  testWidgets('with no enabled city, adding a neighborhood is disabled and says why', (tester) async {
    await _pump(tester, await _db(cityEnabled: false));
    await _openTab(tester, adminTestL10n.neighborhoodsTabLabel);

    final reason = find.byKey(const ValueKey('admin_location_add_disabled_reason'));
    expect(reason, findsOneWidget);
    expect(tester.widget<Text>(reason).data, adminTestL10n.addNeighborhoodNeedsCityMessage);
    final add = find.byTooltip(adminTestL10n.addNeighborhoodNeedsCityMessage);
    expect(add, findsOneWidget);
    final button = tester.widget<IconButton>(find.ancestor(of: add, matching: find.byType(IconButton)).first);
    expect(button.onPressed, isNull);
  });

  testWidgets('saving a new governorate shows success only after it is written', (tester) async {
    final db = await _db();
    await _pump(tester, db);

    await tester.tap(find.byTooltip(adminTestL10n.addGovernorateTitle));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, adminTestL10n.locationIdFieldLabel), 'aleppo_gov');
    await tester.enterText(find.widgetWithText(TextFormField, adminTestL10n.nameEnFieldLabel), 'Aleppo Governorate');
    await tester.enterText(find.widgetWithText(TextFormField, adminTestL10n.nameArFieldLabel), 'محافظة حلب');
    final save = find.text(adminTestL10n.saveButton);
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect((await db.collection('governorates').doc('aleppo_gov').get()).exists, isTrue);
    expect(find.text(adminTestL10n.locationSavedMessage), findsOneWidget);
  });
}
