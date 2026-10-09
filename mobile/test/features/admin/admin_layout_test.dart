import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:delivery_app/core/theme/app_sizes.dart';
import 'package:delivery_app/features/admin/screens/admin_analytics_screen.dart';
import 'package:delivery_app/features/admin/screens/admin_dashboard_screen.dart';
import 'package:delivery_app/features/admin/screens/admin_driver_detail_screen.dart';
import 'package:delivery_app/features/admin/screens/admin_drivers_screen.dart';
import 'package:delivery_app/features/admin/screens/admin_locations_screen.dart';
import 'package:delivery_app/features/admin/screens/admin_orders_screen.dart';
import 'package:delivery_app/features/admin/screens/admin_products_screen.dart';
import 'package:delivery_app/features/admin/screens/admin_promotions_screen.dart';
import 'package:delivery_app/features/admin/screens/admin_users_screen.dart';
import 'package:delivery_app/features/admin/screens/admin_vendors_screen.dart';
import 'package:delivery_app/features/customer/screens/customer_home_screen.dart' show firestoreServiceProvider;
import 'package:delivery_app/l10n/app_localizations.dart';
import 'package:delivery_app/models/order.dart';
import 'package:delivery_app/services/firestore_service.dart';

import '../../support/real_theme_harness.dart';

// Realistic worst cases: long Arabic and English names, a full-length
// Firestore id, eight-digit SYP amounts, a long email and phone.
const _longAr = 'مطعم الشام الكبير للمأكولات الشرقية والمشاوي الدمشقية الأصيلة';
const _longEn = 'The Grand Damascus Kitchen for Oriental Food and Traditional Grills';
const _longId = 'Xk9QpL2mZt7RwY4bNcV1';

Future<FakeFirebaseFirestore> _db() async {
  final db = FakeFirebaseFirestore();
  Future<void> vendor(String id, String name, String status, {bool open = true}) =>
      db.collection('vendors').doc(id).set({
        'ownerId': 'owner-$id',
        'name': name,
        'description': '$name — $name',
        'isOpen': open,
        'approvalStatus': status,
        'city': 'damascus',
        'deliveryFee': 10000,
        'etaMinMinutes': 25,
        'etaMaxMinutes': 40,
        'minimumOrderAmount': 150000,
        'openTime': '10:00',
        'closeTime': '23:30',
      });
  await vendor('v-pending', _longAr, 'pending');
  await vendor('v-approved', _longEn, 'approved');
  await vendor('v-rejected', _longAr, 'rejected', open: false);

  await db.collection('vendors').doc('v-approved').collection('menuItems').doc('m1').set({
    'vendorId': 'v-approved',
    'name': _longAr,
    'price': 12500000,
    'available': true,
  });
  await db.collection('vendors').doc('v-approved').collection('menuItems').doc('m2').set({
    'vendorId': 'v-approved',
    'name': _longEn,
    'price': 3000,
    'available': false,
  });

  await db.collection('promotions').doc('p1').set({
    'title': _longAr,
    'mediaUrl': 'https://example.com/promo.mp4',
    'mediaType': 'video',
    'ctaLabel': 'اطلب الآن',
    'ctaAction': 'v-approved',
    'order': 12,
    'enabled': true,
  });

  await db.collection('governorates').doc('rif_dimashq').set({
    'nameEn': 'Rif Dimashq Governorate (Damascus Countryside)',
    'nameAr': 'محافظة ريف دمشق والمناطق المحيطة بها',
    'enabled': true,
    'order': 1,
  });
  await db.collection('cities').doc('damascus').set({
    'nameEn': 'Damascus Metropolitan Area',
    'nameAr': 'دمشق والمنطقة الحضرية المحيطة',
    'enabled': true,
    'order': 1,
    'governorateId': 'rif_dimashq',
  });
  await db.collection('neighborhoods').doc('mezzeh_villas').set({
    'nameEn': 'Mezzeh Western Villas and Surroundings',
    'nameAr': 'المزة فيلات غربية وما حولها',
    'cityId': 'damascus',
    'enabled': true,
    'order': 3,
    'ochaPcode': 'SY0100005',
  });

  await db.collection('users').doc('d1').set({
    'email': 'very.long.driver.address.for.testing@example-delivery-company.com',
    'displayName': _longAr,
    'role': 'driver',
    'phoneNumber': '+963944123456',
  });
  await db.collection('drivers').doc('d1').set({
    'userId': 'd1',
    'isAvailable': true,
    'approvalStatus': 'pending',
    'ratingSum': 9,
    'ratingCount': 2,
  });
  await db.collection('users').doc('c1').set({
    'email': 'customer@example.com',
    'displayName': _longEn,
    'role': 'customer',
    'phoneNumber': '0944123456',
  });

  for (final (i, status) in OrderStatus.values.indexed) {
    final id = i == 0 ? _longId : 'order-${status.name}';
    await db.collection('orders').doc(id).set(DeliveryOrder(
          id: id,
          customerId: 'c1',
          vendorId: 'v-approved',
          items: const [],
          status: status,
          total: 99999999,
          deliveryAddress: 'Mezzeh',
          createdAt: DateTime(2026, 9, 1 + i),
        ).toMap());
  }
  return db;
}

Future<void> _pump(WidgetTester tester, LayoutConfig c, Widget screen, {double height = 800}) async {
  final db = await _db();
  await pumpWithRealTheme(
    tester,
    screen,
    locale: c.locale,
    width: c.width,
    height: height,
    textScale: c.textScale,
    overrides: [
      firestoreServiceProvider.overrideWithValue(FirestoreService(firestore: db)),
      marketplaceStatsProvider.overrideWith((ref) async => const MarketplaceStats(
            userCount: 1234567,
            vendorCount: 98765,
            driverCount: 4321,
            orderCount: 87654321,
            deliveredSalesTotal: 9876543210,
          )),
    ],
  );
  await tester.pumpAndSettle();
}

