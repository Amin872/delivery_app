import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:delivery_app/models/vendor.dart';
import 'package:delivery_app/services/firestore_service.dart';

void main() {
  test('addMenuItem then deleteMenuItem round-trips through Firestore', () async {
    final firestore = FakeFirebaseFirestore();
    final service = FirestoreService(firestore: firestore);

    final itemId = await service.addMenuItem(
      'vendor-1',
      const MenuItem(
        id: '',
        vendorId: 'vendor-1',
        name: 'Falafel',
        price: 5000,
        available: true,
      ),
    );

    final stored = await firestore
        .collection('vendors')
        .doc('vendor-1')
        .collection('menuItems')
        .doc(itemId)
        .get();
    expect(stored.exists, isTrue);
    expect(stored.data()!['name'], 'Falafel');

    await service.deleteMenuItem('vendor-1', itemId);

    final afterDelete = await firestore
        .collection('vendors')
        .doc('vendor-1')
        .collection('menuItems')
        .doc(itemId)
        .get();
    expect(afterDelete.exists, isFalse);
  });

  test('vendor/driver aggregation methods return expected counts and sums', () async {
    final firestore = FakeFirebaseFirestore();
    final service = FirestoreService(firestore: firestore);

    Map<String, dynamic> orderMap({
      required String vendorId,
      String? driverId,
      required String status,
      required double total,
    }) {
      return {
        'customerId': 'customer-1',
        'vendorId': vendorId,
        'driverId': driverId,
        'items': <Map<String, dynamic>>[],
        'status': status,
        'total': total,
        'deliveryAddress': 'addr',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      };
    }

    await firestore
        .collection('orders')
        .add(orderMap(vendorId: 'vendor-1', status: 'delivered', total: 100));
    await firestore.collection('orders').add(orderMap(
          vendorId: 'vendor-1',
          status: 'delivered',
          total: 50,
          driverId: 'driver-1',
        ));
    await firestore
        .collection('orders')
        .add(orderMap(vendorId: 'vendor-1', status: 'pending', total: 30));
    await firestore
        .collection('orders')
        .add(orderMap(vendorId: 'vendor-2', status: 'delivered', total: 999));

    expect(await service.countVendorOrders('vendor-1'), 3);
    expect(await service.sumVendorDeliveredSales('vendor-1'), 150);
    expect(await service.countVendorDeliveredOrders('vendor-1'), 2);
    expect(await service.countDriverDeliveries('driver-1'), 1);
  });
}
