import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:mocktail/mocktail.dart';

import 'package:delivery_app/core/errors/app_exception.dart';
import 'package:delivery_app/core/format/display_formatters.dart';
import 'package:delivery_app/core/providers/formatters_provider.dart';
import 'package:delivery_app/features/driver/screens/driver_home_screen.dart' show functionsServiceProvider;
import 'package:delivery_app/features/vendor/screens/vendor_dashboard_screen.dart';
import 'package:delivery_app/features/vendor/screens/vendor_order_detail_screen.dart';
import 'package:delivery_app/l10n/app_localizations.dart';
import 'package:delivery_app/models/order.dart';
import 'package:delivery_app/services/functions_service.dart';

class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

/// Records which participant the vendor screen asks the contact resolver
/// for; [error] makes it refuse instead.
class _RecordingFunctions extends FunctionsService {
  _RecordingFunctions({this.error}) : super(functions: _MockFirebaseFunctions());

  final Object? error;
  final targets = <ContactTarget>[];

  @override
  Future<String> getOrderContact(String orderId, ContactTarget target) async {
    targets.add(target);
    if (error != null) throw error!;
    return '+963 900 000 001';
  }
}

final _currency = NumberFormat.currency(locale: 'en', name: 'SYP');

DeliveryOrder _order({
  String id = 'order-1',
  OrderStatus status = OrderStatus.pending,
  double total = 8500,
  double? subtotal = 7000,
  double? deliveryFee = 1500,
  String? instructions = 'Ring twice',
  String? driverNote = 'Leave at door',
}) {
  return DeliveryOrder(
    id: id,
    customerId: 'customer-1',
    vendorId: 'vendor-1',
    items: const [
      OrderItem(menuItemId: 'falafel', name: 'Falafel wrap', quantity: 2, unitPrice: 2000),
      OrderItem(menuItemId: 'hummus', name: 'Hummus', quantity: 1, unitPrice: 3000),
    ],
    status: status,
    total: total,
    subtotal: subtotal,
    deliveryFee: deliveryFee,
    deliveryAddress: 'Mezzeh, Building 4',
    deliveryLatitude: 33.5,
    deliveryLongitude: 36.25,
    deliveryInstructions: instructions,
    driverNote: driverNote,
    createdAt: DateTime(2026, 9, 22, 18, 30),
  );
}

