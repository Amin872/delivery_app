// Basic model round-trip tests. Widget tests that build DeliveryApp require
// Firebase.initializeApp(), which needs the Firebase emulator suite or a
// configured project — see integration_test/ for those instead.

import 'package:flutter_test/flutter_test.dart';

import 'package:delivery_app/models/app_user.dart';
import 'package:delivery_app/models/order.dart';

void main() {
  test('AppUser round-trips through toMap/fromMap', () {
    const user = AppUser(
      id: 'user-1',
      email: 'driver@example.com',
      displayName: 'Alex Driver',
      role: UserRole.driver,
      phoneNumber: '+15551234567',
    );

    final restored = AppUser.fromMap(user.id, user.toMap());

    expect(restored.id, user.id);
    expect(restored.email, user.email);
    expect(restored.displayName, user.displayName);
    expect(restored.role, user.role);
    expect(restored.phoneNumber, user.phoneNumber);
  });

  test('DeliveryOrder round-trips through toMap/fromMap, including proofImageUrl', () {
    final order = DeliveryOrder(
      id: 'order-1',
      customerId: 'customer-1',
      vendorId: 'vendor-1',
      driverId: 'driver-1',
      items: const [
        OrderItem(menuItemId: 'item-1', name: 'Falafel', quantity: 2, unitPrice: 5000),
      ],
      status: OrderStatus.delivered,
      total: 10000,
      deliveryAddress: '123 Main St',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      proofImageUrl: 'https://example.com/proof.jpg',
    );

    final restored = DeliveryOrder.fromMap(order.id, order.toMap());

    expect(restored.id, order.id);
    expect(restored.customerId, order.customerId);
    expect(restored.vendorId, order.vendorId);
    expect(restored.driverId, order.driverId);
    expect(restored.items.length, 1);
    expect(restored.status, order.status);
    expect(restored.total, order.total);
    expect(restored.deliveryAddress, order.deliveryAddress);
    expect(restored.createdAt, order.createdAt);
    expect(restored.proofImageUrl, order.proofImageUrl);
  });
}
