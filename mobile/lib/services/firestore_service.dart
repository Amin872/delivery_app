import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/errors/app_exception.dart';
import '../core/errors/guard.dart';
import '../models/address.dart';
import '../models/app_user.dart';
import '../models/approval_status.dart';
import '../models/city.dart';
import '../models/district.dart';
import '../models/driver.dart';
import '../models/governorate.dart';
import '../models/neighborhood.dart';
import '../models/order.dart';
import '../models/promotion.dart';
import '../models/review.dart';
import '../models/service_area.dart';
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

  CollectionReference<Map<String, dynamic>> get _cities =>
      _db.collection('cities');

  CollectionReference<Map<String, dynamic>> get _governorates =>
      _db.collection('governorates');

  CollectionReference<Map<String, dynamic>> get _districts =>
      _db.collection('districts');

  CollectionReference<Map<String, dynamic>> get _neighborhoods =>
      _db.collection('neighborhoods');

  CollectionReference<Map<String, dynamic>> get _serviceAreas =>
      _db.collection('serviceAreas');

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

  // Single-user lookup, e.g. resolving a DeliveryOrder.customerId to a name
  // for AdminOrderDetailScreen — same isSelf(userId) || hasRole('admin')
  // read rule as watchAllUsers above, just scoped to one doc instead of
  // streaming the whole collection for a one-name lookup.
  Stream<AppUser> watchUser(String userId) {
    return guardStream(
        _users.doc(userId).snapshots().map((doc) => AppUser.fromMap(doc.id, doc.data()!)));
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

  Stream<List<SavedAddress>> watchAddresses(String userId) {
    return guardStream(_addresses(userId).snapshots().map((snap) => snap.docs
        .map((doc) => SavedAddress.fromMap(doc.id, doc.data()))
        .toList()));
  }

  // Powers CartScreen's automatic prefill — a single default address (or
  // none) rather than the full list, so the cart doesn't need to watch and
  // filter every saved address itself.
  Stream<SavedAddress?> watchDefaultAddress(String userId) {
    return guardStream(_addresses(userId)
        .where('isDefault', isEqualTo: true)
        .limit(1)
        .snapshots()
        .map((snap) => snap.docs.isEmpty
            ? null
            : SavedAddress.fromMap(snap.docs.first.id, snap.docs.first.data())));
  }

  // Stamps createdAt/updatedAt server-side (this service's own clock, not
  // the caller's) so every newly-created address gets a real timestamp
  // regardless of what (if anything) the caller passed in — see
  // SavedAddress's own doc comment on why these fields are nullable at the
  // model layer despite always being set from this path onward.
  Future<String> addAddress(String userId, SavedAddress address) {
    return guardFuture(() async {
      final now = DateTime.now();
      final doc = await _addresses(userId).add(address.toMap()
        ..['userId'] = userId
        ..['createdAt'] = now.millisecondsSinceEpoch
        ..['updatedAt'] = now.millisecondsSinceEpoch);
      if (address.isDefault) await setDefaultAddress(userId, doc.id);
      return doc.id;
    });
  }

  Future<void> updateAddress(String userId, SavedAddress address) {
    return guardFuture(() => _addresses(userId).doc(address.id).update(address.toMap()
      ..['userId'] = userId
      ..['updatedAt'] = DateTime.now().millisecondsSinceEpoch));
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

  Future<void> updateVendorLogo(String vendorId, String logoUrl) {
    return guardFuture(() => _vendors.doc(vendorId).update({'logoUrl': logoUrl}));
  }

  /// Field-level update of a vendor's editable store details. Never touches
  /// ownerId, approvalStatus, ratingSum or ratingCount (firestore.rules
  /// rejects those from the owner anyway).
  ///
  /// [name] and [description] are written only when non-null, and the
  /// pickup fields only when [updatePickupLocation] is true — so a caller
  /// that doesn't manage them (the admin edit form, whose rule branch
  /// doesn't allow those fields) leaves them untouched. Throws an
  /// [ArgumentError] without writing anything if [name] is blank or the
  /// pickup location fails [validatePickupLocation].
  Future<void> updateVendorDetails(
    String vendorId, {
    required VendorCategory category,
    required String city,
    double? deliveryFee,
    int? etaMinMinutes,
    int? etaMaxMinutes,
    double? minimumOrderAmount,
    String? openTime,
    String? closeTime,
    String? name,
    String? description,
    bool updatePickupLocation = false,
    String? pickupAddress,
    double? pickupLatitude,
    double? pickupLongitude,
  }) {
    final trimmedName = name?.trim();
    if (trimmedName != null && trimmedName.isEmpty) {
      return Future.error(ArgumentError.value(name, 'name', 'must not be empty'));
    }
    final trimmedPickupAddress = pickupAddress?.trim();
    final normalizedPickupAddress =
        (trimmedPickupAddress == null || trimmedPickupAddress.isEmpty) ? null : trimmedPickupAddress;
    if (updatePickupLocation) {
      final pickupError = validatePickupLocation(
        address: normalizedPickupAddress,
        latitude: pickupLatitude,
        longitude: pickupLongitude,
      );
      if (pickupError != null) {
        return Future.error(ArgumentError('Invalid pickup location: ${pickupError.name}'));
      }
    }

    return guardFuture(() => _vendors.doc(vendorId).update({
          'category': category.name,
          'city': city,
          'deliveryFee': deliveryFee,
          'etaMinMinutes': etaMinMinutes,
          'etaMaxMinutes': etaMaxMinutes,
          'minimumOrderAmount': minimumOrderAmount,
          'openTime': openTime,
          'closeTime': closeTime,
          if (trimmedName != null) 'name': trimmedName,
          if (description != null) 'description': description.trim(),
          if (updatePickupLocation) ...{
            'pickupAddress': normalizedPickupAddress,
            'pickupLatitude': pickupLatitude,
            'pickupLongitude': pickupLongitude,
          },
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

  // Orders are created only by the `createOrder` callable — see
  // FunctionsService.createOrder. firestore.rules denies client-side creates.

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

  // Marketplace-wide counterparts of the vendor/driver-scoped aggregations
  // above, for AdminAnalyticsScreen — same `.count()`/`.aggregate(sum(...))`
  // server-side aggregation, just without a `vendorId`/`driverId` filter, so
  // these never download a full collection just to size it.
  Future<int> countAllUsers() {
    return guardFuture(() async {
      final snapshot = await _users.count().get();
      return snapshot.count ?? 0;
    });
  }

  Future<int> countAllVendors() {
    return guardFuture(() async {
      final snapshot = await _vendors.count().get();
      return snapshot.count ?? 0;
    });
  }

  Future<int> countAllDrivers() {
    return guardFuture(() async {
      final snapshot = await _drivers.count().get();
      return snapshot.count ?? 0;
    });
  }

  Future<int> countAllOrders() {
    return guardFuture(() async {
      final snapshot = await _orders.count().get();
      return snapshot.count ?? 0;
    });
  }

  Future<double> sumAllDeliveredSales() {
    return guardFuture(() async {
      final snapshot = await _orders
          .where('status', isEqualTo: OrderStatus.delivered.name)
          .aggregate(sum('total'))
          .get();
      return snapshot.getSum('total') ?? 0;
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

  // The customer-facing live-tracking feed for one specific order — see the
  // Driver Live Location redesign and firestore.rules'
  // orders/{orderId}/driverLocation/{locationId} block. Null before the
  // assigned driver's first publish (or once tracking is no longer active).
  Stream<DriverLocation?> watchOrderDriverLocation(String orderId) {
    return guardStream(_orders
        .doc(orderId)
        .collection('driverLocation')
        .doc('current')
        .snapshots()
        .map((doc) => doc.exists ? DriverLocation.fromMap(doc.data()!) : null));
  }

  // Every driver's availability, for AdminOrderDetailScreen's reassignment
  // picker. `drivers/{driverId}` read is `isSelf(driverId) || hasRole('admin')`
  // in firestore.rules (see the Driver Live Location redesign) — already
  // covers any signed-in admin — so no rules change was needed. Driver
  // identity (name/email) isn't on this doc; the picker joins this against
  // watchAllUsers() by id, same as AdminUsersScreen already does for the
  // user directory.
  Stream<List<Driver>> watchAllDrivers() {
    return guardStream(_drivers.snapshots().map(
        (snap) => snap.docs.map((doc) => Driver.fromMap(doc.id, doc.data())).toList()));
  }

  Future<void> setDriverAvailability(String driverId, bool isAvailable) {
    return guardFuture(() => _drivers.doc(driverId).update({'isAvailable': isAvailable}));
  }

  /// Admin-only (firestore.rules' drivers admin branch permits exactly this
  /// one field) — the driver counterpart of [setVendorApprovalStatus].
  Future<void> setDriverApprovalStatus(String driverId, ApprovalStatus status) {
    return guardFuture(
      () => _drivers.doc(driverId).update({'approvalStatus': status.name}),
    );
  }

  // Null when the driver has no delivery currently in flight —
  // `driverAssigned`, `pickedUp`, and `delivering` are the only statuses
  // between accepting an order (acceptDelivery) and it being marked
  // delivered. `driverAssigned` was added in Phase 4 (see models/order.dart)
  // for the "assigned but not yet physically picked up" stage.
  Stream<DeliveryOrder?> watchActiveDriverOrder(String driverId) {
    return guardStream(_orders
        .where('driverId', isEqualTo: driverId)
        .where('status', whereIn: [
          OrderStatus.driverAssigned.name,
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

  // Canonical city list for the Locations migration (see the migration
  // plan) — unfiltered, ordered by `order` only, so — same reasoning as
  // watchAllPromotions() above — a single-field automatic index is enough;
  // no composite index needed. Consumed across the app (customer city
  // picker, vendor dashboard, Admin Locations, ...) via allCitiesProvider —
  // the retired `City` enum is gone; every city picker is Firestore-backed.
  Stream<List<CityOption>> watchCities() {
    return guardStream(_cities
        .orderBy('order')
        .snapshots()
        .map((snap) =>
            snap.docs.map((doc) => CityOption.fromMap(doc.id, doc.data())).toList()));
  }

  // Canonical governorate list (Locations Phase 3 — see models/governorate.dart)
  // — unfiltered, ordered by `order` only, same reasoning as watchCities()
  // above: a single-field automatic index is enough, no composite index
  // needed. Grouping cities under a governorate (via CityOption.governorateId)
  // is done client-side, same "fetch everything small, group in Dart"
  // pattern as visibleCities().
  Stream<List<GovernorateOption>> watchGovernorates() {
    return guardStream(_governorates
        .orderBy('order')
        .snapshots()
        .map((snap) =>
            snap.docs.map((doc) => GovernorateOption.fromMap(doc.id, doc.data())).toList()));
  }

  // Canonical district list (Locations Phase 1 — District data foundation,
  // see models/district.dart) — unfiltered, ordered by `order` only, same
  // reasoning as watchCities()/watchGovernorates() above: a single-field
  // automatic index is enough, no composite index needed. No UI consumes
  // this yet in this phase (data foundation only).
  Stream<List<DistrictOption>> watchDistricts() {
    return guardStream(_districts
        .orderBy('order')
        .snapshots()
        .map((snap) =>
            snap.docs.map((doc) => DistrictOption.fromMap(doc.id, doc.data())).toList()));
  }

  // Admin Locations — governorates. addGovernorate runs in a transaction so
  // a duplicate id is rejected atomically even under a race (two admins
  // submitting the same hand-typed id concurrently): whichever transaction
  // commits second sees the doc the first one just created and throws,
  // rather than silently overwriting it. This is genuine protection, unlike
  // firestore.rules' create/update split (see the rules' own comment) —
  // Firestore classifies a .set() purely by document existence at commit
  // time, so rules alone can't distinguish "this was meant as a fresh add"
  // from "this is a legitimate edit" once a doc exists.
  Future<void> addGovernorate(GovernorateOption governorate) {
    return guardFuture(() => _db.runTransaction((tx) async {
          final ref = _governorates.doc(governorate.id);
          final snapshot = await tx.get(ref);
          if (snapshot.exists) {
            throw const AppException('already-exists');
          }
          tx.set(ref, governorate.toMap());
        }));
  }

  Future<void> updateGovernorate(GovernorateOption governorate) {
    return guardFuture(
        () => _governorates.doc(governorate.id).update(governorate.toMap()));
  }

  // Single-field partial write for the list's enable/disable Switch — same
  // reasoning as setPromotionEnabled above, avoids overwriting the rest of
  // the doc from possibly-stale list-item state.
  Future<void> setGovernorateEnabled(String governorateId, bool enabled) {
    return guardFuture(() => _governorates.doc(governorateId).update({'enabled': enabled}));
  }

  // Admin Locations — cities. Same transactional duplicate-id protection as
  // addGovernorate above.
  Future<void> addCity(CityOption city) {
    return guardFuture(() => _db.runTransaction((tx) async {
          final ref = _cities.doc(city.id);
          final snapshot = await tx.get(ref);
          if (snapshot.exists) {
            throw const AppException('already-exists');
          }
          tx.set(ref, city.toMap());
        }));
  }

  Future<void> updateCity(CityOption city) {
    return guardFuture(() => _cities.doc(city.id).update(city.toMap()));
  }

  Future<void> setCityEnabled(String cityId, bool enabled) {
    return guardFuture(() => _cities.doc(cityId).update({'enabled': enabled}));
  }

  // Districts (Locations Phase 1 — data foundation only, no UI consumes
  // this yet). Same transactional duplicate-id protection as
  // addCity/addGovernorate above — district.cityId's existence is enforced
  // server-side by firestore.rules' districts/{districtId} block (both
  // create and update), not re-checked here client-side.
  Future<void> addDistrict(DistrictOption district) {
    return guardFuture(() => _db.runTransaction((tx) async {
          final ref = _districts.doc(district.id);
          final snapshot = await tx.get(ref);
          if (snapshot.exists) {
            throw const AppException('already-exists');
          }
          tx.set(ref, district.toMap());
        }));
  }

  Future<void> updateDistrict(DistrictOption district) {
    return guardFuture(() => _districts.doc(district.id).update(district.toMap()));
  }

  Future<void> setDistrictEnabled(String districtId, bool enabled) {
    return guardFuture(() => _districts.doc(districtId).update({'enabled': enabled}));
  }

  // Neighbourhoods (Phase 4 — see models/neighborhood.dart's own doc comment
  // for why this is a standalone collection rather than reusing districts/).
  // Same unfiltered/order-only query, same transactional duplicate-id
  // protection on add, and same referential integrity on the cityId
  // foreign key (enforced server-side by firestore.rules) as
  // watchDistricts/addDistrict above.
  Stream<List<NeighborhoodOption>> watchNeighborhoods() {
    return guardStream(_neighborhoods
        .orderBy('order')
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => NeighborhoodOption.fromMap(doc.id, doc.data()))
            .toList()));
  }

  Future<void> addNeighborhood(NeighborhoodOption neighborhood) {
    return guardFuture(() => _db.runTransaction((tx) async {
          final ref = _neighborhoods.doc(neighborhood.id);
          final snapshot = await tx.get(ref);
          if (snapshot.exists) {
            throw const AppException('already-exists');
          }
          tx.set(ref, neighborhood.toMap());
        }));
  }

  Future<void> updateNeighborhood(NeighborhoodOption neighborhood) {
    return guardFuture(
        () => _neighborhoods.doc(neighborhood.id).update(neighborhood.toMap()));
  }

  Future<void> setNeighborhoodEnabled(String neighborhoodId, bool enabled) {
    return guardFuture(() => _neighborhoods.doc(neighborhoodId).update({'enabled': enabled}));
  }

  // Service areas (Phase 4 — see models/service_area.dart's own doc comment:
  // a standalone future layer, no consumer reads this for delivery
  // eligibility yet). Same shape/reasoning as watchCities/addCity above.
  Stream<List<ServiceArea>> watchServiceAreas() {
    return guardStream(_serviceAreas
        .orderBy('order')
        .snapshots()
        .map((snap) =>
            snap.docs.map((doc) => ServiceArea.fromMap(doc.id, doc.data())).toList()));
  }

  Future<void> addServiceArea(ServiceArea area) {
    return guardFuture(() => _db.runTransaction((tx) async {
          final ref = _serviceAreas.doc(area.id);
          final snapshot = await tx.get(ref);
          if (snapshot.exists) {
            throw const AppException('already-exists');
          }
          tx.set(ref, area.toMap());
        }));
  }

  Future<void> updateServiceArea(ServiceArea area) {
    return guardFuture(() => _serviceAreas.doc(area.id).update(area.toMap()));
  }

  Future<void> setServiceAreaEnabled(String serviceAreaId, bool enabled) {
    return guardFuture(() => _serviceAreas.doc(serviceAreaId).update({'enabled': enabled}));
  }
}