/// [finder] is on screen, tappable, inside the viewport and at least the
/// 48px tap target.
void _expectReachable(WidgetTester tester, Finder finder, LayoutConfig c) {
  expect(finder.hitTestable(), findsOneWidget);
  final rect = tester.getRect(finder);
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(c.width));
  expect(rect.height, greaterThanOrEqualTo(AppSizes.minTapTarget - 0.5));
}

/// Scrolls the screen's first vertical list end to end; any overflow on
/// the way fails the test.
Future<void> _scrollThrough(WidgetTester tester) async {
  final vertical = find.byWidgetPredicate(
      (widget) => widget is Scrollable && axisDirectionToAxis(widget.axisDirection) == Axis.vertical);
  for (var i = 0; i < 6; i++) {
    if (vertical.evaluate().isEmpty) return;
    await tester.drag(vertical.first, const Offset(0, -300), warnIfMissed: false);
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgetsAcrossLayouts('vendors: cards, approval buttons and menus fit', (tester, c) async {
    final l10n = lookupAppLocalizations(c.locale);
    await _pump(tester, c, const AdminVendorsScreen());

    _expectReachable(tester, find.byKey(const ValueKey('admin_vendor_actions_v-pending')), c);
    _expectReachable(tester, find.byKey(const ValueKey('admin_vendor_approve_v-pending')), c);
    _expectReachable(tester, find.byKey(const ValueKey('admin_vendor_reject_v-pending')), c);
    expect(find.text(l10n.approveTooltip), findsOneWidget);
    await _scrollThrough(tester);
    expect(tester.takeException(), isNull);
  }, textScales: sensitiveTextScales);

  testWidgetsAcrossLayouts('vendors: edit sheet scrolls to Save', (tester, c) async {
    final l10n = lookupAppLocalizations(c.locale);
    await _pump(tester, c, const AdminVendorsScreen(), height: 640);

    await tester.tap(find.byKey(const ValueKey('admin_vendor_actions_v-pending')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.editStoreDetailsTooltip));
    await tester.pumpAndSettle();

    final save = find.text(l10n.saveButton);
    await tester.scrollUntilVisible(save, 120,
        scrollable: find
            .descendant(of: find.byKey(const ValueKey('admin_vendor_edit_form')), matching: find.byType(Scrollable))
            .first);
    expect(save.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, textScales: sensitiveTextScales);

  testWidgetsAcrossLayouts('promotions: card and its actions fit', (tester, c) async {
    await _pump(tester, c, const AdminPromotionsScreen());

    _expectReachable(tester, find.byKey(const ValueKey('admin_promotion_actions_p1')), c);
    final toggle = find.byKey(const ValueKey('admin_promotion_enabled_p1'));
    expect(toggle.hitTestable(), findsOneWidget);
    expect(tester.getRect(toggle).right, lessThanOrEqualTo(c.width));
  }, textScales: sensitiveTextScales);

  testWidgetsAcrossLayouts('promotions: edit form scrolls to Save', (tester, c) async {
    final l10n = lookupAppLocalizations(c.locale);
    await _pump(tester, c, const AdminPromotionsScreen(), height: 640);

    await tester.tap(find.byKey(const ValueKey('admin_promotion_actions_p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.editTooltip));
    await tester.pumpAndSettle();

    final save = find.text(l10n.saveButton);
    await tester.scrollUntilVisible(save, 120,
        scrollable: find
            .descendant(of: find.byKey(const ValueKey('admin_promotion_form')), matching: find.byType(Scrollable))
            .first);
    expect(save.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, textScales: sensitiveTextScales);

  testWidgetsAcrossLayouts('locations: all three tabs lay out', (tester, c) async {
    final l10n = lookupAppLocalizations(c.locale);
    await _pump(tester, c, const AdminLocationsScreen());

    for (final tab in [l10n.governoratesTabLabel, l10n.citiesTabLabel, l10n.neighborhoodsTabLabel]) {
      final tabFinder = find.widgetWithText(Tab, tab);
      await tester.ensureVisible(tabFinder);
      await tester.pumpAndSettle();
      await tester.tap(tabFinder);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: tab);
    }
    final toggle = find.byKey(const ValueKey('admin_neighborhood_enabled_mezzeh_villas'));
    expect(toggle.hitTestable(), findsOneWidget);
    expect(tester.getRect(toggle).right, lessThanOrEqualTo(c.width));
  }, textScales: sensitiveTextScales);

  testWidgetsAcrossLayouts('dashboard, orders, users, drivers, products and analytics lay out', (tester, c) async {
    for (final screen in const <Widget>[
      AdminDashboardScreen(),
      AdminOrdersScreen(),
      AdminUsersScreen(),
      AdminDriversScreen(),
      AdminProductsScreen(),
      AdminAnalyticsScreen(),
    ]) {
      await _pump(tester, c, screen);
      await _scrollThrough(tester);
      expect(tester.takeException(), isNull, reason: screen.runtimeType.toString());
    }
    // The orders list never shows a raw document id.
    await _pump(tester, c, const AdminOrdersScreen());
    expect(find.textContaining(_longId), findsNothing);
  }, textScales: sensitiveTextScales);

  testWidgetsAcrossLayouts('driver detail lays out', (tester, c) async {
    await _pump(tester, c, const AdminDriverDetailScreen(driverId: 'd1'));
    await _scrollThrough(tester);
    expect(tester.takeException(), isNull);
  }, textScales: sensitiveTextScales);
}
