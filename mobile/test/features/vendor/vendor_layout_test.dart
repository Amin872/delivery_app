import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:mocktail/mocktail.dart';

import 'package:delivery_app/core/format/display_formatters.dart';
import 'package:delivery_app/core/theme/app_sizes.dart';
import 'package:delivery_app/features/customer/screens/customer_home_screen.dart' show allCitiesProvider;
import 'package:delivery_app/features/customer/screens/vendor_menu_screen.dart' show vendorMenuProvider;
import 'package:delivery_app/features/driver/screens/driver_home_screen.dart' show functionsServiceProvider;
import 'package:delivery_app/features/vendor/screens/menu_management_screen.dart';
import 'package:delivery_app/features/vendor/screens/vendor_dashboard_screen.dart';
import 'package:delivery_app/features/vendor/screens/vendor_order_detail_screen.dart';
import 'package:delivery_app/features/vendor/screens/vendor_stats_screen.dart';
import 'package:delivery_app/features/vendor/widgets/vendor_order_card.dart';
import 'package:delivery_app/l10n/app_localizations.dart';
import 'package:delivery_app/models/approval_status.dart';
import 'package:delivery_app/models/city.dart';
import 'package:delivery_app/models/order.dart';
import 'package:delivery_app/models/vendor.dart';
import 'package:delivery_app/services/functions_service.dart';

import '../../support/real_theme_harness.dart';

// Realistic worst cases: a full-length Firestore id, long Arabic and
// English names, seven- and eight-digit SYP amounts, a long mixed address.
const _longId = 'Xk9QpL2mZt7RwY4bNcV1';
const _longAr = 'شاورما دجاج عائلية كبيرة مع بطاطا مقلية وثومية ومخللات إضافية';
const _longEn = 'Family-size chicken shawarma platter with fries, garlic sauce and pickles';
const _longAddress = 'المزرعة، شارع عبد الرحمن الشهبندر، بناء 12، الطابق 3 — Building 12, 3rd floor';

const _vendor = Vendor(
  id: 'v',
  ownerId: 'v',
  name: 'مطعم الشام الكبير للمأكولات الشرقية والمشاوي الدمشقية',
  description: '',
  isOpen: true,
  approvalStatus: ApprovalStatus.approved,
  deliveryFee: 10000,
  etaMinMinutes: 25,
  etaMaxMinutes: 40,
  minimumOrderAmount: 150000,
  openTime: '10:00',
  closeTime: '23:30',
  pickupAddress: 'المزرعة، شارع الشهبندر',
  pickupLatitude: 33.5225,
  pickupLongitude: 36.2805,
);

DeliveryOrder _order(String id, OrderStatus status, double total, {String? driverId}) => DeliveryOrder(
      id: id,
      customerId: 'c',
      vendorId: 'v',
      driverId: driverId,
      items: const [
        OrderItem(menuItemId: 'a', name: _longAr, quantity: 12, unitPrice: 1250000),
        OrderItem(menuItemId: 'b', name: _longEn, quantity: 1, unitPrice: 3000),
      ],
      status: status,
      total: total,
      subtotal: total - 10000,
      deliveryFee: 10000,
      deliveryAddress: _longAddress,
      deliveryLatitude: 33.513801234,
      deliveryLongitude: 36.276501234,
      deliveryInstructions: 'الباب الأيسر بعد المصعد، يرجى الاتصال قبل الوصول بخمس دقائق',
      driverNote: 'Call on arrival',
      createdAt: DateTime(2026, 9, 22, 18, 30),
    );

final _orders = [
  _order(_longId, OrderStatus.pending, 15013000),
  _order('order-2', OrderStatus.accepted, 25000),
  _order('order-3', OrderStatus.preparing, 125000),
  _order('order-4', OrderStatus.readyForPickup, 8500),
  _order('order-5', OrderStatus.driverAssigned, 99999999, driverId: 'd'),
  _order('order-6', OrderStatus.delivered, 42000),
  _order('order-7', OrderStatus.cancelled, 12500),
];

const _menu = [
  MenuItem(id: 'a', vendorId: 'v', name: _longAr, price: 1250000, available: true),
  MenuItem(id: 'b', vendorId: 'v', name: _longEn, price: 12500000, available: false),
  MenuItem(id: 'c', vendorId: 'v', name: 'فلافل', price: 3000, available: true),
];

class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

class _NoCallFunctions extends FunctionsService {
  _NoCallFunctions() : super(functions: _MockFirebaseFunctions());

  @override
  Future<String> getOrderContact(String orderId, ContactTarget target) async => '+963944123456';
}

