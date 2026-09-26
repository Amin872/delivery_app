import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:delivery_app/features/customer/widgets/customer_order_tile.dart';
import 'package:delivery_app/features/customer/widgets/floating_order_button.dart';
import 'package:delivery_app/features/customer/widgets/home_floating_controls.dart';
import 'package:delivery_app/features/customer/widgets/menu_item_card.dart';
import 'package:delivery_app/features/customer/widgets/most_ordered_section.dart';
import 'package:delivery_app/features/customer/widgets/price_breakdown.dart';
import 'package:delivery_app/features/customer/widgets/profile_header.dart';
import 'package:delivery_app/features/customer/widgets/store_card.dart';
import 'package:delivery_app/features/customer/widgets/store_info_section.dart';
import 'package:delivery_app/features/customer/widgets/store_search_bar.dart';
import 'package:delivery_app/core/format/display_formatters.dart';
import 'package:delivery_app/models/approval_status.dart';
import 'package:delivery_app/models/order.dart';
import 'package:delivery_app/models/vendor.dart';

import '../../support/real_theme_harness.dart';

// Deliberately long names in both scripts, and large prices.
const _longAr = 'وجبة عائلية كبيرة مع بطاطا مقلية ومشروبات غازية وصلصات إضافية';
const _longEn = 'Family feast with extra-large fries, soft drinks and all the extra sauces';

MenuItem _item(String id, String name, double price) =>
    MenuItem(id: id, vendorId: 'v', name: name, price: price, available: true, description: name);

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
  pickupAddress: 'شارع بغداد، دمشق',
);

NumberFormat _money(LayoutConfig c) => NumberFormat.currency(locale: c.locale.languageCode, name: 'SYP');

Future<void> _pump(WidgetTester tester, LayoutConfig c, Widget child) async {
  await pumpWithRealTheme(
    tester,
    Scaffold(body: ListView(children: [child])),
    locale: c.locale,
    width: c.width,
    textScale: c.textScale,
  );
  // Plain pumps: network-image shimmers never settle.
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgetsAcrossLayouts('MenuItemCard with a long name and a large price', (tester, c) async {
    await _pump(tester, c, MenuItemCard(item: _item('a', c.locale.languageCode == 'ar' ? _longAr : _longEn, 1450000), currencyFormat: _money(c)));
  }, textScales: sensitiveTextScales);

  testWidgetsAcrossLayouts('MostOrderedSection cards', (tester, c) async {
    await _pump(
      tester,
      c,
      MostOrderedSection(
        title: 'الأكثر طلباً',
        items: [_item('a', _longAr, 145000), _item('b', _longEn, 1450000), _item('c', 'فلافل', 12000)],
        currencyFormat: _money(c),
        onAddToCart: (_) {},
        onViewAll: () {},
        onTapItem: (_) {},
      ),
    );
  }, textScales: sensitiveTextScales);

  testWidgetsAcrossLayouts('search bars and the floating bag button', (tester, c) async {
    await _pump(
      tester,
      c,
      Column(children: [
        StoreSearchBar(onTap: () {}),
        const SizedBox(height: 8),
        Row(children: [
          HomeFloatingBagButton(itemCount: 128, onTap: () {}),
          const SizedBox(width: 8),
          Expanded(child: HomeFloatingSearchBar(onTap: () {})),
        ]),
      ]),
    );
  }, textScales: sensitiveTextScales);

  testWidgetsAcrossLayouts('FloatingOrderButton with a large total', (tester, c) async {
    await _pump(tester, c, FloatingOrderButton(itemCount: 99, totalLabel: _money(c).format(14500000), onTap: () {}));
  }, textScales: sensitiveTextScales);

  testWidgetsAcrossLayouts('CustomerOrderTile with a long store name', (tester, c) async {
    await _pump(
      tester,
      c,
      CustomerOrderTile(
        order: DeliveryOrder(
          id: 'Xk3pQ9aB7cD2eF1gH4iJ',
          customerId: 'c',
          vendorId: 'v',
          items: const [],
          status: OrderStatus.readyForPickup,
          total: 1450000,
          deliveryAddress: 'المزرعة',
          createdAt: DateTime(2026, 9, 26, 14, 5),
          vendorName: _vendor.name,
        ),
      ),
    );
  }, textScales: sensitiveTextScales);

  testWidgetsAcrossLayouts('StoreCard, StoreInfoSection and PriceBreakdown', (tester, c) async {
    await _pump(
      tester,
      c,
      Column(children: [
        Builder(builder: (context) {
          // Sized exactly like its real parents (StoreCarousel/StoreListScreen).
          final width = c.width - 32;
          final height = width / storeCardImageAspectRatio + storeCardBodyHeightFor(MediaQuery.textScalerOf(context));
          return SizedBox(height: height, child: StoreCard(vendor: _vendor, currencyFormat: _money(c)));
        }),
        StoreInfoSection(vendor: _vendor, currencyFormat: _money(c)),
        const PriceBreakdown(subtotal: 1450000, deliveryFee: 10000, total: 1460000),
      ]),
    );
  }, textScales: sensitiveTextScales);

  testWidgetsAcrossLayouts('ProfileHeader shows the phone formatted and LTR-isolated', (tester, c) async {
    await _pump(
      tester,
      c,
      ProfileHeader(
        displayName: 'زبون تجريبي باسم طويل جداً للتجربة',
        email: 'a.very.long.customer.email.address@example.com',
        phoneNumber: '+963944123456',
        onEditTap: () {},
      ),
    );
    expect(find.text(formatPhone('+963944123456')), findsOneWidget);
  }, textScales: sensitiveTextScales);
}
