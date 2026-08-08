import 'package:flutter_test/flutter_test.dart';

import 'package:delivery_app/core/stats/menu_item_tally.dart';
import 'package:delivery_app/models/order.dart';

DeliveryOrder _order(List<OrderItem> items) => DeliveryOrder(
      id: 'o',
      customerId: 'c',
      vendorId: 'v',
      items: items,
      status: OrderStatus.delivered,
      total: 0,
      deliveryAddress: 'addr',
      createdAt: DateTime(2024),
    );

OrderItem _item(String name, int quantity) => OrderItem(
      menuItemId: name,
      name: name,
      quantity: quantity,
      unitPrice: 1,
    );

void main() {
  test('tallyMenuItemQuantities sums quantities per item name across orders', () {
    final orders = [
      _order([_item('Falafel', 2), _item('Hummus', 1)]),
      _order([_item('Falafel', 3)]),
    ];

    final tally = tallyMenuItemQuantities(orders);

    expect(tally['Falafel'], 5);
    expect(tally['Hummus'], 1);
  });

  test('returns an empty map for an empty order list', () {
    expect(tallyMenuItemQuantities(const []), isEmpty);
  });
}