List<Override> _overrides({Vendor vendor = _vendor}) => [
      vendorSelfProvider('v').overrideWith((ref) => Stream.value(vendor)),
      vendorOrdersProvider('v').overrideWith((ref) => Stream.value(_orders)),
      vendorMenuProvider('v').overrideWith((ref) => Stream.value(_menu)),
      allCitiesProvider.overrideWith((ref) => Stream.value(const <CityOption>[])),
      functionsServiceProvider.overrideWithValue(_NoCallFunctions()),
    ];

Future<void> _pump(WidgetTester tester, LayoutConfig c, Widget screen, {Vendor vendor = _vendor}) async {
  await pumpWithRealTheme(tester, screen,
      locale: c.locale, width: c.width, height: 800, textScale: c.textScale, overrides: _overrides(vendor: vendor));
  await tester.pumpAndSettle();
}

String _money(LayoutConfig c, num amount) =>
    NumberFormat.currency(locale: c.locale.languageCode, name: 'SYP').format(amount);

/// [finder] is laid out on exactly one line (a price split across lines
/// reads as two numbers).
void _expectSingleLine(WidgetTester tester, Finder finder) {
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: paragraph.text.toPlainText().length));
  expect(boxes.map((b) => b.top.round()).toSet().length, 1, reason: '"${paragraph.text.toPlainText()}" wrapped');
}

/// [finder] is tappable, fully on screen, and at least the 48px target.
void _expectReachable(WidgetTester tester, Finder finder, LayoutConfig c) {
  expect(finder.hitTestable(), findsOneWidget);
  final rect = tester.getRect(finder);
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(c.width));
  expect(rect.height, greaterThanOrEqualTo(AppSizes.minTapTarget - 0.5));
}

/// The IconButton behind [tooltip] (its Tooltip only wraps the 40px
/// visual; the padded tap target is the IconButton itself).
Finder _iconButton(Finder tooltip) => find.ancestor(of: tooltip, matching: find.byType(IconButton)).first;

/// No text anywhere shows a raw document id.
void _expectNoRawOrderId() {
  expect(find.textContaining(_longId), findsNothing);
  expect(find.textContaining('order-'), findsNothing);
}

