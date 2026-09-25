import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:mocktail/mocktail.dart';

import 'package:delivery_app/core/providers/formatters_provider.dart';
import 'package:delivery_app/core/widgets/app_network_image.dart';
import 'package:delivery_app/features/admin/screens/admin_order_detail_screen.dart';
import 'package:delivery_app/features/customer/screens/customer_home_screen.dart' show firestoreServiceProvider;
import 'package:delivery_app/features/customer/widgets/price_breakdown.dart';
import 'package:delivery_app/features/driver/screens/driver_home_screen.dart' show functionsServiceProvider;
import 'package:delivery_app/l10n/app_localizations.dart';
import 'package:delivery_app/models/order.dart';
import 'package:delivery_app/services/firestore_service.dart';
import 'package:delivery_app/services/functions_service.dart';

class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

/// Records the admin callables the screen invokes (nothing reaches a server).
class _RecordingFunctions extends FunctionsService {
  _RecordingFunctions() : super(functions: _MockFirebaseFunctions());

  final cancelled = <String>[];
  final reassigned = <(String, String)>[];

  @override
  Future<void> adminCancelOrder(String orderId) async => cancelled.add(orderId);

  @override
  Future<void> adminReassignDriver(String orderId, String driverId) async =>
      reassigned.add((orderId, driverId));
}

final _currency = NumberFormat.currency(locale: 'en', name: 'SYP');
final _l10n = lookupAppLocalizations(const Locale('en'));

DeliveryOrder _order({
  OrderStatus status = OrderStatus.readyForPickup,
  String? driverId,
  double? subtotal = 7000,
  double? deliveryFee = 1500,
  double total = 8500,
  String? vendorName = 'Falafel House',
  String? pickupAddress = 'Hamra St, Damascus',
  String? instructions = 'Third floor, blue gate',
  String? driverNote = 'Call on arrival',
  String? proofImageUrl,
  double? latitude = 33.5,
  double? longitude = 36.25,
}) {
  return DeliveryOrder(
    id: 'order-1',
    customerId: 'customer-1',
    vendorId: 'vendor-1',
    driverId: driverId,
    items: const [
      OrderItem(menuItemId: 'falafel', name: 'Falafel wrap', quantity: 2, unitPrice: 2000),
      OrderItem(menuItemId: 'hummus', name: 'Hummus', quantity: 1, unitPrice: 3000),
    ],
    status: status,
    total: total,
    subtotal: subtotal,
    deliveryFee: deliveryFee,
    deliveryAddress: 'Mezzeh, Building 4',
    deliveryLatitude: latitude,
    deliveryLongitude: longitude,
    deliveryInstructions: instructions,
    driverNote: driverNote,
    vendorName: vendorName,
    pickupAddress: pickupAddress,
    proofImageUrl: proofImageUrl,
    createdAt: DateTime(2026, 9, 22, 18, 30),
  );
}

Future<void> _seed(FakeFirebaseFirestore db, DeliveryOrder order) async {
  await db.collection('orders').doc(order.id).set(order.toMap());
  await db.collection('vendors').doc('vendor-1').set({
    'ownerId': 'owner-1',
    'name': 'Falafel House',
    'description': '',
    'isOpen': true,
    'approvalStatus': 'approved',
  });
  Future<void> user(String id, String name, String role) =>
      db.collection('users').doc(id).set({'email': '$id@example.com', 'displayName': name, 'role': role});
  await user('customer-1', 'Customer One', 'customer');
  await user('driver-1', 'Driver One', 'driver');
  await user('driver-2', 'Driver Two', 'driver');
  await user('driver-3', 'Pending Pat', 'driver');
  Future<void> driver(String id, String approval, bool available) => db
      .collection('drivers')
      .doc(id)
      .set({'userId': id, 'isAvailable': available, 'approvalStatus': approval});
  await driver('driver-1', 'approved', false);
  await driver('driver-2', 'approved', true);
  await driver('driver-3', 'pending', true);
}

