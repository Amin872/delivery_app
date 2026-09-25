import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:delivery_app/core/l10n/enum_labels.dart';
import 'package:delivery_app/core/providers/formatters_provider.dart';
import 'package:delivery_app/features/auth/providers/auth_provider.dart';
import 'package:delivery_app/features/customer/screens/customer_home_screen.dart' show firestoreServiceProvider;
import 'package:delivery_app/features/customer/screens/my_orders_screen.dart';
import 'package:delivery_app/features/customer/screens/order_history_screen.dart';
import 'package:delivery_app/features/customer/screens/order_tracking_screen.dart';
import 'package:delivery_app/features/customer/widgets/customer_order_tile.dart';
import 'package:delivery_app/l10n/app_localizations.dart';
import 'package:delivery_app/models/app_user.dart';
import 'package:delivery_app/models/order.dart';
import 'package:delivery_app/services/firestore_service.dart';

final _currency = NumberFormat.currency(locale: 'en', name: 'SYP');
final _dateFormat = DateFormat('yyyy-MM-dd HH:mm');
final _l10n = lookupAppLocalizations(const Locale('en'));

const _activeStatuses = [
  OrderStatus.pending,
  OrderStatus.accepted,
  OrderStatus.preparing,
  OrderStatus.readyForPickup,
  OrderStatus.driverAssigned,
  OrderStatus.pickedUp,
  OrderStatus.delivering,
];

DeliveryOrder _order(String id, OrderStatus status, {String? vendorName, int day = 1}) {
  return DeliveryOrder(
    id: id,
    customerId: 'customer-1',
    vendorId: 'vendor-1',
    items: const [],
    status: status,
    total: 1000,
    deliveryAddress: 'Mezzeh',
    vendorName: vendorName ?? 'Store $id',
    createdAt: DateTime(2026, 9, day, 12, 0),
  );
}