void main() {
  testWidgetsAcrossLayouts('dashboard: AppBar actions, filter and order cards', (tester, c) async {
    final l10n = lookupAppLocalizations(c.locale);
    await _pump(tester, c, const VendorDashboardScreen(vendorId: 'v'));

    // AppBar: title still readable, every action on screen and tappable.
    final title = find.descendant(of: find.byType(AppBar), matching: find.text(l10n.incomingOrdersTitle));
    expect(tester.getSize(title).width, greaterThan(40));
    final openSwitch = find.byKey(const ValueKey('vendor_open_switch'));
    expect(openSwitch.hitTestable(), findsOneWidget);
    expect(tester.getRect(openSwitch).right, lessThanOrEqualTo(c.width));
    _expectReachable(tester, _iconButton(find.byTooltip(l10n.menuManagementTitle)), c);
    _expectReachable(tester, find.byKey(const ValueKey('vendor_more_menu')), c);

    // First card: short reference (bidi-isolated), status chip, total on one
    // line, both actions reachable.
    _expectNoRawOrderId();
    final card = find.byKey(const ValueKey('vendor_order_$_longId'));
    expect(find.descendant(of: card, matching: find.text(l10n.orderLabel(displayOrderId(_longId)))), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text(l10n.orderStatusPending)), findsOneWidget);
    _expectSingleLine(tester, find.descendant(of: card, matching: find.text(_money(c, 15013000))));
    _expectReachable(tester, find.descendant(of: card, matching: find.byType(FilledButton)), c);
    _expectReachable(tester, _iconButton(find.descendant(of: card, matching: find.byTooltip(l10n.cancelOrderButton))), c);

    // Active holds everything not yet delivered/cancelled; Completed the rest.
    final activeList = find.descendant(
        of: find.byKey(const ValueKey('vendor_orders_active')), matching: find.byType(Scrollable));
    await tester.scrollUntilVisible(find.byKey(const ValueKey('vendor_order_order-5')), 300,
        scrollable: activeList.first);
    await tester.drag(activeList.first, const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('vendor_order_order-5')), findsOneWidget);
    expect(find.byKey(const ValueKey('vendor_order_order-6')), findsNothing);
    expect(find.byKey(const ValueKey('vendor_order_order-7')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('vendor_filter_completed')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('vendor_order_order-6')), findsOneWidget);
    expect(find.byKey(const ValueKey('vendor_order_order-7')), findsOneWidget);
    expect(find.byKey(const ValueKey('vendor_order_$_longId')), findsNothing);
    _expectNoRawOrderId();
  }, textScales: sensitiveTextScales);

  testWidgetsAcrossLayouts('dashboard: "more" menu holds every secondary action', (tester, c) async {
    final l10n = lookupAppLocalizations(c.locale);
    await _pump(tester, c, const VendorDashboardScreen(vendorId: 'v'));
    await tester.tap(find.byKey(const ValueKey('vendor_more_menu')));
    await tester.pumpAndSettle();
    for (final label in [
      l10n.editStoreDetailsTooltip,
      l10n.changeStorefrontPhotoTooltip,
      l10n.vendorStatsTitle,
      l10n.languageToggleTooltip,
      l10n.signOutTooltip,
    ]) {
      expect(find.text(label).hitTestable(), findsOneWidget, reason: label);
      expect(tester.getRect(find.text(label)).right, lessThanOrEqualTo(c.width));
    }
  }, textScales: sensitiveTextScales);

  testWidgetsAcrossLayouts('order card: every vendor status in a narrow list', (tester, c) async {
    await pumpWithRealTheme(
      tester,
      Scaffold(
        body: ListView(children: [
          for (final order in _orders) VendorOrderCard(key: ValueKey(order.id), order: order, onTap: () {}),
        ]),
      ),
      locale: c.locale,
      width: c.width,
      height: 3000,
      textScale: c.textScale,
    );
    await tester.pumpAndSettle();
    _expectNoRawOrderId();
    for (final order in _orders) {
      final card = find.byKey(ValueKey(order.id));
      expect(card, findsOneWidget);
      _expectSingleLine(tester, find.descendant(of: card, matching: find.text(_money(c, order.total))));
    }
  }, textScales: sensitiveTextScales);

  testWidgetsAcrossLayouts('order detail: long content, formatted id and coordinates', (tester, c) async {
    final l10n = lookupAppLocalizations(c.locale);
    await _pump(tester, c, const VendorOrderDetailScreen(vendorId: 'v', orderId: _longId));

    _expectNoRawOrderId();
    expect(find.text(l10n.orderLabel(displayOrderId(_longId))), findsOneWidget);
    expect(find.text(l10n.orderStatusPending), findsOneWidget);
    final total = find.text(_money(c, 15013000), skipOffstage: false);
    await tester.scrollUntilVisible(total, 200, scrollable: find.byType(Scrollable).first);
    _expectSingleLine(tester, total);

    final coordinates = find.text(formatCoordinates(33.513801234, 36.276501234), skipOffstage: false);
    await tester.scrollUntilVisible(coordinates, 200, scrollable: find.byType(Scrollable).first);
    expect(coordinates, findsOneWidget);

    final advance = find.byType(FilledButton);
    await tester.scrollUntilVisible(advance, 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    _expectReachable(tester, advance, c);
  }, textScales: sensitiveTextScales);

  testWidgetsAcrossLayouts('order detail: not-found state', (tester, c) async {
    final l10n = lookupAppLocalizations(c.locale);
    await _pump(tester, c, const VendorOrderDetailScreen(vendorId: 'v', orderId: 'missing'));
    expect(find.text(l10n.orderNotFoundMessage), findsOneWidget);
  });

  testWidgetsAcrossLayouts('menu management: names get real width, controls stay reachable', (tester, c) async {
    final l10n = lookupAppLocalizations(c.locale);
    await _pump(tester, c, const MenuManagementScreen(vendorId: 'v'));

    for (final item in _menu) {
      final card = find.byKey(ValueKey('menu_item_${item.id}'));
      await tester.ensureVisible(card);
      await tester.pumpAndSettle();
      final name = find.descendant(of: card, matching: find.text(item.name));
      // The name may use well over a third of the screen (it had 36px at
      // 320 before) and the row stays compact.
      expect(tester.renderObject<RenderParagraph>(name).constraints.maxWidth, greaterThan(c.width * 0.35),
          reason: item.name);
      expect(tester.getSize(card).height, lessThan(260), reason: item.name);
      _expectSingleLine(tester, find.descendant(of: card, matching: find.text(_money(c, item.price))));
      expect(
          find.descendant(
              of: card, matching: find.text(item.available ? l10n.availableLabel : l10n.unavailableLabel)),
          findsOneWidget);
      _expectReachable(tester, find.byKey(ValueKey('menu_item_actions_${item.id}')), c);
      expect(find.byKey(ValueKey('menu_item_available_${item.id}')).hitTestable(), findsOneWidget);
    }

    await tester.tap(find.byKey(const ValueKey('menu_item_actions_a')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.editTooltip).hitTestable(), findsOneWidget);
    expect(find.text(l10n.deleteTooltip).hitTestable(), findsOneWidget);
  }, textScales: sensitiveTextScales);

  testWidgetsAcrossLayouts('menu item form: scrolls to Save with the keyboard open', (tester, c) async {
    final l10n = lookupAppLocalizations(c.locale);
    await _pump(tester, c, const MenuManagementScreen(vendorId: 'v'));
    await tester.tap(find.byKey(const ValueKey('menu_item_actions_a')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.editTooltip));
    await tester.pumpAndSettle();

    // Existing price shown as an editable amount, not "1250000.00".
    expect(find.text('1250000'), findsOneWidget);

    // A phone keyboard takes ~40% of the screen.
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    final save = find.byKey(const ValueKey('menu_item_save_button'));
    await tester.scrollUntilVisible(save, 150,
        scrollable: find.descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable)).first);
    await tester.pumpAndSettle();
    // GradientButton's outermost render object is an entrance-animation
    // transform, which never reports itself in a hit test — check its label.
    expect(find.descendant(of: save, matching: find.text(l10n.saveButton)).hitTestable(), findsOneWidget);
    expect(tester.getRect(save).bottom, lessThanOrEqualTo(800 - 320));
  }, textScales: sensitiveTextScales);

  testWidgetsAcrossLayouts('store details: formatted amounts and pin, Save reachable', (tester, c) async {
    final l10n = lookupAppLocalizations(c.locale);
    await _pump(tester, c, const VendorDashboardScreen(vendorId: 'v'));
    await tester.tap(find.byKey(const ValueKey('vendor_more_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.editStoreDetailsTooltip));
    await tester.pumpAndSettle();

    expect(find.text('10000'), findsOneWidget); // delivery fee, not "10000.00"
    expect(find.text('150000', skipOffstage: false), findsOneWidget); // minimum order
    final sheetScroll = find.descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable)).first;
    final pin = find.text(l10n.pickupPinSetLabel(formatCoordinates(33.5225, 36.2805)), skipOffstage: false);
    await tester.scrollUntilVisible(pin, 150, scrollable: sheetScroll);
    expect(pin, findsOneWidget);

    final save = find.text(l10n.saveButton);
    await tester.scrollUntilVisible(save, 150, scrollable: sheetScroll);
    await tester.pumpAndSettle();
    expect(save.hitTestable(), findsOneWidget);
  }, textScales: sensitiveTextScales);

  testWidgetsAcrossLayouts('stats: large counts and sales totals', (tester, c) async {
    final l10n = lookupAppLocalizations(c.locale);
    await pumpWithRealTheme(tester, const VendorStatsScreen(vendorId: 'v'),
        locale: c.locale,
        width: c.width,
        height: 800,
        textScale: c.textScale,
        overrides: [
          vendorStatsProvider('v').overrideWith((ref) async => const VendorStats(
                orderCount: 1234567,
                salesTotal: 987654321,
                topItems: [MapEntry(_longAr, 123456), MapEntry(_longEn, 98765)],
              )),
        ]);
    await tester.pumpAndSettle();

    final count = NumberFormat.decimalPattern(c.locale.languageCode);
    expect(find.text(count.format(1234567)), findsOneWidget);
    expect(find.text(count.format(123456)), findsOneWidget);
    final sales = find.text(_money(c, 987654321));
    _expectSingleLine(tester, sales);
    final tile = tester.getRect(find.byKey(const ValueKey('vendor_stat_sales')));
    final value = tester.getRect(sales);
    expect(value.left, greaterThanOrEqualTo(tile.left));
    expect(value.right, lessThanOrEqualTo(tile.right));
    expect(find.text(l10n.topItemsTitle), findsOneWidget);
  }, textScales: sensitiveTextScales);

  for (final status in [ApprovalStatus.pending, ApprovalStatus.rejected]) {
    testWidgetsAcrossLayouts('approval view: ${status.name}', (tester, c) async {
      final l10n = lookupAppLocalizations(c.locale);
      await _pump(tester, c, const VendorDashboardScreen(vendorId: 'v'),
          vendor: Vendor(
            id: 'v',
            ownerId: 'v',
            name: _vendor.name,
            description: '',
            isOpen: false,
            approvalStatus: status,
          ));
      final isPending = status == ApprovalStatus.pending;
      expect(find.byKey(ValueKey('vendor_approval_${status.name}')), findsOneWidget);
      expect(find.text(isPending ? l10n.vendorStoreSetupTitle : l10n.vendorStoreTitle), findsOneWidget);
      expect(find.text(l10n.incomingOrdersTitle), findsNothing);
      expect(find.text(isPending ? l10n.vendorStatusPending : l10n.vendorStatusRejected), findsOneWidget);
      _expectReachable(tester, find.byKey(const ValueKey('vendor_more_menu')), c);
      if (isPending) _expectReachable(tester, _iconButton(find.byTooltip(l10n.menuManagementTitle)), c);
    }, textScales: sensitiveTextScales);
  }
}
