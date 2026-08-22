// Comprehensive multi-role E2E suite, driven live on the connected Android
// emulator. Runs against the local Firebase Emulator Suite ONLY — see
// test_helpers.dart's connectToEmulators() — never the live orient-food-9c1e0
// project. One continuous, ordered scenario: later steps depend on earlier
// ones' state, which is the honest shape of "the full lifecycle across
// roles," not an isolated-unit-test anti-pattern.
//
// Prerequisites (see the plan / README note added alongside this file):
//   1. cd functions && npm run build
//   2. firebase emulators:start   (from repo root)
//   3. FIRESTORE_EMULATOR_HOST=localhost:8080 FIREBASE_AUTH_EMULATOR_HOST=localhost:9099 \
//      npx ts-node functions/scripts/seed-admin.ts
//   4. adb -s emulator-5554 emu geo fix 35.9106 31.9539
//   5. flutter test integration_test/app_e2e_test.dart -d emulator-5554
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:integration_test/integration_test.dart';

import 'package:delivery_app/models/app_user.dart';

import 'test_helpers.dart';

// Matches functions/scripts/seed-admin.ts exactly.
const _adminEmail = 'admin@e2e.test';
const _adminPassword = 'TestAdmin123!';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final runId = DateTime.now().millisecondsSinceEpoch;
  final customerEmail = 'customer_$runId@e2e.test';
  final vendorEmail = 'vendor_$runId@e2e.test';
  final driverEmail = 'driver_$runId@e2e.test';
  const password = 'TestPass123!';
  // Unique per run, not just the emails — the local emulator's Firestore
  // data is long-lived across repeated `flutter test` invocations during
  // development (nothing clears it automatically), so a fixed name would
  // collide with any prior run's leftover vendor/menu item, e.g. making
  // "Approve" ambiguous on admin_dashboard_screen.dart's pending-vendor list.
  final vendorName = 'E2E Test Kitchen $runId';
  final menuItemName = 'E2E Falafel Wrap $runId';
  const menuItemPrice = '5.50';

  String? customerUid;
  String? vendorUid;
  String? driverUid;
  String? orderId;

  setUpAll(() async {
    await connectToEmulators();
    ImagePickerPlatform.instance = FakeImagePicker();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(await buildTestApp());
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 1200));
  }

  testWidgets('1. Customer signs up, signs out, signs back in', (tester) async {
    await pumpApp(tester);

    await signUp(
      tester,
      name: 'E2E Customer',
      email: customerEmail,
      password: password,
      phone: '+15550000001',
    );
    expect(find.text('Nearby vendors'), findsOneWidget);
    customerUid = FirebaseAuth.instance.currentUser!.uid;

    await signOut(tester);
    expect(find.text('Sign in'), findsWidgets);

    await signIn(tester, email: customerEmail, password: password);
    expect(find.text('Nearby vendors'), findsOneWidget);
  });

  testWidgets('2. Vendor signs up, opens the store, adds a menu item', (tester) async {
    await pumpApp(tester);
    await signOut(tester); // leftover customer session from step 1

    await signUp(
      tester,
      name: vendorName,
      email: vendorEmail,
      password: password,
      phone: '+15550000002',
      role: UserRole.vendor,
    );
    expect(find.text('Incoming orders'), findsOneWidget);
    vendorUid = FirebaseAuth.instance.currentUser!.uid;

    // New vendors start closed (isOpen: false) — open the store.
    await tester.tap(find.byKey(const ValueKey('vendor_open_switch')));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Manage menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add item'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('menu_item_name_field')), menuItemName);
    await tester.enterText(find.byKey(const ValueKey('menu_item_price_field')), menuItemPrice);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('menu_item_save_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu_item_save_button')));
    await tester.pumpAndSettle();
    expect(find.text(menuItemName), findsWidgets);
  });

  testWidgets('3. Driver signs up, toggles availability', (tester) async {
    await pumpApp(tester);
    await signOut(tester);

    await signUp(
      tester,
      name: 'E2E Driver',
      email: driverEmail,
      password: password,
      phone: '+15550000003',
      role: UserRole.driver,
    );
    expect(find.text('Available deliveries'), findsOneWidget);
    driverUid = FirebaseAuth.instance.currentUser!.uid;

    await tester.tap(find.byKey(const ValueKey('driver_available_switch')));
    await tester.pumpAndSettle();

    final driverDoc = await FirebaseFirestore.instance.collection('drivers').doc(driverUid).get();
    expect(driverDoc.data()!['isAvailable'], isFalse); // toggled off from its default-true

    await signOut(tester);
  });

  testWidgets('4. Admin approves the vendor', (tester) async {
    await pumpApp(tester);

    await signIn(tester, email: _adminEmail, password: _adminPassword);
    expect(find.text('Restaurant Management'), findsOneWidget);
    expect(find.text(vendorName), findsWidgets);

    // The emulator's Firestore data isn't cleared between dev runs of this
    // suite, so other pending vendors (from earlier partial runs) may still
    // be sitting in the approvals list, each with their own "Approve"
    // tooltip — a bare find.byTooltip('Approve') would be ambiguous. Scope
    // the tap to this run's own vendor card, identified by its unique name.
    final vendorCard = find.ancestor(of: find.text(vendorName), matching: find.byType(Card));
    await tester.tap(find.descendant(of: vendorCard, matching: find.byTooltip('Approve')).first);
    await tester.pumpAndSettle();

    final vendorDoc = await FirebaseFirestore.instance.collection('vendors').doc(vendorUid).get();
    expect(vendorDoc.data()!['approvalStatus'], 'approved');
    expect(vendorDoc.data()!['isOpen'], isTrue);

    await signOut(tester);
  });

  testWidgets('5. Customer browses the now-open vendor, places an order', (tester) async {
    await pumpApp(tester);

    await signIn(tester, email: customerEmail, password: password);
    expect(find.text('Nearby vendors'), findsOneWidget);
    expect(find.text(vendorName), findsWidgets);

    await tester.tap(find.text(vendorName).first);
    await tester.pumpAndSettle();
    expect(find.text(menuItemName), findsWidgets);

    await tester.tap(find.byTooltip('Add to cart'));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('View cart'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('cart_address_field')), '123 E2E Street');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('cart_place_order_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cart_place_order_button')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 1200));

    expect(find.text('Order placed!'), findsOneWidget);
    expect(find.text('Track order'), findsOneWidget);

    // Filtered by customerId, not vendorId — firestore.rules' orders read
    // rule can only prove a *list* query safe when the query itself
    // guarantees the match (here: customerId == the signed-in customer),
    // same reasoning as watchAvailableOrdersForDrivers() in
    // firestore_service.dart. A vendorId-only filter would come back
    // permission-denied even though the individual doc would pass the rule.
    final orders = await FirebaseFirestore.instance
        .collection('orders')
        .where('customerId', isEqualTo: customerUid)
        .get();
    expect(orders.docs.length, 1);
    orderId = orders.docs.first.id;
    expect(orders.docs.first.data()['status'], 'pending');

    // Placing an order pushReplace()s CartScreen with OrderTrackingScreen,
    // two pushes deep from CustomerHomeScreen (Home -> VendorMenuScreen ->
    // CartScreen/OrderTrackingScreen) — its AppBar has a back button, not
    // the logout icon signOut() looks for, so pop back to the home shell.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await signOut(tester);
  });

  testWidgets('6. Vendor advances the order through prep', (tester) async {
    await pumpApp(tester);

    await signIn(tester, email: vendorEmail, password: password);
    expect(find.text('Incoming orders'), findsOneWidget);

    await tester.tap(find.text('Move to Accepted').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to Preparing').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to Ready for pickup').first);
    await tester.pumpAndSettle();

    final orderDoc = await FirebaseFirestore.instance.collection('orders').doc(orderId).get();
    expect(orderDoc.data()!['status'], 'readyForPickup');

    await signOut(tester);
  });

  testWidgets(
      '7. Driver accepts and delivers the order; GPS lands in Firestore '
      '(data layer only — no rendered map, see the plan)', (tester) async {
    await pumpApp(tester);

    await signIn(tester, email: driverEmail, password: password);
    expect(find.text('Available deliveries'), findsOneWidget);
    expect(find.text('Accept'), findsWidgets);

    await tester.tap(find.text('Accept').first);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Order accepted.'), findsOneWidget);

    await tester.tap(find.text('Move to Delivering').first);
    await tester.pumpAndSettle();

    // The order's status write (delivering) is async — the active-delivery
    // card (and its proof-of-delivery photo icon) only appears once the
    // live orders stream picks up the new status and rebuilds. Poll instead
    // of a fixed wait, since the round-trip time isn't fully predictable.
    // This also gives the location stream (driverLocationSyncProvider,
    // active as soon as an order is mid-delivery) time to publish at least
    // once, fed by the `adb emu geo fix` coordinate set before this test ran.
    final proofIcon = find.byIcon(Icons.add_a_photo_outlined);
    var waited = Duration.zero;
    const pollStep = Duration(milliseconds: 250);
    const pollTimeout = Duration(seconds: 25);
    while (!tester.any(proofIcon) && waited < pollTimeout) {
      await tester.pump(pollStep);
      waited += pollStep;
    }
    if (!tester.any(proofIcon)) {
      final orderDoc = await FirebaseFirestore.instance.collection('orders').doc(orderId).get();
      // ignore: avoid_print
      print('DIAG: proof icon never appeared. order status = ${orderDoc.data()?['status']}');
      // ignore: avoid_print
      print('DIAG: texts on screen: ${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList()}');
    }

    // Proof-of-delivery photo, required before "delivered" is reachable —
    // FakeImagePicker (installed in setUpAll) returns the bundled fixture
    // instead of an OS gallery chooser WidgetTester couldn't drive anyway.
    await tester.tap(proofIcon.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to Delivered').first);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final driverDoc = await FirebaseFirestore.instance.collection('drivers').doc(driverUid).get();
    expect(driverDoc.data()!['lastKnownLocation'], isNotNull);

    final orderDoc = await FirebaseFirestore.instance.collection('orders').doc(orderId).get();
    expect(orderDoc.data()!['status'], 'delivered');
    expect(orderDoc.data()!['proofImageUrl'], isNotNull);

    await signOut(tester);
  });

  testWidgets('8. Customer rates the order; vendor rating aggregates via the Functions emulator',
      (tester) async {
    await pumpApp(tester);

    await signIn(tester, email: customerEmail, password: password);
    expect(find.text('Nearby vendors'), findsOneWidget);

    await tester.tap(find.byTooltip('My orders'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Order ').first);
    await tester.pumpAndSettle();

    expect(find.text('Rate your order'), findsOneWidget);
    await tester.tap(find.text('Rate your order'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('vendor_rating_star_5')));
    await tester.tap(find.byKey(const ValueKey('driver_rating_star_4')));
    await tester.enterText(
      find.byKey(const ValueKey('review_comment_field')),
      'Great E2E delivery!',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('review_submit_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('review_submit_button')));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.text('Thanks for your feedback!'), findsOneWidget);

    final vendorDoc = await FirebaseFirestore.instance.collection('vendors').doc(vendorUid).get();
    expect(vendorDoc.data()!['ratingCount'], 1);
    expect(vendorDoc.data()!['ratingSum'], 5);

    final driverDoc = await FirebaseFirestore.instance.collection('drivers').doc(driverUid).get();
    expect(driverDoc.data()!['ratingCount'], 1);
    expect(driverDoc.data()!['ratingSum'], 4);

    expect(customerUid, isNotNull); // sanity: captured in step 1, never null by here
  });
}
