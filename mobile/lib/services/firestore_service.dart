import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/errors/guard.dart';
import '../models/address.dart';
import '../models/app_user.dart';
import '../models/city.dart';
import '../models/driver.dart';
import '../models/order.dart';
import '../models/promotion.dart';
import '../models/review.dart';
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

  CollectionReference<Map<String, dynamic>> get _reviews =>
      _db.collection('reviews');

  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');

  CollectionReference<Map<String, dynamic>> get _promotions =>
      _db.collection('promotions');

  // AdminUsersScreen's list. NOTE: firestore.rules' users/{userId} read rule
  // is currently `isSelf(userId)` only — there is no admin read branch yet
  // (see ADMIN_AUDIT_REPORT.md §2/§15) — so this stream will surface a
  // permission-denied AppException for every caller, admin included, until
  // that rule is updated. Left as a plain, correct query rather than a
  // workaround: the fix belongs in firestore.rules, not here.
  Stream<List<AppUser>> watchAllUsers() {
    return guardStream(_users.snapshots().map(
        (snap) => snap.docs.map((doc) => AppUser.fromMap(doc.id, doc.data())).toList()));
  }

  // A customer's own favorites — firestore.rules' users/{userId} update rule
  // already permits a signed-in user to change any of their own profile
  // fields (only `role` is pinned), so no rules change was needed for this.
  Future<void> toggleFavoriteVendor(String customerId, String vendorId, bool isFavorite) {
    return guardFuture(() => _users.doc(customerId).update({
          'favoriteVendorIds':
              isFavorite ? FieldValue.arrayUnion([vendorId]) : FieldValue.arrayRemove([vendorId]),
        }));
  }

  // Same rule as toggleFavoriteVendor above — role is pinned, every other
  // profile field is a plain client write. Used by EditProfileScreen.
  Future<void> updateUserProfile(
    String userId, {
    required String displayName,
    String? phoneNumber,
  }) {
    return guardFuture(() => _users.doc(userId).update({
          'displayName': displayName,
          'phoneNumber': phoneNumber,
        }));
  }

  CollectionReference<Map<String, dynamic>> _addresses(String userId) =>
      _users.doc(userId).collection('addresses');

  Stream<List<DeliveryAddress>> watchAddresses(String userId) {
    return guardStream(_addresses(userId).snapshots().map((snap) => snap.docs
        .map((doc) => DeliveryAddress.fromMap(doc.id, doc.data()))
        .toList()));
  }

  // Powers CartScreen's automatic prefill — a single default address (or
  // none) rather than the full list, so the cart doesn't need to watch and
  // filter every saved address itself.
  Stream<DeliveryAddress?> watchDefaultAddress(String userId) {
    return guardStream(_addresses(userId)
        .where('isDefault', isEqualTo: true)
        .limit(1)
        .snapshots()
        .map((snap) => snap.docs.isEmpty
            ? null
            : DeliveryAddress.fromMap(snap.docs.first.id, snap.docs.first.data())));
  }

  Future<String> addAddress(String userId, DeliveryAddress address) {
    return guardFuture(() async {
      final doc = await _addresses(userId).add(address.toMap());
      if (address.isDefault) await setDefaultAddress(userId, doc.id);
      return doc.id;
    });
  }

  Future<void> updateAddress(String userId, DeliveryAddress address) {
    return guardFuture(() => _addresses(userId).doc(address.id).update(address.toMap()));
  }

  Future<void> deleteAddress(String userId, String addressId) {
    return guardFuture(() => _addresses(userId).doc(addressId).delete());
  }

  // Only one address may be default at a time — a batch clears the flag on
  // every other saved address while setting it on [addressId], so the
  // "exactly one default" invariant holds without a transaction (a batch is
  // enough here since nothing else concurrently writes isDefault).
  Future<void> setDefaultAddress(String userId, String addressId) {
    return guardFuture(() async {
      final snap = await _addresses(userId).get();
      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.update(doc.reference, {'isDefault': doc.id == addressId});
      }
      await batch.commit();
    });
  }

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

  Stream<Vendor> watchVendor(String vendorId) {
    return guardStream(_vendors
        .doc(vendorId)
        .snapshots()
        .map((doc) => Vendor.fromMap(doc.id, doc.data()!)));
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

  // AdminVendorsScreen's full restaurant directory — every vendor
  // regardless of approvalStatus/isOpen, unlike watchOpenVendors (customer
  // Home, approved+open only) and watchPendingVendors (approval queue
  // only). No new rule needed: vendors/{vendorId}.read is already `if true`.
  Stream<List<Vendor>> watchAllVendors() {
    return guardStream(_vendors.snapshots().map(
        (snap) => snap.docs.map((doc) => Vendor.fromMap(doc.id, doc.data())).toList()));
  }

  Future<void> updateVendorImage(String vendorId, String imageUrl) {
    return guardFuture(() => _vendors.doc(vendorId).update({'imageUrl': imageUrl}));
  }

  Future<void> setVendorOpen(String vendorId, bool isOpen) {
    return guardFuture(() => _vendors.doc(vendorId).update({'isOpen': isOpen}));
  }

  Future<void> updateVendorDetails(
    String vendorId, {
    required VendorCategory category,
    required City city,
    double? deliveryFee,
    int? etaMinMinutes,
    int? etaMaxMinutes,
    double? minimumOrderAmount,
    String? openTime,
    String? closeTime,
  }) {
    return guardFuture(() => _vendors.doc(vendorId).update({
          'category': category.name,
          'city': city.name,
          'deliveryFee': deliveryFee,
          'etaMinMinutes': etaMinMinutes,
          'etaMaxMinutes': etaMaxMinutes,
          'minimumOrderAmount': minimumOrderAmount,
          'openTime': openTime,
          'closeTime': closeTime,
        }));
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

  // Powers CustomerHomeScreen's product feed — a collection-group query
  // across every vendor's menuItems subcollection (firestore.rules'
  // menuItems read rule is unconditionally `true`, so this is allowed).
  // Deliberately no server-side `.where()`: a filtered collection-group
  // query needs a deployed composite index, and at this app's scale
  // (dozens of vendors, not thousands) fetching everything and filtering
  // client-side — by availability, and by the same open/category/city
  // vendor set CustomerHomeScreen already computes — is simpler and avoids
  // an index-deployment step for no real benefit.
  Stream<List<MenuItem>> watchAllMenuItems() {
    return guardStream(_db
        .collectionGroup('menuItems')
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

  Future<void> setDriverAvailability(String driverId, bool isAvailable) {
    return guardFuture(() => _drivers.doc(driverId).update({'isAvailable': isAvailable}));
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

  // Doc id is the order id (see Review's doc comment), so this both creates
  // the review and enforces "one review per order" — firestore.rules' create
  // rule fires only when no doc exists yet at that id.
  Future<void> submitReview(Review review) {
    return guardFuture(() => _reviews.doc(review.id).set(review.toMap()));
  }

  Stream<Review?> watchReviewForOrder(String orderId) {
    return guardStream(_reviews.doc(orderId).snapshots().map(
        (doc) => doc.exists ? Review.fromMap(doc.id, doc.data()!) : null));
  }

  Stream<List<Review>> watchVendorReviews(String vendorId) {
    return guardStream(_reviews
        .where('vendorId', isEqualTo: vendorId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((doc) => Review.fromMap(doc.id, doc.data())).toList()));
  }

  // PromoBannerCarousel's read query — equality filter (enabled) plus
  // orderBy on a different field (order) needs a composite index, same as
  // watchCustomerOrders/watchVendorOrders above (see firestore.indexes.json).
  Stream<List<Promotion>> watchActivePromotions() {
    return guardStream(_promotions
        .where('enabled', isEqualTo: true)
        .orderBy('order')
        .snapshots()
        .map((snap) =>
            snap.docs.map((doc) => Promotion.fromMap(doc.id, doc.data())).toList()));
  }

  // AdminPromotionsScreen's list — unfiltered, so unlike
  // watchActivePromotions() a single-field index (automatic) is enough.
  Stream<List<Promotion>> watchAllPromotions() {
    return guardStream(_promotions
        .orderBy('order')
        .snapshots()
        .map((snap) =>
            snap.docs.map((doc) => Promotion.fromMap(doc.id, doc.data())).toList()));
  }

  Future<String> addPromotion(Promotion promotion) {
    return guardFuture(() async {
      final doc = await _promotions.add(promotion.toMap());
      return doc.id;
    });
  }

  Future<void> updatePromotion(Promotion promotion) {
    return guardFuture(() => _promotions.doc(promotion.id).set(promotion.toMap()));
  }

  Future<void> deletePromotion(String promotionId) {
    return guardFuture(() => _promotions.doc(promotionId).delete());
  }

  // Single-field partial write for the admin list's enable/disable Switch —
  // same reasoning as setVendorOpen/setDriverAvailability above, avoids
  // overwriting the rest of the doc from possibly-stale list-item state.
  Future<void> setPromotionEnabled(String promotionId, bool enabled) {
    return guardFuture(() => _promotions.doc(promotionId).update({'enabled': enabled}));
  }
}
