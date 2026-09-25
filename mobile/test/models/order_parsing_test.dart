import 'package:flutter_test/flutter_test.dart';

import 'package:delivery_app/models/order.dart';

void main() {
  // An order document as written before the pricing breakdown and vendor
  // snapshot fields existed.
  Map<String, dynamic> legacyOrderMap() => {
        'customerId': 'customer-1',
        'vendorId': 'vendor-1',
        'driverId': null,
        'items': [
          {'menuItemId': 'item-1', 'name': 'Falafel', 'quantity': 2, 'unitPrice': 5000},
        ],
        'status': 'delivered',
        'total': 10000,
        'deliveryAddress': '123 Main St',
        'createdAt': 1700000000000,
      };

  test('round-trips pricing breakdown and vendor snapshot fields', () {
    final order = DeliveryOrder(
      id: 'order-1',
      customerId: 'customer-1',
      vendorId: 'vendor-1',
      items: const [
        OrderItem(menuItemId: 'item-1', name: 'Falafel', quantity: 2, unitPrice: 5000),
      ],
      status: OrderStatus.pending,
      total: 11500,
      deliveryAddress: '123 Main St',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      subtotal: 10000,
      deliveryFee: 1500,
      vendorName: 'Abu Kamal Falafel',
      pickupAddress: 'Hamra St, Damascus',
      pickupLatitude: 33.5138,
      pickupLongitude: 36.2765,
    );

    final restored = DeliveryOrder.fromMap(order.id, order.toMap());

    expect(restored.subtotal, 10000);
    expect(restored.deliveryFee, 1500);
    expect(restored.total, 11500);
    expect(restored.vendorName, 'Abu Kamal Falafel');
    expect(restored.pickupAddress, 'Hamra St, Damascus');
    expect(restored.pickupLatitude, 33.5138);
    expect(restored.pickupLongitude, 36.2765);
    expect(restored.effectiveSubtotal, 10000);
    expect(restored.effectiveDeliveryFee, 1500);
  });

  test('parses a legacy order without any of the new fields', () {
    final order = DeliveryOrder.fromMap('order-1', legacyOrderMap());

    expect(order.total, 10000);
    expect(order.status, OrderStatus.delivered);
    expect(order.subtotal, isNull);
    expect(order.deliveryFee, isNull);
    expect(order.vendorName, isNull);
    expect(order.pickupAddress, isNull);
    expect(order.pickupLatitude, isNull);
    expect(order.pickupLongitude, isNull);
  });

  test('legacy order: subtotal falls back to total, delivery fee to 0', () {
    final order = DeliveryOrder.fromMap('order-1', legacyOrderMap());

    expect(order.effectiveSubtotal, 10000);
    expect(order.effectiveDeliveryFee, 0);
    // The fallback is read-side only — nothing is synthesized into the
    // stored fields, so re-serializing never invents a subtotal.
    expect(order.toMap()['subtotal'], isNull);
    expect(order.toMap()['deliveryFee'], isNull);
  });

  test('numeric fields stored as ints parse as doubles', () {
    final order = DeliveryOrder.fromMap('order-1', {
      ...legacyOrderMap(),
      'subtotal': 10000,
      'deliveryFee': 0,
      'pickupLatitude': 33,
      'pickupLongitude': 36,
    });

    expect(order.subtotal, 10000.0);
    expect(order.deliveryFee, 0.0);
    expect(order.effectiveDeliveryFee, 0.0);
    expect(order.pickupLatitude, 33.0);
    expect(order.pickupLongitude, 36.0);
  });
}
