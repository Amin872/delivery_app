import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:mocktail/mocktail.dart';

import 'package:delivery_app/core/providers/formatters_provider.dart';
import 'package:delivery_app/features/auth/providers/auth_provider.dart';
import 'package:delivery_app/features/customer/screens/order_tracking_screen.dart';
import 'package:delivery_app/features/customer/widgets/driver_tracking_map.dart';
import 'package:delivery_app/features/customer/widgets/price_breakdown.dart';
import 'package:delivery_app/features/driver/screens/driver_home_screen.dart' show functionsServiceProvider;
import 'package:delivery_app/l10n/app_localizations.dart';
import 'package:delivery_app/models/app_user.dart';
import 'package:delivery_app/models/order.dart';
import 'package:delivery_app/models/review.dart';
import 'package:delivery_app/services/functions_service.dart';

class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

/// Records which participant the tracking screen asks the contact resolver
/// for. Nothing is dialed in tests (the url_launcher plugin is absent, so
/// the shared PhoneCallAction reports a failed call instead).
class _RecordingFunctions extends FunctionsService {
  _RecordingFunctions() : super(functions: _MockFirebaseFunctions());

  final targets = <ContactTarget>[];

  @override
  Future<String> getOrderContact(String orderId, ContactTarget target) async {
    targets.add(target);
    return '+963 900 000 002';
  }
}

final _currency = NumberFormat.currency(locale: 'en', name: 'SYP');
final _dateFormat = DateFormat('yyyy-MM-dd HH:mm');
final _l10n = lookupAppLocalizations(const Locale('en'));

const _customer = AppUser(id: 'customer-1', email: 'c@example.com', displayName: 'C', role: UserRole.customer);

DeliveryOrder _order({
  OrderStatus status = OrderStatus.pending,
  String? driverId,
  String? vendorName = 'Falafel House',
  double? subtotal = 7000,
  double? deliveryFee = 1500,
  double total = 8500,
  String? instructions = 'Third floor, blue gate',
  String? driverNote = 'Call on arrival',
  List<OrderItem> items = const [
    OrderItem(menuItemId: 'falafel', name: 'Falafel wrap', quantity: 2, unitPrice: 2000),
    OrderItem(menuItemId: 'hummus', name: 'Hummus', quantity: 1, unitPrice: 3000),
  ],
}) {
  return DeliveryOrder(
    id: 'order-1',
    customerId: 'customer-1',
    vendorId: 'vendor-1',
    driverId: driverId,
    items: items,
    status: status,
    total: total,
    subtotal: subtotal,
    deliveryFee: deliveryFee,
    deliveryAddress: 'Mezzeh, Building 4',
    deliveryLatitude: 33.5,
    deliveryLongitude: 36.25,
    deliveryInstructions: instructions,
    driverNote: driverNote,
    vendorName: vendorName,
    createdAt: DateTime(2026, 9, 22, 18, 30),
  );
}

