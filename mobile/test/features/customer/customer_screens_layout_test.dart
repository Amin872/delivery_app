import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:delivery_app/features/auth/providers/auth_provider.dart';
import 'package:delivery_app/features/customer/providers/cart_provider.dart';
import 'package:delivery_app/features/customer/screens/cart_screen.dart';
import 'package:delivery_app/features/customer/screens/customer_home_screen.dart'
    show allCitiesProvider, firestoreServiceProvider;
import 'package:delivery_app/features/customer/screens/delivery_addresses_screen.dart';
import 'package:delivery_app/features/customer/screens/search_screen.dart';
import 'package:delivery_app/features/customer/screens/vendor_menu_screen.dart';
import 'package:delivery_app/l10n/app_localizations.dart';
import 'package:delivery_app/models/app_user.dart';
import 'package:delivery_app/models/approval_status.dart';
import 'package:delivery_app/models/city.dart';
import 'package:delivery_app/models/vendor.dart';
import 'package:delivery_app/services/firestore_service.dart';

import '../../support/real_theme_harness.dart';

const _longAr = 'وجبة عائلية كبيرة مع بطاطا مقلية ومشروبات غازية وصلصات إضافية';
const _longEn = 'Family feast with extra-large fries, soft drinks and all the extra sauces';

const _vendor = Vendor(
  id: 'v',
  ownerId: 'v',
  name: 'مطعم الشام للمأكولات الشرقية والغربية والحلويات',
  description: 'Shawarma, grills and sweets — a long description that should wrap cleanly on narrow phones.',
  isOpen: true,
  approvalStatus: ApprovalStatus.approved,
  ratingSum: 27,
  ratingCount: 6,
  category: VendorCategory.restaurants,
  deliveryFee: 10000,
  etaMinMinutes: 25,
  etaMaxMinutes: 40,
  minimumOrderAmount: 150000,
  openTime: '10:00',
  closeTime: '23:59',
);

Future<FakeFirebaseFirestore> _seed() async {
  final db = FakeFirebaseFirestore();
  await db.collection('vendors').doc('v').set(_vendor.toMap());
  for (final (id, name, price, section) in [
    ('a', _longAr, 145000.0, 'وجبات'),
    ('b', _longEn, 1450000.0, 'Meals'),
    ('c', 'فلافل', 12000.0, 'سندويشات'),
  ]) {
    await db.collection('vendors').doc('v').collection('menuItems').doc(id).set(
        {'vendorId': 'v', 'name': name, 'price': price, 'available': true, 'section': section, 'description': name, 'orderCount': 5});
  }
  await db.collection('users').doc('c').collection('addresses').doc('home').set({
    'userId': 'c',
    'label': 'المنزل — بيت العائلة في المزرعة',
    'latitude': 33.5225,
    'longitude': 36.2805,
    'cityId': 'damascus',
    'addressText': 'المزرعة، شارع عبد الرحمن الشهبندر، بناء 12، الطابق 3، جانب الصيدلية',
    'deliveryInstructions': 'الباب الأيسر بعد المصعد، يرجى الاتصال قبل الوصول بخمس دقائق',
    'driverNote': 'Call +963944123456 on arrival',
    'phone': '+963944123456',
    'isDefault': true,
    'createdAt': 1,
    'updatedAt': 1,
  });
  return db;
}

List<Override> _overrides(FakeFirebaseFirestore db) => [
      firestoreServiceProvider.overrideWithValue(FirestoreService(firestore: db)),
      allCitiesProvider.overrideWith((ref) => Stream.value(const <CityOption>[])),
      currentAppUserProvider.overrideWith((ref) => Stream.value(
          const AppUser(id: 'c', email: 'c@example.com', displayName: 'C', role: UserRole.customer))),
      cartProvider.overrideWith((ref) => CartController()
        ..addItem('v', _vendor.name, const MenuItem(id: 'a', vendorId: 'v', name: _longAr, price: 145000, available: true))
        ..addItem('v', _vendor.name, const MenuItem(id: 'b', vendorId: 'v', name: _longEn, price: 1450000, available: true))),
    ];

Future<void> _pump(WidgetTester tester, LayoutConfig c, Widget screen) async {
  final db = await _seed();
  await pumpWithRealTheme(tester, screen,
      locale: c.locale, width: c.width, height: 800, textScale: c.textScale, overrides: _overrides(db));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Scrolls [finder] into view: until it exists, then twice with a layout
/// pass in between — a lazy
/// list's scroll extent is an estimate until the children below have been
/// laid out, so one jump can stop short.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  // Not built yet (below the lazy list's cache area): scroll until it is.
  await tester.scrollUntilVisible(finder, 150, scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.ensureVisible(finder);
  await tester.pump();
}

void main() {
  testWidgetsAcrossLayouts('CartScreen: lines, totals, address tile and Place order', (tester, c) async {
    await _pump(tester, c, const CartScreen());
    // Checked first, while both lines are on screen. Prices never wrap mid-number (a wrapped price has more than one line).
    for (final price in [145000, 1450000]) {
      final text = find.text(NumberFormat.currency(locale: c.locale.languageCode, name: 'SYP').format(price));
      expect(text, findsWidgets);
      final paragraph = tester.renderObject<RenderParagraph>(text.first);
      expect(paragraph.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: paragraph.text.toPlainText().length))
              .map((b) => b.top.round()).toSet().length,
          1,
          reason: 'price wrapped onto several lines');
      // ...and is shown at full size, not shrunk to fit.
      expect(tester.getRect(text.first).width, closeTo(tester.getSize(text.first).width, 0.5),
          reason: 'price was scaled down to fit');
    }
    final l10n = lookupAppLocalizations(c.locale);
    await _reveal(tester, find.text(l10n.changeLocationButton));
    expect(find.text(l10n.changeLocationButton).hitTestable(), findsOneWidget);
    await _reveal(tester, find.byKey(const ValueKey('cart_place_order_button')));
    expect(find.byKey(const ValueKey('cart_place_order_button')).hitTestable(), findsOneWidget);
    await tester.pump(const Duration(seconds: 2)); // let entrance animations finish
  }, textScales: sensitiveTextScales);

  testWidgetsAcrossLayouts('DeliveryAddressesScreen with a long address and notes', (tester, c) async {
    await _pump(tester, c, const DeliveryAddressesScreen(customerId: 'c'));
    expect(find.textContaining('المزرعة'), findsWidgets);
  }, textScales: sensitiveTextScales);

  testWidgetsAcrossLayouts('VendorMenuScreen with long item names', (tester, c) async {
    await _pump(tester, c, const VendorMenuScreen(vendor: _vendor));
    await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -600));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }, textScales: sensitiveTextScales);

  testWidgetsAcrossLayouts('SearchScreen with a query that matches long names', (tester, c) async {
    await _pump(tester, c, const SearchScreen());
    await tester.enterText(find.byType(TextField), 'وجبة');
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }, textScales: sensitiveTextScales);
}
