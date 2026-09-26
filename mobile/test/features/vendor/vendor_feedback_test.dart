import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:delivery_app/features/customer/screens/customer_home_screen.dart'
    show allCitiesProvider, firestoreServiceProvider;
import 'package:delivery_app/features/customer/screens/vendor_menu_screen.dart' show vendorMenuProvider;
import 'package:delivery_app/features/vendor/screens/menu_management_screen.dart';
import 'package:delivery_app/features/vendor/screens/vendor_dashboard_screen.dart';
import 'package:delivery_app/l10n/app_localizations.dart';
import 'package:delivery_app/models/approval_status.dart';
import 'package:delivery_app/models/city.dart';
import 'package:delivery_app/models/order.dart';
import 'package:delivery_app/models/vendor.dart';
import 'package:delivery_app/services/firestore_service.dart';

import '../../support/real_theme_harness.dart';

/// Every vendor write this screen makes fails, with a message that must
/// never reach the user verbatim.
class _FailingFirestoreService extends FirestoreService {
  _FailingFirestoreService() : super(firestore: FakeFirebaseFirestore());

  static const rawError = 'permission-denied: raw backend detail';

  @override
  Future<void> setVendorOpen(String vendorId, bool isOpen) async => throw Exception(rawError);

  @override
  Future<void> updateMenuItem(String vendorId, MenuItem item) async => throw Exception(rawError);

  @override
  Future<void> deleteMenuItem(String vendorId, String itemId) async => throw Exception(rawError);
}

const _vendor = Vendor(
  id: 'v',
  ownerId: 'v',
  name: 'Test Kitchen',
  description: '',
  isOpen: false,
  approvalStatus: ApprovalStatus.approved,
  etaMinMinutes: 20,
  etaMaxMinutes: 40,
);

final _l10n = lookupAppLocalizations(const Locale('en'));

Future<void> _pump(WidgetTester tester, Widget screen) async {
  await pumpWithRealTheme(tester, screen, locale: const Locale('en'), overrides: [
    firestoreServiceProvider.overrideWithValue(_FailingFirestoreService()),
    vendorSelfProvider('v').overrideWith((ref) => Stream.value(_vendor)),
    vendorOrdersProvider('v').overrideWith((ref) => Stream.value(const <DeliveryOrder>[])),
    vendorMenuProvider('v').overrideWith((ref) => Stream.value(const [
          MenuItem(id: 'a', vendorId: 'v', name: 'Falafel', price: 3000, available: true),
        ])),
    allCitiesProvider.overrideWith((ref) => Stream.value(const <CityOption>[])),
  ]);
  await tester.pumpAndSettle();
}

/// A localized error snackbar is showing, without the raw exception text.
void _expectLocalizedErrorSnackBar() {
  expect(find.byType(SnackBar), findsOneWidget);
  expect(find.textContaining('permission-denied'), findsNothing);
  expect(find.textContaining('raw backend detail'), findsNothing);
}

void main() {
  testWidgets('a failed open/closed switch shows a localized error', (tester) async {
    await _pump(tester, const VendorDashboardScreen(vendorId: 'v'));
    await tester.tap(find.byKey(const ValueKey('vendor_open_switch')));
    await tester.pumpAndSettle();
    _expectLocalizedErrorSnackBar();
  });

  testWidgets('a failed availability toggle shows a localized error', (tester) async {
    await _pump(tester, const MenuManagementScreen(vendorId: 'v'));
    await tester.tap(find.byKey(const ValueKey('menu_item_available_a')));
    await tester.pumpAndSettle();
    _expectLocalizedErrorSnackBar();
  });

  testWidgets('a failed delete shows a localized error after confirmation', (tester) async {
    await _pump(tester, const MenuManagementScreen(vendorId: 'v'));
    await tester.tap(find.byKey(const ValueKey('menu_item_actions_a')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_l10n.deleteTooltip));
    await tester.pumpAndSettle();
    expect(find.text(_l10n.deleteMenuItemConfirmMessage), findsOneWidget);
    await tester.tap(find.text(_l10n.confirmButton));
    await tester.pumpAndSettle();
    _expectLocalizedErrorSnackBar();
    expect(find.byKey(const ValueKey('menu_item_a')), findsOneWidget);
  });

  testWidgets('an out-of-order ETA gets the ETA message, not "invalid price"', (tester) async {
    await _pump(tester, const VendorDashboardScreen(vendorId: 'v'));
    await tester.tap(find.byKey(const ValueKey('vendor_more_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_l10n.editStoreDetailsTooltip));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, _l10n.etaMinFieldLabel), '50');
    await tester.enterText(find.widgetWithText(TextFormField, _l10n.etaMaxFieldLabel), '20');
    final save = find.text(_l10n.saveButton);
    await tester.scrollUntilVisible(save, 150,
        scrollable: find.descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable)).first);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(find.text(_l10n.invalidEtaError, skipOffstage: false), findsWidgets);
    expect(find.text(_l10n.invalidPriceError, skipOffstage: false), findsNothing);
  });
}
