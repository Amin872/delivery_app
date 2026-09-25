import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:delivery_app/core/providers/formatters_provider.dart';
import 'package:delivery_app/core/providers/preferences_provider.dart';
import 'package:delivery_app/features/vendor/screens/vendor_dashboard_screen.dart';
import 'package:delivery_app/l10n/app_localizations.dart';
import 'package:delivery_app/models/approval_status.dart';
import 'package:delivery_app/models/order.dart';
import 'package:delivery_app/models/vendor.dart';

Vendor _vendor(ApprovalStatus status) => Vendor(
      id: 'vendor-1',
      ownerId: 'vendor-1',
      name: 'Test Kitchen',
      description: '',
      isOpen: false,
      approvalStatus: status,
    );

Future<void> _pump(WidgetTester tester, ApprovalStatus status) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        currencyFormatProvider.overrideWithValue(NumberFormat.currency(locale: 'en', name: 'SYP')),
        vendorSelfProvider('vendor-1').overrideWith((ref) => Stream.value(_vendor(status))),
        vendorOrdersProvider('vendor-1')
            .overrideWith((ref) => Stream.value(const <DeliveryOrder>[])),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const VendorDashboardScreen(vendorId: 'vendor-1'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('approved: the normal dashboard with orders, stats and setup actions', (tester) async {
    await _pump(tester, ApprovalStatus.approved);

    expect(find.text('Incoming orders'), findsOneWidget);
    expect(find.text('No orders yet.'), findsOneWidget);
    expect(find.byTooltip('Sales & orders'), findsOneWidget);
    expect(find.byTooltip('Manage menu'), findsOneWidget);
    expect(find.byKey(const ValueKey('vendor_open_switch')), findsOneWidget);
    expect(find.text('Pending approval'), findsNothing);
    expect(find.text('Store not approved'), findsNothing);
  });

  testWidgets('pending: approval notice instead of orders; store setup still available',
      (tester) async {
    await _pump(tester, ApprovalStatus.pending);

    expect(find.byKey(const ValueKey('vendor_approval_pending')), findsOneWidget);
    expect(find.text('Pending approval'), findsOneWidget);
    expect(find.text('No orders yet.'), findsNothing);
    expect(find.byTooltip('Sales & orders'), findsNothing);
    // Setup actions a new vendor needs before approval (E2E scenario 2 uses these).
    expect(find.byKey(const ValueKey('vendor_open_switch')), findsOneWidget);
    expect(find.byTooltip('Manage menu'), findsOneWidget);
    expect(find.byTooltip('Edit store details'), findsOneWidget);
    expect(find.byTooltip('Sign out'), findsOneWidget);
  });

  testWidgets('rejected: rejection notice with no operational actions, but sign-out remains',
      (tester) async {
    await _pump(tester, ApprovalStatus.rejected);

    expect(find.byKey(const ValueKey('vendor_approval_rejected')), findsOneWidget);
    expect(find.text('Store not approved'), findsOneWidget);
    expect(find.text('No orders yet.'), findsNothing);
    expect(find.byKey(const ValueKey('vendor_open_switch')), findsNothing);
    expect(find.byTooltip('Manage menu'), findsNothing);
    expect(find.byTooltip('Edit store details'), findsNothing);
    expect(find.byTooltip('Change storefront photo'), findsNothing);
    expect(find.byTooltip('Sales & orders'), findsNothing);
    expect(find.byTooltip('Sign out'), findsOneWidget);
  });
}
