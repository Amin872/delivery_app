import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:delivery_app/core/widgets/gradient_button.dart';
import 'package:delivery_app/core/widgets/star_rating.dart';
import 'package:delivery_app/features/auth/providers/auth_provider.dart';
import 'package:delivery_app/features/auth/providers/session_provider.dart';
import 'package:delivery_app/features/auth/widgets/require_sign_in.dart';
import 'package:delivery_app/features/customer/providers/cart_provider.dart';
import 'package:delivery_app/features/customer/screens/account_screen.dart';
import 'package:delivery_app/features/customer/screens/cart_screen.dart';
import 'package:delivery_app/features/customer/screens/customer_home_screen.dart';
import 'package:delivery_app/features/customer/screens/delivery_addresses_screen.dart';
import 'package:delivery_app/features/customer/screens/vendor_menu_screen.dart';
import 'package:delivery_app/features/customer/widgets/store_info_section.dart';
import 'package:delivery_app/features/driver/screens/driver_home_screen.dart' show functionsServiceProvider;
import 'package:delivery_app/l10n/app_localizations.dart';
import 'package:delivery_app/models/app_user.dart';
import 'package:delivery_app/models/approval_status.dart';
import 'package:delivery_app/models/city.dart';
import 'package:delivery_app/models/review.dart';
import 'package:delivery_app/models/vendor.dart';
import 'package:delivery_app/services/firestore_service.dart';
import 'package:delivery_app/services/functions_service.dart';

import '../../support/real_theme_harness.dart';

class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

/// Records createOrder calls; a guest must never reach it.
class _RecordingFunctions extends FunctionsService {
  _RecordingFunctions() : super(functions: _MockFirebaseFunctions());

  int calls = 0;

  @override
  Future<PlacedOrder> createOrder({
    required String vendorId,
    required List<OrderLineRequest> items,
    required String addressId,
  }) async {
    calls++;
    throw Exception('a guest must never place an order');
  }
}

final _l10n = lookupAppLocalizations(const Locale('en'));

const _customer =
    AppUser(id: 'c1', email: 'c@example.com', displayName: 'C', role: UserRole.customer);

const _vendor = Vendor(
  id: 'v1',
  ownerId: 'owner-1',
  name: 'Falafel House',
  description: 'Falafel and more',
  isOpen: true,
  approvalStatus: ApprovalStatus.approved,
  category: VendorCategory.restaurants,
  ratingSum: 27,
  ratingCount: 6,
);

const _falafel =
    MenuItem(id: 'falafel', vendorId: 'v1', name: 'Falafel wrap', price: 2000, available: true);

Future<FakeFirebaseFirestore> _seed() async {
  final db = FakeFirebaseFirestore();
  await db.collection('vendors').doc(_vendor.id).set(_vendor.toMap());
  await db
      .collection('vendors')
      .doc(_vendor.id)
      .collection('menuItems')
      .doc(_falafel.id)
      .set(_falafel.toMap());
  return db;
}

class _Probe {
  int signInLaunches = 0;
  int reviewQueries = 0;
  final functions = _RecordingFunctions();
}

/// Pumps [screen] as a confirmed guest ([user] null, session guest) or as a
/// signed-in customer, with the sign-in launcher and the detailed reviews
/// provider recorded instead of reaching Firebase.
Future<_Probe> _pump(
  WidgetTester tester,
  Widget screen, {
  AppUser? user,
  bool withCart = false,
}) async {
  final db = await _seed();
  final probe = _Probe();
  await pumpWithRealTheme(
    tester,
    screen,
    locale: const Locale('en'),
    width: 393,
    height: 2000,
    overrides: [
      firestoreServiceProvider.overrideWithValue(FirestoreService(firestore: db)),
      functionsServiceProvider.overrideWithValue(probe.functions),
      allCitiesProvider.overrideWith((ref) => Stream.value(const <CityOption>[])),
      currentAppUserProvider.overrideWith((ref) => Stream.value(user)),
      sessionProvider.overrideWithValue(
        user == null ? const SessionGuest() : SessionReady(user),
      ),
      signInLauncherProvider.overrideWithValue((context) => probe.signInLaunches++),
      vendorReviewsProvider.overrideWith((ref, vendorId) {
        probe.reviewQueries++;
        return Stream.value(const <Review>[]);
      }),
      if (withCart)
        cartProvider.overrideWith(
          (ref) => CartController()..addItem(_vendor.id, _vendor.name, _falafel),
        ),
    ],
  );
  await _settle(tester);
  return probe;
}

/// Network-image shimmers never settle, so pump in fixed steps.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder get _prompt => find.byKey(const ValueKey('sign_in_prompt'));

Future<void> _tapAndSettle(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await _settle(tester);
}

