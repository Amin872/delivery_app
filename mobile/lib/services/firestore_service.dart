import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/order.dart';
import '../models/vendor.dart';

/// Thin wrapper around Firestore collections used across features.
///
/// Keeping collection names and query shapes here avoids scattering
/// raw string literals through the UI layer.
class FirestoreService {
  FirestoreService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _orders =>
      _db.collection('orders');

  CollectionReference<Map<String, dynamic>> get _vendors =>
      _db.collection('vendors');

  Stream<List<Vendor>> watchOpenVendors() {
    return _vendors.where('isOpen', isEqualTo: true).snapshots().map(
          (snap) => snap.docs
              .map((doc) => Vendor.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }

  Stream<List<MenuItem>> watchMenu(String vendorId) {
    return _vendors
        .doc(vendorId)
        .collection('menuItems')
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => MenuItem.fromMap(doc.id, doc.data()))
            .toList());
  }

  Stream<DeliveryOrder> watchOrder(String orderId) {
    return _orders
        .doc(orderId)
        .snapshots()
        .map((doc) => DeliveryOrder.fromMap(doc.id, doc.data()!));
  }

  Stream<List<DeliveryOrder>> watchCustomerOrders(String customerId) {
    return _orders
        .where('customerId', isEqualTo: customerId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => DeliveryOrder.fromMap(doc.id, doc.data()))
            .toList());
  }

  Stream<List<DeliveryOrder>> watchVendorOrders(String vendorId) {
    return _orders
        .where('vendorId', isEqualTo: vendorId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => DeliveryOrder.fromMap(doc.id, doc.data()))
            .toList());
  }

  Stream<List<DeliveryOrder>> watchAvailableOrdersForDrivers() {
    // Both filters are required, not just for correctness: firestore.rules
    // only grants drivers read access to unclaimed readyForPickup orders,
    // and Firestore rejects a list query unless its own filters guarantee
    // that condition for every possible result — the rule can't be proven
    // from a status-only filter.
    return _orders
        .where('status', isEqualTo: OrderStatus.readyForPickup.name)
        .where('driverId', isNull: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => DeliveryOrder.fromMap(doc.id, doc.data()))
            .toList());
  }

  Future<String> createOrder(DeliveryOrder order) async {
    final doc = await _orders.add(order.toMap());
    return doc.id;
  }

  Future<void> updateOrderStatus(String orderId, OrderStatus status) {
    return _orders.doc(orderId).update({'status': status.name});
  }

  Future<void> assignDriver(String orderId, String driverId) {
    return _orders.doc(orderId).update({
      'driverId': driverId,
      'status': OrderStatus.pickedUp.name,
    });
  }
}
