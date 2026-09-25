import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'package:delivery_app/core/providers/formatters_provider.dart';
import 'package:delivery_app/features/auth/providers/auth_provider.dart';
import 'package:delivery_app/features/customer/screens/my_orders_screen.dart';
import 'package:delivery_app/features/customer/screens/order_tracking_screen.dart';
import 'package:delivery_app/features/customer/widgets/driver_tracking_map.dart';
import 'package:delivery_app/l10n/app_localizations.dart';
import 'package:delivery_app/models/app_user.dart';
import 'package:delivery_app/models/order.dart';

// Arabic (RTL), a 320dp-wide phone and 1.3× text, with long names and
// realistic Syrian-pound amounts — any RenderFlex overflow fails the test.
// (This caught the price breakdown's fixed-width amount overflowing.)

final _order = DeliveryOrder(
  id: 'o1',
  customerId: 'c1',
  vendorId: 'v1',
  driverId: 'd1',
  items: const [
    OrderItem(menuItemId: 'a', name: 'فلافل مع صحن حمص كبير جداً وخبز', quantity: 12, unitPrice: 1234567),
  ],
  status: OrderStatus.pickedUp,
  total: 99999999,
  subtotal: 99000000,
  deliveryFee: 999999,
  deliveryAddress: 'المزة، بناء ٤، الطابق الثالث بجانب الصيدلية الكبيرة',
  deliveryInstructions: 'الطابق الثالث، البوابة الزرقاء بجانب الصيدلية الكبيرة في آخر الشارع',
  driverNote: 'اتصل عند الوصول',
  vendorName: 'مطعم الفلافل الذهبي للمأكولات الشامية الأصيلة',
  createdAt: DateTime(2026, 9, 22, 18, 30),
);

Future<void> _pump(WidgetTester tester, Widget home, List<Override> overrides) async {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currencyFormatProvider.overrideWithValue(NumberFormat.currency(locale: 'ar', name: 'SYP')),
        dateTimeFormatProvider.overrideWithValue(DateFormat.yMd('ar').add_Hm()),
        currentAppUserProvider.overrideWith((ref) => Stream.value(
              const AppUser(id: 'c1', email: 'c@example.com', displayName: 'C', role: UserRole.customer),
            )),
        ...overrides,
      ],
      child: MaterialApp(
        locale: const Locale('ar'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('ar'));

  testWidgets('OrderTrackingScreen lays out without overflow, scrolled end to end', (tester) async {
    await _pump(tester, const OrderTrackingScreen(orderId: 'o1'), [
      orderTrackingProvider('o1').overrideWith((ref) => Stream.value(_order)),
      reviewForOrderProvider('o1').overrideWith((ref) => Stream.value(null)),
      driverOrderLocationProvider('o1').overrideWith((ref) => Stream.value(null)),
    ]);

    for (var i = 0; i < 12; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const ValueKey('order_summary')), findsOneWidget);
  });

  testWidgets('MyOrdersScreen lays out without overflow', (tester) async {
    await _pump(tester, const MyOrdersScreen(customerId: 'c1'), [
      customerOrdersProvider('c1').overrideWith((ref) => Stream.value([_order])),
    ]);

    expect(find.text(_order.vendorName!), findsOneWidget);
  });
}