Future<_RecordingFunctions> _pump(WidgetTester tester, DeliveryOrder order, {Review? review}) async {
  // Tall enough that the whole (lazy) ListView is built.
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final functions = _RecordingFunctions();
  await tester.pumpWidget(
    ProviderScope(
      // A fresh scope per pump, so a test can re-pump with another order.
      key: UniqueKey(),
      overrides: [
        orderTrackingProvider(order.id).overrideWith((ref) => Stream.value(order)),
        reviewForOrderProvider(order.id).overrideWith((ref) => Stream.value(review)),
        // No driver position has arrived — the map shows its waiting state
        // (and never builds a GoogleMap in tests).
        driverOrderLocationProvider(order.id).overrideWith((ref) => Stream.value(null)),
        currentAppUserProvider.overrideWith((ref) => Stream.value(_customer)),
        currencyFormatProvider.overrideWithValue(_currency),
        dateTimeFormatProvider.overrideWithValue(_dateFormat),
        functionsServiceProvider.overrideWithValue(functions),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: OrderTrackingScreen(orderId: order.id),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return functions;
}

Finder _callDriver() => find.byKey(const ValueKey('customer_call_driver'));

Finder _richText(String text) => find.textContaining(text, findRichText: true);

void main() {
  testWidgets('every status renders without errors', (tester) async {
    for (final status in OrderStatus.values) {
      await _pump(tester, _order(status: status, driverId: 'driver-1'));
      expect(tester.takeException(), isNull, reason: status.name);
      expect(find.byKey(const ValueKey('order_summary')), findsOneWidget, reason: status.name);
    }
  });

  group('order summary', () {
    testWidgets('shows store, date, items, amounts, instructions and note', (tester) async {
      await _pump(tester, _order());

      expect(find.text(_l10n.orderDetailsTitle), findsOneWidget);
      expect(_richText('Falafel House'), findsOneWidget);
      expect(_richText(_dateFormat.format(DateTime(2026, 9, 22, 18, 30))), findsOneWidget);

      expect(find.text('Falafel wrap'), findsOneWidget);
      expect(find.text(_l10n.orderItemQuantityPrice(2, _currency.format(2000))), findsOneWidget);
      expect(find.text(_currency.format(4000)), findsOneWidget); // line total
      expect(find.text('Hummus'), findsOneWidget);
      expect(find.text(_l10n.orderItemQuantityPrice(1, _currency.format(3000))), findsOneWidget);

      // One shared breakdown, fed the server-charged amounts.
      final breakdown = tester.widget<PriceBreakdown>(find.byType(PriceBreakdown));
      expect(breakdown.subtotal, 7000);
      expect(breakdown.deliveryFee, 1500);
      expect(breakdown.total, 8500);
      expect(find.text(_l10n.subtotalLabel), findsOneWidget);
      expect(find.text(_currency.format(7000)), findsOneWidget);
      expect(find.text(_currency.format(1500)), findsOneWidget);
      expect(find.text(_currency.format(8500)), findsOneWidget);

      expect(_richText('Third floor, blue gate'), findsOneWidget);
      expect(_richText(_l10n.orderDeliveryInstructionsLabel), findsOneWidget);
      expect(_richText('Call on arrival'), findsOneWidget);
      expect(_richText(_l10n.orderDriverNoteLabel), findsOneWidget);
    });

    testWidgets('a legacy order without the optional fields still renders', (tester) async {
      await _pump(
        tester,
        _order(
          vendorName: null,
          subtotal: null,
          deliveryFee: null,
          total: 5000,
          instructions: null,
          driverNote: '  ',
          items: const [],
        ),
      );

      expect(tester.takeException(), isNull);
      expect(_richText(_l10n.vendorLabel), findsNothing);
      expect(find.text(_l10n.orderItemsTitle), findsNothing);
      expect(_richText(_l10n.orderDeliveryInstructionsLabel), findsNothing);
      expect(_richText(_l10n.orderDriverNoteLabel), findsNothing);
      // effective* fallbacks: subtotal = total, no fee.
      final breakdown = tester.widget<PriceBreakdown>(find.byType(PriceBreakdown));
      expect(breakdown.subtotal, 5000);
      expect(breakdown.deliveryFee, 0);
      expect(find.text(_l10n.freeDeliveryLabel), findsOneWidget);
    });

    testWidgets('does not expose the pickup address to the customer', (tester) async {
      final order = DeliveryOrder(
        id: 'order-1',
        customerId: 'customer-1',
        vendorId: 'vendor-1',
        items: const [],
        status: OrderStatus.accepted,
        total: 100,
        deliveryAddress: 'Mezzeh',
        createdAt: DateTime(2026, 9, 22),
        pickupAddress: 'Hidden pickup street',
      );
      await _pump(tester, order);

      expect(_richText('Hidden pickup street'), findsNothing);
    });
  });

  group('call driver', () {
    for (final status in [OrderStatus.driverAssigned, OrderStatus.pickedUp, OrderStatus.delivering]) {
      testWidgets('visible at ${status.name} with a driver, without a driver location', (tester) async {
        await _pump(tester, _order(status: status, driverId: 'driver-1'));

        expect(_callDriver(), findsOneWidget);
        expect(find.text(_l10n.callDriverButton), findsOneWidget);
      });
    }

    testWidgets('delivering: the map is shown (waiting for a position) and there is exactly one call action',
        (tester) async {
      await _pump(tester, _order(status: OrderStatus.delivering, driverId: 'driver-1'));

      expect(find.byType(DriverTrackingMap), findsOneWidget);
      expect(find.text(_l10n.waitingForDriverLocationMessage), findsOneWidget);
      expect(_callDriver(), findsOneWidget);
      expect(find.byIcon(Icons.call), findsOneWidget);
    });

    testWidgets('hidden without a driverId', (tester) async {
      await _pump(tester, _order(status: OrderStatus.driverAssigned));
      expect(_callDriver(), findsNothing);
    });

    testWidgets('hidden outside the contact window', (tester) async {
      for (final status in [
        OrderStatus.pending,
        OrderStatus.accepted,
        OrderStatus.preparing,
        OrderStatus.readyForPickup,
        OrderStatus.delivered,
        OrderStatus.cancelled,
      ]) {
        await _pump(tester, _order(status: status, driverId: 'driver-1'));
        expect(_callDriver(), findsNothing, reason: status.name);
      }
    });

    testWidgets('asks the contact resolver for the driver only', (tester) async {
      final functions = await _pump(tester, _order(status: OrderStatus.pickedUp, driverId: 'driver-1'));

      await tester.tap(find.text(_l10n.callDriverButton));
      await tester.pump();
      await tester.pump();

      expect(functions.targets, [ContactTarget.driver]);
    });
  });

  group('actions by status', () {
    testWidgets('cancel is offered only while pending', (tester) async {
      await _pump(tester, _order(status: OrderStatus.pending));
      expect(find.text(_l10n.cancelOrderButton), findsOneWidget);

      for (final status in OrderStatus.values.where((s) => s != OrderStatus.pending)) {
        await _pump(tester, _order(status: status, driverId: 'driver-1'));
        expect(find.text(_l10n.cancelOrderButton), findsNothing, reason: status.name);
      }
    });

    testWidgets('delivered and not yet rated offers the rate button', (tester) async {
      await _pump(tester, _order(status: OrderStatus.delivered, driverId: 'driver-1'));
      expect(find.text(_l10n.rateOrderButton), findsOneWidget);
    });

    testWidgets('cancelled shows the terminal state instead of the timeline', (tester) async {
      await _pump(tester, _order(status: OrderStatus.cancelled));

      expect(find.byIcon(Icons.cancel), findsOneWidget);
      expect(find.text(_l10n.rateOrderButton), findsNothing);
      expect(find.byKey(const ValueKey('order_summary')), findsOneWidget);
    });
  });
}