Future<void> _pump(
  WidgetTester tester,
  List<DeliveryOrder> orders, {
  String orderId = 'order-1',
  _RecordingFunctions? functions,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        vendorOrdersProvider('vendor-1').overrideWith((ref) => Stream.value(orders)),
        currencyFormatProvider.overrideWithValue(_currency),
        dateTimeFormatProvider.overrideWithValue(DateFormat('yyyy-MM-dd HH:mm')),
        functionsServiceProvider.overrideWithValue(functions ?? _RecordingFunctions()),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: VendorOrderDetailScreen(vendorId: 'vendor-1', orderId: orderId),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders items, quantities, line totals and the price breakdown', (tester) async {
    await _pump(tester, [_order()]);

    expect(find.text('Order details'), findsOneWidget);
    expect(find.text('Falafel wrap'), findsOneWidget);
    expect(find.text('Hummus'), findsOneWidget);
    expect(find.text('2 × ${_currency.format(2000)}'), findsOneWidget);
    expect(find.text('1 × ${_currency.format(3000)}'), findsOneWidget);
    // Line totals: 2 x 2000 and 1 x 3000.
    expect(find.text(_currency.format(4000)), findsOneWidget);
    expect(find.text(_currency.format(3000)), findsOneWidget);

    expect(find.text('Subtotal'), findsOneWidget);
    expect(find.text(_currency.format(7000)), findsOneWidget);
    expect(find.text('Delivery fee'), findsOneWidget);
    expect(find.text(_currency.format(1500)), findsOneWidget);
    expect(find.text('Total'), findsOneWidget);
    expect(find.text(_currency.format(8500)), findsOneWidget);
  });

  testWidgets('renders status, placed time, address, instructions and driver note', (tester) async {
    await _pump(tester, [_order()]);

    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('2026-09-22 18:30'), findsOneWidget);
    expect(find.text('Mezzeh, Building 4'), findsOneWidget);
    expect(find.text(formatCoordinates(33.5, 36.25)), findsOneWidget);
    expect(find.text('Ring twice'), findsOneWidget);
    expect(find.text('Leave at door'), findsOneWidget);
  });

  testWidgets('a legacy order falls back to subtotal = total and a 0 delivery fee', (tester) async {
    await _pump(tester, [_order(total: 7000, subtotal: null, deliveryFee: null)]);

    // Subtotal and total both show 7000; the fee shows 0.
    expect(find.text(_currency.format(7000)), findsNWidgets(2));
    expect(find.text(_currency.format(0)), findsOneWidget);
  });

  testWidgets('omits empty instructions and driver note rows', (tester) async {
    await _pump(tester, [_order(instructions: null, driverNote: '')]);

    expect(find.text('Delivery instructions'), findsNothing);
    expect(find.text('Driver note'), findsNothing);
  });

  testWidgets('shows the vendor actions for an order the vendor can still act on', (tester) async {
    await _pump(tester, [_order(status: OrderStatus.accepted)]);

    // The actions sit at the bottom of the scrollable detail list.
    await tester.scrollUntilVisible(find.text('Cancel order'), 200);
    expect(find.text('Move to Preparing'), findsOneWidget);
    expect(find.text('Cancel order'), findsOneWidget);
  });

  testWidgets('shows no actions once the order has left the vendor', (tester) async {
    await _pump(tester, [_order(status: OrderStatus.pickedUp)]);

    await tester.scrollUntilVisible(find.text('Leave at door'), 200);
    await tester.drag(find.byType(ListView), const Offset(0, -1000));
    await tester.pumpAndSettle();
    expect(find.textContaining('Move to', skipOffstage: false), findsNothing);
    expect(find.text('Cancel order', skipOffstage: false), findsNothing);
  });

  testWidgets('shows a not-found message for an order that is no longer listed', (tester) async {
    await _pump(tester, [_order()], orderId: 'missing');

    expect(find.text('This order is no longer in your list.'), findsOneWidget);
  });

  group('contact (Phase 27)', () {
    DeliveryOrder withStatus(OrderStatus status, {String? driverId}) => DeliveryOrder(
          id: 'order-1',
          customerId: 'customer-1',
          vendorId: 'vendor-1',
          driverId: driverId,
          items: const [],
          status: status,
          total: 10,
          deliveryAddress: 'addr',
          createdAt: DateTime(2026, 9, 22),
        );

    Future<void> scrollDown(WidgetTester tester) async {
      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tester.pumpAndSettle();
    }

    final customer = find.byKey(const ValueKey('vendor_call_customer'), skipOffstage: false);
    final driver = find.byKey(const ValueKey('vendor_call_driver'), skipOffstage: false);

    for (final status in [OrderStatus.pending, OrderStatus.accepted, OrderStatus.preparing, OrderStatus.readyForPickup]) {
      testWidgets('${status.name}: call customer only', (tester) async {
        await _pump(tester, [withStatus(status)]);
        await scrollDown(tester);

        expect(customer, findsOneWidget);
        expect(driver, findsNothing);
      });
    }

    testWidgets('driverAssigned: call customer and call driver', (tester) async {
      await _pump(tester, [withStatus(OrderStatus.driverAssigned, driverId: 'driver-1')]);
      await scrollDown(tester);

      expect(customer, findsOneWidget);
      expect(driver, findsOneWidget);
    });

    testWidgets('pickedUp: call driver only', (tester) async {
      await _pump(tester, [withStatus(OrderStatus.pickedUp, driverId: 'driver-1')]);
      await scrollDown(tester);

      expect(customer, findsNothing);
      expect(driver, findsOneWidget);
    });

    for (final status in [OrderStatus.delivering, OrderStatus.delivered, OrderStatus.cancelled]) {
      testWidgets('${status.name}: no call buttons', (tester) async {
        await _pump(tester, [withStatus(status, driverId: 'driver-1')]);
        await scrollDown(tester);

        expect(customer, findsNothing);
        expect(driver, findsNothing);
      });
    }

    testWidgets('each button asks the resolver for its own target', (tester) async {
      final functions = _RecordingFunctions(error: const AppException('phone-unavailable'));
      await _pump(tester, [withStatus(OrderStatus.driverAssigned, driverId: 'driver-1')], functions: functions);
      await scrollDown(tester);

      await tester.tap(find.text('Call customer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Call driver'));
      await tester.pumpAndSettle();

      expect(functions.targets, [ContactTarget.customer, ContactTarget.driver]);
    });

    testWidgets('no phone on file: localized message', (tester) async {
      final functions = _RecordingFunctions(error: const AppException('phone-unavailable'));
      await _pump(tester, [withStatus(OrderStatus.pending)], functions: functions);
      await scrollDown(tester);

      await tester.tap(find.text('Call customer'));
      await tester.pumpAndSettle();

      expect(find.text('No phone number is available for this person.'), findsOneWidget);
    });
  });
}
