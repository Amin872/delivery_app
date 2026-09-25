import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:mocktail/mocktail.dart';

import 'package:delivery_app/core/providers/formatters_provider.dart';
import 'package:delivery_app/core/widgets/app_network_image.dart';
import 'package:delivery_app/core/widgets/gradient_button.dart';
import 'package:delivery_app/features/auth/providers/auth_provider.dart';
import 'package:delivery_app/features/customer/providers/cart_provider.dart';
import 'package:delivery_app/features/customer/screens/cart_screen.dart';
import 'package:delivery_app/features/customer/screens/customer_home_screen.dart' show firestoreServiceProvider;
import 'package:delivery_app/features/customer/screens/delivery_addresses_screen.dart' show defaultAddressProvider;
import 'package:delivery_app/features/customer/widgets/cart_quantity_control.dart';
import 'package:delivery_app/features/customer/widgets/price_breakdown.dart';
import 'package:delivery_app/features/driver/screens/driver_home_screen.dart' show functionsServiceProvider;
import 'package:delivery_app/l10n/app_localizations.dart';
import 'package:delivery_app/models/address.dart';
import 'package:delivery_app/models/app_user.dart';
import 'package:delivery_app/models/approval_status.dart';
import 'package:delivery_app/models/vendor.dart';
import 'package:delivery_app/services/firestore_service.dart';
import 'package:delivery_app/services/functions_service.dart';

class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

/// Records every createOrder call; each call waits on [release] so a test
/// can observe the in-flight state before letting it fail.
class _RecordingFunctions extends FunctionsService {
  _RecordingFunctions() : super(functions: _MockFirebaseFunctions());

  final calls = <({String vendorId, List<OrderLineRequest> items, String addressId})>[];
  final release = Completer<void>();

  @override
  Future<PlacedOrder> createOrder({
    required String vendorId,
    required List<OrderLineRequest> items,
    required String addressId,
  }) async {
    calls.add((vendorId: vendorId, items: items, addressId: addressId));
    await release.future;
    throw Exception('stop here');
  }
}

final _currency = NumberFormat.currency(locale: 'en', name: 'SYP');
final _l10n = lookupAppLocalizations(const Locale('en'));

const _falafel = MenuItem(id: 'falafel', vendorId: 'vendor-1', name: 'Falafel wrap', price: 2000, available: true);
const _hummus = MenuItem(
  id: 'hummus',
  vendorId: 'vendor-1',
  name: 'Hummus',
  price: 3000,
  available: true,
  imageUrl: 'https://example.com/hummus.png',
);

const _address = SavedAddress(
  id: 'home',
  userId: 'customer-1',
  label: 'Home',
  addressText: 'Mezzeh, Building 4',
  latitude: 33.5,
  longitude: 36.25,
  deliveryInstructions: 'Third floor, blue gate',
  driverNote: 'Call on arrival',
  isDefault: true,
);

Vendor _vendor({double? minimum, double? fee = 1500}) => Vendor(
      id: 'vendor-1',
      ownerId: 'owner-1',
      name: 'Falafel House',
      description: '',
      isOpen: true,
      approvalStatus: ApprovalStatus.approved,
      deliveryFee: fee,
      minimumOrderAmount: minimum,
    );

/// Pumps CartScreen with falafel ×2 (+ hummus when [withHummus]) in the
/// cart — subtotal 4,000 (or 7,000).
Future<_RecordingFunctions> _pump(
  WidgetTester tester, {
  Vendor? vendor,
  SavedAddress? address = _address,
  bool withHummus = false,
  bool emptyCart = false,
}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final firestore = FakeFirebaseFirestore();
  final v = vendor ?? _vendor();
  await firestore.collection('vendors').doc(v.id).set(v.toMap());
  final functions = _RecordingFunctions();

  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        firestoreServiceProvider.overrideWithValue(FirestoreService(firestore: firestore)),
        functionsServiceProvider.overrideWithValue(functions),
        currencyFormatProvider.overrideWithValue(_currency),
        currentAppUserProvider.overrideWith((ref) => Stream.value(
              const AppUser(id: 'customer-1', email: 'c@example.com', displayName: 'C', role: UserRole.customer),
            )),
        defaultAddressProvider('customer-1').overrideWith((ref) => Stream.value(address)),
        cartProvider.overrideWith((ref) {
          final cart = CartController();
          if (!emptyCart) {
            cart.addItem('vendor-1', 'Falafel House', _falafel);
            cart.addItem('vendor-1', 'Falafel House', _falafel);
            if (withHummus) cart.addItem('vendor-1', 'Falafel House', _hummus);
          }
          return cart;
        }),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const CartScreen(),
      ),
    ),
  );
  // Plain pumps: the network thumbnail's shimmer never settles.
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return functions;
}

Finder _placeOrder() => find.byKey(const ValueKey('cart_place_order_button'));
Finder _minimumHint() => find.byKey(const ValueKey('cart_minimum_order_hint'));

bool _placeOrderEnabled(WidgetTester tester) => tester.widget<GradientButton>(_placeOrder()).onPressed != null;

