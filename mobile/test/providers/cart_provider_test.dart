import 'package:flutter_test/flutter_test.dart';

import 'package:delivery_app/features/customer/providers/cart_provider.dart';
import 'package:delivery_app/models/vendor.dart';

MenuItem _item(String id, {double price = 10}) => MenuItem(
      id: id,
      vendorId: 'vendor-1',
      name: 'Item $id',
      price: price,
      available: true,
    );

void main() {
  group('CartController', () {
    test('adding an item from an empty cart sets the vendor and quantity 1', () {
      final controller = CartController();
      final added = controller.addItem('vendor-1', 'Vendor One', _item('a'));

      expect(added, isTrue);
      expect(controller.state.vendorId, 'vendor-1');
      expect(controller.state.itemCount, 1);
      expect(controller.state.total, 10);
    });

    test('adding the same item twice increments its quantity', () {
      final controller = CartController();
      controller.addItem('vendor-1', 'Vendor One', _item('a'));
      controller.addItem('vendor-1', 'Vendor One', _item('a'));

      expect(controller.state.lines['a']!.quantity, 2);
      expect(controller.state.itemCount, 2);
    });

    test('adding an item from a different vendor is rejected without changing state', () {
      final controller = CartController();
      controller.addItem('vendor-1', 'Vendor One', _item('a'));

      final added = controller.addItem('vendor-2', 'Vendor Two', _item('b', price: 5));

      expect(added, isFalse);
      expect(controller.state.vendorId, 'vendor-1');
      expect(controller.state.lines.containsKey('b'), isFalse);
    });

    test('replaceWithItem clears the cart and starts a new vendor cart', () {
      final controller = CartController();
      controller.addItem('vendor-1', 'Vendor One', _item('a'));

      controller.replaceWithItem('vendor-2', 'Vendor Two', _item('b', price: 5));

      expect(controller.state.vendorId, 'vendor-2');
      expect(controller.state.lines.keys, ['b']);
      expect(controller.state.total, 5);
    });

    test('setQuantity to zero removes the item', () {
      final controller = CartController();
      controller.addItem('vendor-1', 'Vendor One', _item('a'));

      controller.setQuantity('a', 0);

      expect(controller.state.isEmpty, isTrue);
      expect(controller.state.vendorId, isNull);
    });

    test('removeItem removes just that line, keeping others', () {
      final controller = CartController();
      controller.addItem('vendor-1', 'Vendor One', _item('a'));
      controller.addItem('vendor-1', 'Vendor One', _item('b', price: 20));

      controller.removeItem('a');

      expect(controller.state.lines.containsKey('a'), isFalse);
      expect(controller.state.lines.containsKey('b'), isTrue);
      expect(controller.state.total, 20);
    });

    test('clear empties the cart', () {
      final controller = CartController();
      controller.addItem('vendor-1', 'Vendor One', _item('a'));

      controller.clear();

      expect(controller.state.isEmpty, isTrue);
    });
  });
}