/// Pumps the screen over an in-memory Firestore seeded with [order], its
/// people and three drivers (two approved, one pending).
Future<_RecordingFunctions> _pump(
  WidgetTester tester,
  DeliveryOrder order, {
  Size size = const Size(800, 3000),
  Locale locale = const Locale('en'),
  double textScale = 1,
  bool settle = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final db = FakeFirebaseFirestore();
  await _seed(db, order);
  final functions = _RecordingFunctions();
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        firestoreServiceProvider.overrideWithValue(FirestoreService(firestore: db)),
        functionsServiceProvider.overrideWithValue(functions),
        currencyFormatProvider.overrideWithValue(NumberFormat.currency(locale: locale.languageCode, name: 'SYP')),
        dateTimeFormatProvider.overrideWithValue(DateFormat.yMd(locale.languageCode).add_Hm()),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const AdminOrderDetailScreen(orderId: 'order-1'),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    // A network image's shimmer never settles.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
  return functions;
}

// The action buttons, by label (OutlinedButton.icon builds a private
// subclass, so a by-type finder would miss them).
Finder _cancelButton() => find.text(_l10n.cancelOrderButton);
Finder _reassignButton() => find.text(_l10n.reassignDriverButton);

void main() {
  setUpAll(() => initializeDateFormatting('ar'));

  group('order summary', () {
    testWidgets('items with quantity × unit price and line totals, plus the shared price breakdown',
        (tester) async {
      await _pump(tester, _order());

      expect(find.text('Falafel wrap'), findsOneWidget);
      expect(find.text(_l10n.orderItemQuantityPrice(2, _currency.format(2000))), findsOneWidget);
      expect(find.text(_currency.format(4000)), findsOneWidget);
      expect(find.text('Hummus'), findsOneWidget);
      expect(find.text(_l10n.orderItemQuantityPrice(1, _currency.format(3000))), findsOneWidget);

      final breakdown = tester.widget<PriceBreakdown>(find.byType(PriceBreakdown));
      expect((breakdown.subtotal, breakdown.deliveryFee, breakdown.total), (7000.0, 1500.0, 8500.0));
      expect(find.text(_currency.format(7000)), findsOneWidget);
      expect(find.text(_currency.format(1500)), findsOneWidget);
      expect(find.text(_currency.format(8500)), findsOneWidget);
    });

    testWidgets('pickup snapshot, delivery details and coordinates', (tester) async {
      await _pump(tester, _order());

      final pickup = find.byKey(const ValueKey('admin_order_pickup'));
      expect(find.descendant(of: pickup, matching: find.text('Falafel House')), findsOneWidget);
      expect(find.descendant(of: pickup, matching: find.text('Hamra St, Damascus')), findsOneWidget);
      expect(find.descendant(of: pickup, matching: find.text(_l10n.pickupAddressFieldLabel)), findsOneWidget);

      final delivery = find.byKey(const ValueKey('admin_order_delivery'));
      expect(find.descendant(of: delivery, matching: find.text('Mezzeh, Building 4')), findsOneWidget);
      expect(find.descendant(of: delivery, matching: find.text('Third floor, blue gate')), findsOneWidget);
      expect(find.descendant(of: delivery, matching: find.text(_l10n.orderDeliveryInstructionsLabel)), findsOneWidget);
      expect(find.descendant(of: delivery, matching: find.text('Call on arrival')), findsOneWidget);
      expect(find.descendant(of: delivery, matching: find.text(_l10n.orderDriverNoteLabel)), findsOneWidget);
      expect(find.descendant(of: delivery, matching: find.text('33.50000, 36.25000')), findsOneWidget);

      expect(find.byKey(const ValueKey('admin_order_proof')), findsNothing);
    });

    testWidgets('proof of delivery shows the photo through AppNetworkImage', (tester) async {
      await _pump(
        tester,
        _order(status: OrderStatus.delivered, driverId: 'driver-1', proofImageUrl: 'https://example.com/proof.jpg'),
        settle: false,
      );

      expect(find.text(_l10n.proofOfDeliveryLabel), findsOneWidget);
      final image = tester.widget<AppNetworkImage>(find.byKey(const ValueKey('admin_order_proof')));
      expect(image.imageUrl, 'https://example.com/proof.jpg');
    });

    testWidgets('a legacy order without the optional fields renders safely', (tester) async {
      await _pump(
        tester,
        _order(
          subtotal: null,
          deliveryFee: null,
          total: 5000,
          vendorName: null,
          pickupAddress: '  ',
          instructions: null,
          driverNote: '',
          latitude: null,
          longitude: null,
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('admin_order_pickup')), findsNothing);
      expect(find.text(_l10n.orderDeliveryInstructionsLabel), findsNothing);
      expect(find.text(_l10n.orderDriverNoteLabel), findsNothing);
      expect(find.text(_l10n.deliveryLocationLabel), findsNothing);
      expect(find.byKey(const ValueKey('admin_order_proof')), findsNothing);
      final breakdown = tester.widget<PriceBreakdown>(find.byType(PriceBreakdown));
      expect((breakdown.subtotal, breakdown.deliveryFee, breakdown.total), (5000.0, 0.0, 5000.0));
    });
  });

  group('actions', () {
    testWidgets('cancel and reassign are offered exactly in the server-allowed statuses', (tester) async {
      const cancellable = {
        OrderStatus.pending,
        OrderStatus.accepted,
        OrderStatus.preparing,
        OrderStatus.readyForPickup,
      };
      const reassignable = {OrderStatus.readyForPickup, OrderStatus.driverAssigned, OrderStatus.pickedUp};
      for (final status in OrderStatus.values) {
        await _pump(tester, _order(status: status, driverId: 'driver-1'));
        expect(_cancelButton(), cancellable.contains(status) ? findsOneWidget : findsNothing, reason: status.name);
        expect(_reassignButton(), reassignable.contains(status) ? findsOneWidget : findsNothing, reason: status.name);
      }
    });

    testWidgets('cancel calls adminCancelOrder with this order id after confirmation', (tester) async {
      final functions = await _pump(tester, _order(status: OrderStatus.preparing));

      await tester.tap(_cancelButton());
      await tester.pumpAndSettle();
      expect(functions.cancelled, isEmpty); // nothing before confirming

      await tester.tap(find.text(_l10n.confirmButton));
      await tester.pumpAndSettle();

      expect(functions.cancelled, ['order-1']);
      expect(functions.reassigned, isEmpty);
    });

    testWidgets('reassign offers approved drivers only and calls adminReassignDriver with order + driver',
        (tester) async {
      final functions = await _pump(tester, _order(status: OrderStatus.driverAssigned, driverId: 'driver-1'));

      await tester.tap(_reassignButton());
      await tester.pumpAndSettle();

      final sheet = find.byType(BottomSheet);
      expect(find.descendant(of: sheet, matching: find.text('Driver One')), findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.text('Driver Two')), findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.text('Pending Pat')), findsNothing);

      await tester.tap(find.descendant(of: sheet, matching: find.text('Driver Two')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_l10n.confirmButton));
      await tester.pumpAndSettle();

      expect(functions.reassigned, [('order-1', 'driver-2')]);
      expect(functions.cancelled, isEmpty);
    });
  });

  testWidgets('Arabic, 320dp wide, 1.3× text: lays out without overflow', (tester) async {
    await _pump(
      tester,
      _order(
        vendorName: 'مطعم الفلافل الذهبي للمأكولات الشامية الأصيلة',
        pickupAddress: 'شارع الحمراء، بجانب الصيدلية الكبيرة، دمشق',
        instructions: 'الطابق الثالث، البوابة الزرقاء بجانب الصيدلية الكبيرة في آخر الشارع',
        subtotal: 99000000,
        deliveryFee: 999999,
        total: 99999999,
      ),
      size: const Size(320, 640),
      locale: const Locale('ar'),
      textScale: 1.3,
    );

    for (var i = 0; i < 12; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -300));
      await tester.pumpAndSettle();
    }
    // Scrolled end to end; any overflow on the way already failed the test.
    expect(tester.takeException(), isNull);
  });
}