void main() {
  group('customer home, as a guest', () {
    testWidgets('shows the public catalog', (tester) async {
      await _pump(tester, const CustomerHomeScreen());

      expect(find.text(_vendor.name), findsWidgets);
      expect(_prompt, findsNothing);
    });

    testWidgets('the account button asks the guest to sign in', (tester) async {
      final probe = await _pump(tester, const CustomerHomeScreen());

      await _tapAndSettle(tester, find.byTooltip(_l10n.accountTitle).first);

      expect(_prompt, findsOneWidget);
      expect(find.byType(AccountScreen), findsNothing);

      await _tapAndSettle(tester, find.byKey(const ValueKey('sign_in_prompt_confirm')));
      expect(probe.signInLaunches, 1);
    });

    testWidgets('a signed-in customer still opens their account directly', (tester) async {
      final probe = await _pump(tester, const CustomerHomeScreen(), user: _customer);

      await _tapAndSettle(tester, find.byTooltip(_l10n.accountTitle).first);

      expect(_prompt, findsNothing);
      expect(find.byType(AccountScreen), findsOneWidget);
      expect(probe.signInLaunches, 0);
    });
  });

  group('vendor menu, as a guest', () {
    testWidgets('shows the menu and the aggregate rating', (tester) async {
      await _pump(tester, const VendorMenuScreen(vendor: _vendor));

      expect(find.text(_falafel.name), findsWidgets);
      expect(
        find.descendant(of: find.byType(StoreInfoSection), matching: find.byType(StarRatingDisplay)),
        findsOneWidget,
      );
    });

    testWidgets('never queries detailed reviews; shows a sign-in prompt instead',
        (tester) async {
      final probe = await _pump(tester, const VendorMenuScreen(vendor: _vendor));

      expect(probe.reviewQueries, 0);
      final reviewsPrompt = find.byKey(const ValueKey('reviews_sign_in_prompt'));
      await tester.ensureVisible(reviewsPrompt);
      await tester.pump();
      expect(reviewsPrompt, findsOneWidget);
      expect(find.text(_l10n.reviewsSignInMessage), findsOneWidget);
      expect(find.text(_l10n.noReviewsMessage), findsNothing);

      await _tapAndSettle(tester, find.byKey(const ValueKey('reviews_sign_in_button')));
      expect(_prompt, findsOneWidget);
      expect(probe.reviewQueries, 0);
    });

    testWidgets('the favorite button asks the guest to sign in', (tester) async {
      final probe = await _pump(tester, const VendorMenuScreen(vendor: _vendor));

      await _tapAndSettle(tester, find.byTooltip(_l10n.favoriteTooltip).first);
      expect(_prompt, findsOneWidget);

      await _tapAndSettle(tester, find.byKey(const ValueKey('sign_in_prompt_confirm')));
      expect(probe.signInLaunches, 1);
    });

    testWidgets('a signed-in customer still gets the detailed reviews, no prompt',
        (tester) async {
      final probe = await _pump(tester, const VendorMenuScreen(vendor: _vendor), user: _customer);

      expect(probe.reviewQueries, greaterThan(0));
      expect(find.byKey(const ValueKey('reviews_sign_in_prompt')), findsNothing);
      await tester.ensureVisible(find.text(_l10n.noReviewsMessage));
      expect(find.text(_l10n.noReviewsMessage), findsOneWidget);
    });
  });

  group('cart, as a guest', () {
    testWidgets('Place order stays enabled and asks the guest to sign in; nothing is sent',
        (tester) async {
      final probe = await _pump(tester, const CartScreen(), withCart: true);
      final placeOrder = find.byKey(const ValueKey('cart_place_order_button'));

      expect(tester.widget<GradientButton>(placeOrder).onPressed, isNotNull);
      await _tapAndSettle(tester, placeOrder);

      expect(_prompt, findsOneWidget);
      expect(probe.functions.calls, 0);

      await _tapAndSettle(tester, find.byKey(const ValueKey('sign_in_prompt_confirm')));
      expect(probe.signInLaunches, 1);
      expect(probe.functions.calls, 0);
    });

    testWidgets('changing the address asks the guest to sign in and opens no address book',
        (tester) async {
      final probe = await _pump(tester, const CartScreen(), withCart: true);

      await _tapAndSettle(tester, find.byKey(const ValueKey('cart_address_field')));

      expect(_prompt, findsOneWidget);
      expect(find.byType(DeliveryAddressesScreen), findsNothing);

      await _tapAndSettle(tester, find.byKey(const ValueKey('sign_in_prompt_cancel')));
      expect(_prompt, findsNothing);
      expect(probe.signInLaunches, 0);
      expect(find.byType(DeliveryAddressesScreen), findsNothing);
    });
  });
}
