import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/errors/guard.dart';
import '../models/driver.dart';
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

  CollectionReference<Map<String, dynamic>> get _drivers =>
      _db.collection('drivers');

  Stream<List<Vendor>> watchOpenVendors() {
    return guardStream(_vendors
        .where('isOpen', isEqualTo: true)
        .where('approvalStatus', isEqualTo: VendorApprovalStatus.approved.name)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => Vendor.fromMap(doc.id, doc.data()))
              .toList(),
        ));
  }

  Stream<List<Vendor>> watchPendingVendors() {
    return guardStream(_vendors
        .where('approvalStatus', isEqualTo: VendorApprovalStatus.pending.name)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => Vendor.fromMap(doc.id, doc.data()))
              .toList(),
        ));
  }

  Future<void> setVendorApprovalStatus(
    String vendorId,
    VendorApprovalStatus status,
  ) {
    return guardFuture(
      () => _vendors.doc(vendorId).update({'approvalStatus': status.name}),
    );
  }

  Stream<List<MenuItem>> watchMenu(String vendorId) {
    return guardStream(_vendors
        .doc(vendorId)
        .collection('menuItems')
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => MenuItem.fromMap(doc.id, doc.data()))
            .toList()));
  }

  Future<String> addMenuItem(String vendorId, MenuItem item) {
    return guardFuture(() async {
      final doc = await _vendors.doc(vendorId).collection('menuItems').add(item.toMap());
      return doc.id;
    });
  }

  Future<void> updateMenuItem(String vendorId, MenuItem item) {
    return guardFuture(() => _vendors
        .doc(vendorId)
        .collection('menuItems')
        .doc(item.id)
        .set(item.toMap()));
  }

  Future<void> deleteMenuItem(String vendorId, String itemId) {
    return guardFuture(
      () => _vendors.doc(vendorId).collection('menuItems').doc(itemId).delete(),
    );
  }

  Stream<DeliveryOrder> watchOrder(String orderId) {
    return guardStream(_orders
        .doc(orderId)
        .snapshots()
        .map((doc) => DeliveryOrder.fromMap(doc.id, doc.data()!)));
  }

  Stream<List<DeliveryOrder>> watchCustomerOrders(String customerId) {
    return guardStream(_orders
        .where('customerId', isEqualTo: customerId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => DeliveryOrder.fromMap(doc.id, doc.data()))
            .toList()));
  }

  Stream<List<DeliveryOrder>> watchVendorOrders(String vendorId) {
    return guardStream(_orders
        .where('vendorId', isEqualTo: vendorId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => DeliveryOrder.fromMap(doc.id, doc.data()))
            .toList()));
  }

  Stream<List<DeliveryOrder>> watchAvailableOrdersForDrivers() {
    // Both filters are required, not just for correctness: firestore.rules
    // only grants drivers read access to unclaimed readyForPickup orders,
    // and Firestore rejects a list query unless its own filters guarantee
    // that condition for every possible result — the rule can't be proven
    // from a status-only filter.
    return guardStream(_orders
        .where('status', isEqualTo: OrderStatus.readyForPickup.name)
        .where('driverId', isNull: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => DeliveryOrder.fromMap(doc.id, doc.data()))
            .toList()));
  }

  Future<String> createOrder(DeliveryOrder order) {
    return guardFuture(() async {
      final doc = await _orders.add(order.toMap());
      return doc.id;
    });
  }

  Future<void> updateOrderStatus(String orderId, OrderStatus status) {
    return guardFuture(
      () => _orders.doc(orderId).update({'status': status.name}),
    );
  }

  // Same underlying write as updateOrderStatus — kept as its own method
  // because who's allowed to call it is narrower: firestore.rules only lets
  // the owning vendor set an arbitrary status, or the order's own customer
  // move it from 'pending' to 'cancelled' specifically.
  Future<void> cancelOrder(String orderId) {
    return guardFuture(
      () => _orders.doc(orderId).update({'status': OrderStatus.cancelled.name}),
    );
  }

  Future<void> assignDriver(String orderId, String driverId) {
    return guardFuture(() => _orders.doc(orderId).update({
          'driverId': driverId,
          'status': OrderStatus.pickedUp.name,
        }));
  }

  Future<int> countVendorOrders(String vendorId) {
    return guardFuture(() async {
      final snapshot = await _orders.where('vendorId', isEqualTo: vendorId).count().get();
      return snapshot.count ?? 0;
    });
  }

  Future<double> sumVendorDeliveredSales(String vendorId) {
    return guardFuture(() async {
      final snapshot = await _orders
          .where('vendorId', isEqualTo: vendorId)
          .where('status', isEqualTo: OrderStatus.delivered.name)
          .aggregate(sum('total'))
          .get();
      return snapshot.getSum('total') ?? 0;
    });
  }

  Future<int> countVendorDeliveredOrders(String vendorId) {
    return guardFuture(() async {
      final snapshot = await _orders
          .where('vendorId', isEqualTo: vendorId)
          .where('status', isEqualTo: OrderStatus.delivered.name)
          .count()
          .get();
      return snapshot.count ?? 0;
    });
  }

  // Bounded sample used for the vendor's "most ordered items" tally —
  // Firestore aggregation can't group by values inside an `items[]` array,
  // so this is a deliberate approximation over recent history rather than a
  // full scan, which is fine at this app's current scale.
  Future<List<DeliveryOrder>> fetchRecentDeliveredOrders(
    String vendorId, {
    int limit = 200,
  }) {
    return guardFuture(() async {
      final snapshot = await _orders
          .where('vendorId', isEqualTo: vendorId)
          .where('status', isEqualTo: OrderStatus.delivered.name)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();
      return snapshot.docs.map((doc) => DeliveryOrder.fromMap(doc.id, doc.data())).toList();
    });
  }

  Stream<List<DeliveryOrder>> watchAllOrders({OrderStatus? status}) {
    Query<Map<String, dynamic>> query = _orders.orderBy('createdAt', descending: true);
    if (status != null) {
      query = _orders
          .where('status', isEqualTo: status.name)
          .orderBy('createdAt', descending: true);
    }
    return guardStream(query.snapshots().map((snap) =>
        snap.docs.map((doc) => DeliveryOrder.fromMap(doc.id, doc.data())).toList()));
  }

  Stream<Driver> watchDriver(String driverId) {
    return guardStream(_drivers
        .doc(driverId)
        .snapshots()
        .map((doc) => Driver.fromMap(doc.id, doc.data()!)));
  }

  // Null when the driver has no delivery currently in flight — `pickedUp`
  // and `delivering` are the only statuses between accepting an order
  // (acceptDelivery) and it being marked delivered.
  Stream<DeliveryOrder?> watchActiveDriverOrder(String driverId) {
    return guardStream(_orders
        .where('driverId', isEqualTo: driverId)
        .where('status', whereIn: [
          OrderStatus.pickedUp.name,
          OrderStatus.delivering.name,
        ])
        .snapshots()
        .map((snap) => snap.docs.isEmpty
            ? null
            : DeliveryOrder.fromMap(snap.docs.first.id, snap.docs.first.data())));
  }

  Future<int> countDriverDeliveries(String driverId) {
    return guardFuture(() async {
      final snapshot = await _orders
          .where('driverId', isEqualTo: driverId)
          .where('status', isEqualTo: OrderStatus.delivered.name)
          .count()
          .get();
      return snapshot.count ?? 0;
    });
  }
}
