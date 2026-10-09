import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:delivery_app/core/format/display_formatters.dart';
import 'package:delivery_app/core/widgets/state_views.dart';
import 'package:delivery_app/features/admin/screens/admin_driver_detail_screen.dart';
import 'package:delivery_app/features/admin/screens/admin_order_detail_screen.dart';
import 'package:delivery_app/models/app_user.dart';
import 'package:delivery_app/models/order.dart';
import 'package:delivery_app/services/firestore_service.dart';

import 'admin_test_harness.dart';

/// The first subscription to an order or a user fails (as a dropped
/// connection would); every later one is the real stream — so the screen's
/// Retry is what recovers.
class _FlakyService extends FirestoreService {
  _FlakyService(FakeFirebaseFirestore db) : super(firestore: db);

  int orderSubscriptions = 0;
  int userSubscriptions = 0;

  @override
  Stream<DeliveryOrder> watchOrder(String orderId) {
    orderSubscriptions++;
    if (orderSubscriptions == 1) return Stream.error(Exception('unavailable'));
    return super.watchOrder(orderId);
  }

  @override
  Stream<AppUser> watchUser(String userId) {
    userSubscriptions++;
    if (userSubscriptions == 1) return Stream.error(Exception('unavailable'));
    return super.watchUser(userId);
  }
}

Future<FakeFirebaseFirestore> _db() async {
  final db = FakeFirebaseFirestore();
  await db.collection('orders').doc('order-abc123').set(DeliveryOrder(
        id: 'order-abc123',
        customerId: 'customer-1',
        vendorId: 'vendor-1',
        items: const [],
        status: OrderStatus.delivered,
        total: 1000,
        deliveryAddress: 'Mezzeh',
        createdAt: DateTime(2026, 9, 1),
      ).toMap());
  await db.collection('users').doc('driver-1').set({
    'email': 'driver@example.com',
    'displayName': 'Driver One',
    'role': 'driver',
    'phoneNumber': '0944123456',
  });
  await db.collection('drivers').doc('driver-1').set({
    'userId': 'driver-1',
    'isAvailable': true,
    'approvalStatus': 'approved',
  });
  return db;
}

void main() {
  testWidgets('order detail: a failed load shows the shared error state, and Retry recovers', (tester) async {
    final db = await _db();
    final service = _FlakyService(db);
    await pumpAdminScreen(tester, const AdminOrderDetailScreen(orderId: 'order-abc123'), db, service: service);

    expect(find.byType(ErrorState), findsOneWidget);
    // The AppBar shows the short order reference, not the raw id.
    expect(find.text(adminTestL10n.orderLabel(displayOrderId('order-abc123'))), findsOneWidget);

    await tester.tap(find.text(adminTestL10n.retryButton));
    await tester.pumpAndSettle();
    expect(find.byType(ErrorState), findsNothing);
    expect(find.text('Mezzeh'), findsOneWidget);
  });

  testWidgets('driver detail: a failed load shows the shared error state, and Retry recovers', (tester) async {
    final db = await _db();
    final service = _FlakyService(db);
    await pumpAdminScreen(tester, const AdminDriverDetailScreen(driverId: 'driver-1'), db, service: service);

    expect(find.byType(ErrorState), findsOneWidget);
    await tester.tap(find.text(adminTestL10n.retryButton));
    await tester.pumpAndSettle();

    expect(find.byType(ErrorState), findsNothing);
    expect(find.text('driver@example.com'), findsOneWidget);
    // Phone is grouped and bidi-isolated by the shared formatter.
    expect(find.text(formatPhone('0944123456')), findsOneWidget);
  });
}
