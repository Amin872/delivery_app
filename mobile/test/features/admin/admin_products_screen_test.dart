import 'package:flutter_test/flutter_test.dart';

import 'package:delivery_app/features/admin/screens/admin_products_screen.dart';
import 'package:delivery_app/models/vendor.dart';

Vendor _vendor(String id, String name) {
  return Vendor(
    id: id,
    ownerId: 'owner-$id',
    name: name,
    description: '',
    isOpen: true,
    approvalStatus: VendorApprovalStatus.approved,
  );
}

MenuItem _item(String id, String vendorId, {String name = 'Item', bool available = true}) {
  return MenuItem(id: id, vendorId: vendorId, name: name, price: 1000, available: available);
}

void main() {
  test('buildProductRows joins each item with its vendor name', () {
    final rows = buildProductRows(
      [_item('item-1', 'vendor-1', name: 'Falafel'), _item('item-2', 'vendor-2', name: 'Pizza')],
      [_vendor('vendor-1', 'Green Grocer'), _vendor('vendor-2', 'Pizza Place')],
    );

    expect(rows.length, 2);
    expect(rows.firstWhere((r) => r.itemId == 'item-1').vendorName, 'Green Grocer');
    expect(rows.firstWhere((r) => r.itemId == 'item-2').vendorName, 'Pizza Place');
  });

  test('buildProductRows falls back to an empty vendor name when the vendor is missing', () {
    final rows = buildProductRows([_item('item-1', 'vendor-missing')], []);

    expect(rows.single.vendorName, '');
    expect(rows.single.itemId, 'item-1');
  });

  test('buildProductRows carries availability through unchanged', () {
    final rows = buildProductRows(
      [_item('item-1', 'vendor-1', available: true), _item('item-2', 'vendor-1', available: false)],
      [_vendor('vendor-1', 'Shop')],
    );

    expect(rows.firstWhere((r) => r.itemId == 'item-1').available, isTrue);
    expect(rows.firstWhere((r) => r.itemId == 'item-2').available, isFalse);
  });

  test('buildProductRows returns an empty list for an empty item list', () {
    expect(buildProductRows([], [_vendor('vendor-1', 'Shop')]), isEmpty);
  });
}
