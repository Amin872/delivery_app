import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:delivery_app/models/order.dart';
import 'package:delivery_app/models/review.dart';
import 'package:delivery_app/models/vendor.dart';
import 'package:delivery_app/services/firestore_service.dart';

Map<String, dynamic> _orderMap({
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

    await firestore
        .collection('orders')
        .add(_orderMap(vendorId: 'vendor-1', status: 'delivered', total: 100));
    await firestore.collection('orders').add(_orderMap(
          vendorId: 'vendor-1',
          status: 'delivered',
          total: 50,
          driverId: 'driver-1',
        ));
    await firestore
        .collection('orders')
        .add(_orderMap(vendorId: 'vendor-1', status: 'pending', total: 30));
    await firestore
        .collection('orders')
        .add(_orderMap(vendorId: 'vendor-2', status: 'delivered', total: 999));

    expect(await service.countVendorOrders('vendor-1'), 3);
    expect(await service.sumVendorDeliveredSales('vendor-1'), 150);
    expect(await service.countVendorDeliveredOrders('vendor-1'), 2);
    expect(await service.countDriverDeliveries('driver-1'), 1);
  });

  test('watchAllOrders returns every order unfiltered, and only matching ones when filtered',
      () async {
    final firestore = FakeFirebaseFirestore();
    final service = FirestoreService(firestore: firestore);

    await firestore
        .collection('orders')
        .add(_orderMap(vendorId: 'vendor-1', status: 'pending', total: 10));
    await firestore
        .collection('orders')
        .add(_orderMap(vendorId: 'vendor-2', status: 'delivered', total: 20));
    await firestore
        .collection('orders')
        .add(_orderMap(vendorId: 'vendor-3', status: 'delivered', total: 30));

    final all = await service.watchAllOrders().first;
    expect(all.length, 3);

    final delivered = await service.watchAllOrders(status: OrderStatus.delivered).first;
    expect(delivered.length, 2);
    expect(delivered.every((order) => order.status == OrderStatus.delivered), isTrue);
  });

  test('watchActiveDriverOrder resolves the in-flight order for a driver, or null', () async {
    final firestore = FakeFirebaseFirestore();
    final service = FirestoreService(firestore: firestore);

    // Delivered already — shouldn't count as "active".
    await firestore.collection('orders').add(_orderMap(
          vendorId: 'vendor-1',
          status: 'delivered',
          total: 20,
          driverId: 'driver-1',
        ));
    // Belongs to a different driver.
    await firestore.collection('orders').add(_orderMap(
          vendorId: 'vendor-1',
          status: 'delivering',
          total: 30,
          driverId: 'driver-2',
        ));

    expect(await service.watchActiveDriverOrder('driver-1').first, isNull);

    final activeRef = await firestore.collection('orders').add(_orderMap(
          vendorId: 'vendor-1',
          status: 'pickedUp',
          total: 40,
          driverId: 'driver-1',
        ));

    final active = await service.watchActiveDriverOrder('driver-1').first;
    expect(active?.id, activeRef.id);
    expect(active?.status, OrderStatus.pickedUp);
  });

  test('cancelOrder sets the order status to cancelled', () async {
    final firestore = FakeFirebaseFirestore();
    final service = FirestoreService(firestore: firestore);

    final orderRef = await firestore
        .collection('orders')
        .add(_orderMap(vendorId: 'vendor-1', status: 'pending', total: 10));

    await service.cancelOrder(orderRef.id);

    final updated = await orderRef.get();
    expect(updated.data()!['status'], 'cancelled');
  });

  test('updateVendorImage sets the vendor doc imageUrl', () async {
    final firestore = FakeFirebaseFirestore();
    final service = FirestoreService(firestore: firestore);

    final vendorRef = await firestore.collection('vendors').add({
      'ownerId': 'owner-1',
      'name': 'Falafel House',
      'description': '',
      'imageUrl': null,
      'isOpen': true,
      'approvalStatus': 'approved',
    });

    await service.updateVendorImage(vendorRef.id, 'https://example.com/photo.jpg');

    final updated = await vendorRef.get();
    expect(updated.data()!['imageUrl'], 'https://example.com/photo.jpg');
  });

  test('submitReview writes to reviews/{orderId}, and watchReviewForOrder resolves it', () async {
    final firestore = FakeFirebaseFirestore();
    final service = FirestoreService(firestore: firestore);

    expect(await service.watchReviewForOrder('order-1').first, isNull);

    final review = Review(
      id: 'order-1',
      orderId: 'order-1',
      customerId: 'customer-1',
      vendorId: 'vendor-1',
      driverId: 'driver-1',
      vendorRating: 5,
      driverRating: 4,
      comment: 'Great food!',
      createdAt: DateTime.now(),
    );
    await service.submitReview(review);

    final stored = await firestore.collection('reviews').doc('order-1').get();
    expect(stored.data()!['vendorRating'], 5);

    final watched = await service.watchReviewForOrder('order-1').first;
    expect(watched?.driverRating, 4);
    expect(watched?.comment, 'Great food!');
  });

  test('watchVendorReviews returns only that vendor\'s reviews, newest first', () async {
    final firestore = FakeFirebaseFirestore();
    final service = FirestoreService(firestore: firestore);

    Future<void> addReview(String orderId, String vendorId, DateTime createdAt) {
      return service.submitReview(Review(
        id: orderId,
        orderId: orderId,
        customerId: 'customer-1',
        vendorId: vendorId,
        driverId: 'driver-1',
        vendorRating: 3,
        driverRating: 3,
        createdAt: createdAt,
      ));
    }

    await addReview('order-1', 'vendor-1', DateTime(2024, 1, 1));
    await addReview('order-2', 'vendor-1', DateTime(2024, 1, 2));
    await addReview('order-3', 'vendor-2', DateTime(2024, 1, 3));

    final reviews = await service.watchVendorReviews('vendor-1').first;
    expect(reviews.map((r) => r.id).toList(), ['order-2', 'order-1']);
  });
}