Future<void> _pump(WidgetTester tester, Widget screen, List<DeliveryOrder> orders) async {
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        customerOrdersProvider('customer-1').overrideWith((ref) => Stream.value(orders)),
        currencyFormatProvider.overrideWithValue(_currency),
        dateTimeFormatProvider.overrideWithValue(_dateFormat),
        // Only reached after tapping into OrderTrackingScreen — an empty
        // in-memory Firestore, so that screen just shows a missing order.
        firestoreServiceProvider.overrideWithValue(FirestoreService(firestore: FakeFirebaseFirestore())),
        currentAppUserProvider.overrideWith((ref) => Stream.value(
              const AppUser(id: 'customer-1', email: 'c@example.com', displayName: 'C', role: UserRole.customer),
            )),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: screen,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Vertical position of [finder], to check which section a row sits in.
double _top(WidgetTester tester, Finder finder) => tester.getTopLeft(finder).dy;

/// The app's own localized status label (the one the rows must show).
String _statusLabel(WidgetTester tester, OrderStatus status) =>
    orderStatusLabel(tester.element(find.byType(Scaffold).first), status);

void main() {
  test('isActiveCustomerOrder: everything but delivered/cancelled', () {
    for (final status in OrderStatus.values) {
      final terminal = status == OrderStatus.delivered || status == OrderStatus.cancelled;
      expect(isActiveCustomerOrder(_order('o', status)), !terminal, reason: status.name);
    }
  });

  group('MyOrdersScreen', () {
    const screen = MyOrdersScreen(customerId: 'customer-1');

    testWidgets('splits every active status above Past (delivered + cancelled)', (tester) async {
      final orders = [
        for (final (i, status) in _activeStatuses.indexed) _order('a$i', status),
        _order('done', OrderStatus.delivered),
        _order('gone', OrderStatus.cancelled),
      ];
      await _pump(tester, screen, orders);

      final pastHeader = _top(tester, find.byKey(const ValueKey('past_orders_header')));
      expect(_top(tester, find.byKey(const ValueKey('active_orders_header'))), lessThan(pastHeader));
      for (final (i, status) in _activeStatuses.indexed) {
        expect(_top(tester, find.text('Store a$i')), lessThan(pastHeader), reason: status.name);
        expect(find.text(_statusLabel(tester, status)), findsOneWidget, reason: status.name);
      }
      expect(_top(tester, find.text('Store done')), greaterThan(pastHeader));
      expect(_top(tester, find.text('Store gone')), greaterThan(pastHeader));
      expect(find.byType(CustomerOrderTile), findsNWidgets(9));
    });

    testWidgets('rows show the store name and date, never the raw order id', (tester) async {
      await _pump(tester, screen, [_order('order-xyz', OrderStatus.preparing, vendorName: 'Falafel House', day: 22)]);

      expect(find.text('Falafel House'), findsOneWidget);
      expect(find.text(_dateFormat.format(DateTime(2026, 9, 22, 12, 0))), findsOneWidget);
      expect(find.text(_currency.format(1000)), findsOneWidget);
      expect(find.textContaining('order-xyz'), findsNothing);
      expect(find.text(_l10n.orderLabel('order-xyz')), findsNothing);
    });

    testWidgets('an order without a stored store name gets the generic title', (tester) async {
      final legacy = DeliveryOrder(
        id: 'legacy-1',
        customerId: 'customer-1',
        vendorId: 'vendor-1',
        items: const [],
        status: OrderStatus.delivered,
        total: 500,
        deliveryAddress: 'Mezzeh',
        createdAt: DateTime(2026, 1, 1),
      );
      await _pump(tester, screen, [legacy]);

      expect(find.text(_l10n.orderFallbackTitle), findsOneWidget);
      expect(find.textContaining('legacy-1'), findsNothing);
    });

    testWidgets('empty sections show their own localized message', (tester) async {
      await _pump(tester, screen, [_order('done', OrderStatus.delivered)]);
      expect(find.text(_l10n.noActiveOrdersMessage), findsOneWidget);
      expect(find.text(_l10n.noPastOrdersMessage), findsNothing);

      await _pump(tester, screen, [_order('live', OrderStatus.delivering)]);
      expect(find.text(_l10n.noActiveOrdersMessage), findsNothing);
      expect(find.text(_l10n.noPastOrdersMessage), findsOneWidget);
    });

    testWidgets('no orders at all keeps the existing empty state', (tester) async {
      await _pump(tester, screen, const []);

      expect(find.text(_l10n.noOrdersMessage), findsOneWidget);
      expect(find.byKey(const ValueKey('active_orders_header')), findsNothing);
    });

    testWidgets('tapping an order opens its OrderTrackingScreen', (tester) async {
      await _pump(tester, screen, [_order('o7', OrderStatus.accepted)]);

      await tester.tap(find.text('Store o7'));
      await tester.pumpAndSettle();

      expect(find.byType(OrderTrackingScreen), findsOneWidget);
      expect(tester.widget<OrderTrackingScreen>(find.byType(OrderTrackingScreen)).orderId, 'o7');
    });
  });

  group('OrderHistoryScreen', () {
    const screen = OrderHistoryScreen(customerId: 'customer-1');

    testWidgets('lists only delivered and cancelled orders, with the shared row', (tester) async {
      await _pump(tester, screen, [
        for (final (i, status) in _activeStatuses.indexed) _order('a$i', status),
        _order('done', OrderStatus.delivered),
        _order('gone', OrderStatus.cancelled),
      ]);

      expect(find.byType(CustomerOrderTile), findsNWidgets(2));
      expect(find.text('Store done'), findsOneWidget);
      expect(find.text('Store gone'), findsOneWidget);
      for (var i = 0; i < _activeStatuses.length; i++) {
        expect(find.text('Store a$i'), findsNothing);
      }
      expect(find.text(_statusLabel(tester, OrderStatus.delivered)), findsOneWidget);
      expect(find.text(_statusLabel(tester, OrderStatus.cancelled)), findsOneWidget);
    });

    testWidgets('no finished orders shows the existing empty state', (tester) async {
      await _pump(tester, screen, [_order('live', OrderStatus.pending)]);
      expect(find.text(_l10n.noOrdersMessage), findsOneWidget);
    });

    testWidgets('tapping an order opens its OrderTrackingScreen', (tester) async {
      await _pump(tester, screen, [_order('done', OrderStatus.delivered)]);

      await tester.tap(find.text('Store done'));
      await tester.pumpAndSettle();

      expect(tester.widget<OrderTrackingScreen>(find.byType(OrderTrackingScreen)).orderId, 'done');
    });
  });
}