void main() {
  group('minimum order', () {
    testWidgets('below the minimum: hint with amounts, Place Order disabled', (tester) async {
      await _pump(tester, vendor: _vendor(minimum: 5000));

      expect(_minimumHint(), findsOneWidget);
      expect(
        find.text(_l10n.minimumOrderNotMetHint(_currency.format(5000), _currency.format(1000))),
        findsOneWidget,
      );
      expect(_placeOrderEnabled(tester), isFalse);
    });

    testWidgets('exactly at the minimum: no hint, Place Order enabled', (tester) async {
      await _pump(tester, vendor: _vendor(minimum: 4000));

      expect(_minimumHint(), findsNothing);
      expect(_placeOrderEnabled(tester), isTrue);
    });

    testWidgets('above the minimum: no hint, Place Order enabled', (tester) async {
      await _pump(tester, vendor: _vendor(minimum: 5000), withHummus: true);

      expect(_minimumHint(), findsNothing);
      expect(_placeOrderEnabled(tester), isTrue);
    });

    testWidgets('a zero or missing minimum never gates the order', (tester) async {
      for (final minimum in [null, 0.0]) {
        await _pump(tester, vendor: _vendor(minimum: minimum));
        expect(_minimumHint(), findsNothing, reason: '$minimum');
        expect(_placeOrderEnabled(tester), isTrue, reason: '$minimum');
      }
    });

    testWidgets('raising the quantity past the minimum re-enables Place Order', (tester) async {
      await _pump(tester, vendor: _vendor(minimum: 5000));
      expect(_placeOrderEnabled(tester), isFalse);

      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pump();

      expect(_minimumHint(), findsNothing);
      expect(_placeOrderEnabled(tester), isTrue);
    });
  });

  group('selected address', () {
    testWidgets('shows its delivery instructions and driver note, read-only', (tester) async {
      await _pump(tester);

      expect(find.text('Third floor, blue gate'), findsOneWidget);
      expect(find.text('Call on arrival'), findsOneWidget);
      expect(find.byTooltip(_l10n.orderDeliveryInstructionsLabel), findsOneWidget);
      expect(find.byTooltip(_l10n.orderDriverNoteLabel), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('an address without them shows neither', (tester) async {
      await _pump(
        tester,
        address: const SavedAddress(id: 'home', userId: 'customer-1', label: 'Home', addressText: 'Mezzeh'),
      );

      expect(find.byTooltip(_l10n.orderDeliveryInstructionsLabel), findsNothing);
      expect(find.byTooltip(_l10n.orderDriverNoteLabel), findsNothing);
    });

    testWidgets('no address still blocks Place Order (existing rule)', (tester) async {
      await _pump(tester, address: null);

      expect(find.text(_l10n.noDeliveryLocationMessage), findsOneWidget);
      expect(_placeOrderEnabled(tester), isFalse);
    });
  });

  group('cart lines', () {
    testWidgets('use the shared CartQuantityControl and keep +/- behavior', (tester) async {
      await _pump(tester);

      expect(find.byType(CartQuantityControl), findsOneWidget);
      expect(find.text('2'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pump();
      expect(find.text('3'), findsOneWidget);
      expect(tester.widget<PriceBreakdown>(find.byType(PriceBreakdown)).subtotal, 6000);

      await tester.tap(find.byIcon(Icons.remove_circle_outline));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.remove_circle_outline));
      await tester.pump();
      expect(find.text('1'), findsOneWidget);

      // Down to zero removes the line — the cart is then empty.
      await tester.tap(find.byIcon(Icons.remove_circle_outline));
      await tester.pump();
      expect(find.text(_l10n.emptyCartMessage), findsOneWidget);
    });

    testWidgets('a line with a photo uses AppNetworkImage; one without keeps the placeholder icon', (tester) async {
      await _pump(tester, withHummus: true);

      expect(find.byType(AppNetworkImage), findsOneWidget);
      expect(find.byIcon(Icons.fastfood_outlined), findsOneWidget);
      expect(find.byType(CartQuantityControl), findsNWidgets(2));
    });

    testWidgets('shared price breakdown: subtotal, fee and estimated total', (tester) async {
      await _pump(tester);

      final breakdown = tester.widget<PriceBreakdown>(find.byType(PriceBreakdown));
      expect(breakdown.subtotal, 4000);
      expect(breakdown.deliveryFee, 1500);
      expect(breakdown.total, 5500);
      expect(find.text(_currency.format(5500)), findsOneWidget);
    });

    testWidgets('an empty cart shows the empty message', (tester) async {
      await _pump(tester, emptyCart: true);

      expect(find.text(_l10n.emptyCartMessage), findsOneWidget);
      expect(_placeOrder(), findsNothing);
    });
  });

  group('placing the order', () {
    testWidgets('sends only vendor, lines and address id; a second tap while in flight sends nothing',
        (tester) async {
      final functions = await _pump(tester, withHummus: true);

      await tester.tap(_placeOrder());
      await tester.pump();

      expect(functions.calls, hasLength(1));
      final call = functions.calls.single;
      expect(call.vendorId, 'vendor-1');
      expect(call.addressId, 'home');
      expect(call.items, [
        (menuItemId: 'falafel', quantity: 2),
        (menuItemId: 'hummus', quantity: 1),
      ]);
      expect(_placeOrderEnabled(tester), isFalse);

      await tester.tap(_placeOrder(), warnIfMissed: false);
      await tester.pump();
      expect(functions.calls, hasLength(1));

      // Let the call fail: the button comes back and the cart is kept.
      functions.release.complete();
      await tester.pump();
      await tester.pump();
      expect(_placeOrderEnabled(tester), isTrue);
      expect(find.byType(CartQuantityControl), findsNWidgets(2));
    });
  });
}
