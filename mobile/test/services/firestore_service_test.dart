import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:delivery_app/core/errors/app_exception.dart';
import 'package:delivery_app/models/approval_status.dart';
import 'package:delivery_app/models/city.dart';
import 'package:delivery_app/models/district.dart';
import 'package:delivery_app/models/governorate.dart';
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

  test('watchAllMenuItems returns items across every vendor via a collection-group query',
      () async {
    final firestore = FakeFirebaseFirestore();
    final service = FirestoreService(firestore: firestore);

    await service.addMenuItem(
      'vendor-1',
      const MenuItem(id: '', vendorId: 'vendor-1', name: 'Falafel', price: 5000, available: true),
    );
    await service.addMenuItem(
      'vendor-2',
      const MenuItem(id: '', vendorId: 'vendor-2', name: 'Shawarma', price: 6000, available: true),
    );

    final items = await service.watchAllMenuItems().first;

    expect(items.length, 2);
    expect(items.map((item) => item.name), containsAll(['Falafel', 'Shawarma']));
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

  test('marketplace-wide aggregation methods count/sum across every vendor and driver',
      () async {
    final firestore = FakeFirebaseFirestore();
    final service = FirestoreService(firestore: firestore);

    await firestore.collection('users').doc('u1').set({'email': 'a@b.com', 'displayName': 'A', 'role': 'customer'});
    await firestore.collection('users').doc('u2').set({'email': 'b@b.com', 'displayName': 'B', 'role': 'driver'});
    await firestore.collection('vendors').add({'ownerId': 'o1', 'name': 'V1', 'description': '', 'isOpen': true, 'approvalStatus': 'approved'});
    await firestore.collection('vendors').add({'ownerId': 'o2', 'name': 'V2', 'description': '', 'isOpen': true, 'approvalStatus': 'pending'});
    await firestore.collection('drivers').doc('d1').set({'userId': 'd1', 'isAvailable': true});

    await firestore
        .collection('orders')
        .add(_orderMap(vendorId: 'vendor-1', status: 'delivered', total: 100));
    await firestore
        .collection('orders')
        .add(_orderMap(vendorId: 'vendor-2', status: 'delivered', total: 999));
    await firestore
        .collection('orders')
        .add(_orderMap(vendorId: 'vendor-1', status: 'pending', total: 30));

    expect(await service.countAllUsers(), 2);
    expect(await service.countAllVendors(), 2);
    expect(await service.countAllDrivers(), 1);
    expect(await service.countAllOrders(), 3);
    expect(await service.sumAllDeliveredSales(), 1099);
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

  test('watchOrderDriverLocation resolves null before any publish, then the published position',
      () async {
    final firestore = FakeFirebaseFirestore();
    final service = FirestoreService(firestore: firestore);

    expect(await service.watchOrderDriverLocation('order-1').first, isNull);

    await firestore
        .collection('orders')
        .doc('order-1')
        .collection('driverLocation')
        .doc('current')
        .set({
      'latitude': 33.5,
      'longitude': 36.3,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });

    final location = await service.watchOrderDriverLocation('order-1').first;
    expect(location?.latitude, 33.5);
    expect(location?.longitude, 36.3);
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

  test('toggleFavoriteVendor adds and removes a vendor id from favoriteVendorIds', () async {
    final firestore = FakeFirebaseFirestore();
    final service = FirestoreService(firestore: firestore);

    await firestore.collection('users').doc('customer-1').set({
      'email': 'a@b.com',
      'displayName': 'A',
      'role': 'customer',
      'favoriteVendorIds': <String>[],
    });

    await service.toggleFavoriteVendor('customer-1', 'vendor-1', true);
    final afterAdd = await firestore.collection('users').doc('customer-1').get();
    expect(afterAdd.data()!['favoriteVendorIds'], ['vendor-1']);

    await service.toggleFavoriteVendor('customer-1', 'vendor-1', false);
    final afterRemove = await firestore.collection('users').doc('customer-1').get();
    expect(afterRemove.data()!['favoriteVendorIds'], isEmpty);
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

  test('setVendorOpen sets the vendor doc isOpen, and watchVendor reflects it', () async {
    final firestore = FakeFirebaseFirestore();
    final service = FirestoreService(firestore: firestore);

    final vendorRef = await firestore.collection('vendors').add({
      'ownerId': 'owner-1',
      'name': 'Falafel House',
      'description': '',
      'imageUrl': null,
      'isOpen': false,
      'approvalStatus': 'approved',
    });

    await service.setVendorOpen(vendorRef.id, true);

    final updated = await service.watchVendor(vendorRef.id).first;
    expect(updated.isOpen, isTrue);
  });

  test('setDriverAvailability sets the driver doc isAvailable, and watchDriver reflects it',
      () async {
    final firestore = FakeFirebaseFirestore();
    final service = FirestoreService(firestore: firestore);

    await firestore.collection('drivers').doc('driver-1').set({
      'userId': 'driver-1',
      'isAvailable': true,
    });

    await service.setDriverAvailability('driver-1', false);

    final updated = await service.watchDriver('driver-1').first;
    expect(updated.isAvailable, isFalse);
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

  test('watchAllDrivers returns every driver doc across the collection', () async {
    final firestore = FakeFirebaseFirestore();
    final service = FirestoreService(firestore: firestore);

    await firestore.collection('drivers').doc('driver-1').set({
      'userId': 'driver-1',
      'isAvailable': true,
    });
    await firestore.collection('drivers').doc('driver-2').set({
      'userId': 'driver-2',
      'isAvailable': false,
    });

    final drivers = await service.watchAllDrivers().first;

    expect(drivers.length, 2);
    expect(drivers.map((d) => d.id), containsAll(['driver-1', 'driver-2']));
    expect(drivers.firstWhere((d) => d.id == 'driver-1').isAvailable, isTrue);
    expect(drivers.firstWhere((d) => d.id == 'driver-2').isAvailable, isFalse);
  });

  test('watchUser resolves a single user doc by id', () async {
    final firestore = FakeFirebaseFirestore();
    final service = FirestoreService(firestore: firestore);

    await firestore.collection('users').doc('driver-1').set({
      'email': 'driver@example.com',
      'displayName': 'Sam Driver',
      'role': 'driver',
    });

    final user = await service.watchUser('driver-1').first;

    expect(user.id, 'driver-1');
    expect(user.displayName, 'Sam Driver');
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

  test('watchCities returns every city ordered by `order`, regardless of insertion order',
      () async {
    final firestore = FakeFirebaseFirestore();
    final service = FirestoreService(firestore: firestore);

    await firestore.collection('cities').doc('aleppo').set({
      'nameEn': 'Aleppo',
      'nameAr': 'حلب',
      'enabled': true,
      'order': 1,
    });
    await firestore.collection('cities').doc('damascus').set({
      'nameEn': 'Damascus',
      'nameAr': 'دمشق',
      'enabled': true,
      'order': 0,
    });
    await firestore.collection('cities').doc('homs').set({
      'nameEn': 'Homs',
      'nameAr': 'حمص',
      'enabled': false,
      'order': 2,
    });

    final cities = await service.watchCities().first;

    expect(cities.map((c) => c.id).toList(), ['damascus', 'aleppo', 'homs']);
    expect(cities.map((c) => c.order).toList(), [0, 1, 2]);
    expect(cities.firstWhere((c) => c.id == 'homs').enabled, isFalse);
  });

  test('watchGovernorates returns every governorate ordered by `order`, regardless of insertion order',
      () async {
    final firestore = FakeFirebaseFirestore();
    final service = FirestoreService(firestore: firestore);

    await firestore.collection('governorates').doc('aleppo').set({
      'nameEn': 'Aleppo',
      'nameAr': 'حلب',
      'enabled': true,
      'order': 2,
    });
    await firestore.collection('governorates').doc('damascus').set({
      'nameEn': 'Damascus',
      'nameAr': 'دمشق',
      'enabled': true,
      'order': 0,
    });
    await firestore.collection('governorates').doc('rif_dimashq').set({
      'nameEn': 'Rif Dimashq',
      'nameAr': 'ريف دمشق',
      'enabled': false,
      'order': 1,
    });

    final governorates = await service.watchGovernorates().first;

    expect(governorates.map((g) => g.id).toList(), ['damascus', 'rif_dimashq', 'aleppo']);
    expect(governorates.map((g) => g.order).toList(), [0, 1, 2]);
    expect(governorates.firstWhere((g) => g.id == 'rif_dimashq').enabled, isFalse);
  });

  test('addGovernorate creates a new governorate doc', () async {
    final firestore = FakeFirebaseFirestore();
    final service = FirestoreService(firestore: firestore);

    await service.addGovernorate(const GovernorateOption(
      id: 'damascus',
      nameEn: 'Damascus',
      nameAr: 'دمشق',
      enabled: true,
      order: 0,
    ));

    final doc = await firestore.collection('governorates').doc('damascus').get();
    expect(doc.exists, isTrue);
    expect(doc.data()!['nameEn'], 'Damascus');
  });

  test('addGovernorate throws already-exists when the id is already taken', () async {
    final firestore = FakeFirebaseFirestore();
    final service = FirestoreService(firestore: firestore);
    await firestore.collection('governorates').doc('damascus').set({
      'nameEn': 'Damascus',
      'nameAr': 'دمشق',
      'enabled': true,
      'order': 0,
    });

    await expectLater(
      service.addGovernorate(const GovernorateOption(
        id: 'damascus',
        nameEn: 'Somewhere else',
        nameAr: 'مكان آخر',
        enabled: true,
        order: 99,
      )),
      throwsA(isA<AppException>().having((e) => e.code, 'code', 'already-exists')),
    );
    // The original doc must be untouched by the rejected attempt.
    final doc = await firestore.collection('governorates').doc('damascus').get();
    expect(doc.data()!['nameEn'], 'Damascus');
  });

  test('updateGovernorate overwrites an existing governorate doc', () async {
    final firestore = FakeFirebaseFirestore();
    final service = FirestoreService(firestore: firestore);
    await firestore.collection('governorates').doc('damascus').set({
      'nameEn': 'Damascus',
      'nameAr': 'دمشق',
      'enabled': true,
      'order': 0,
    });

    await service.updateGovernorate(const GovernorateOption(
      id: 'damascus',
      nameEn: 'Damascus',
      nameAr: 'دمشق',
      enabled: true,
      order: 7,
    ));

    final doc = await firestore.collection('governorates').doc('damascus').get();
    expect(doc.data()!['order'], 7);
  });

  test('setGovernorateEnabled updates only the enabled field', () async {
    final firestore = FakeFirebaseFirestore();
    final service = FirestoreService(firestore: firestore);
    await firestore.collection('governorates').doc('damascus').set({
      'nameEn': 'Damascus',
      'nameAr': 'دمشق',
      'enabled': true,
      'order': 3,
    });

    await service.setGovernorateEnabled('damascus', false);

    final doc = await firestore.collection('governorates').doc('damascus').get();
    expect(doc.data()!['enabled'], isFalse);
    expect(doc.data()!['order'], 3);
  });

  test('addCity creates a new city doc', () async {
    final firestore = FakeFirebaseFirestore();
    final service = FirestoreService(firestore: firestore);

    await service.addCity(const CityOption(
      id: 'douma',
      nameEn: 'Douma',
      nameAr: 'دوما',
      enabled: true,
      order: 0,
      governorateId: 'rif_dimashq',
    ));

    final doc = await firestore.collection('cities').doc('douma').get();
    expect(doc.exists, isTrue);
    expect(doc.data()!['governorateId'], 'rif_dimashq');
  });

  test('addCity throws already-exists when the id is already taken', () async {
    final firestore = FakeFirebaseFirestore();
    final service = FirestoreService(firestore: firestore);
    await firestore.collection('cities').doc('damascus').set({
      'nameEn': 'Damascus',
      'nameAr': 'دمشق',
      'enabled': true,
      'order': 0,
    });

    await expectLater(
      service.addCity(const CityOption(
        id: 'damascus',
        nameEn: 'Somewhere else',
        nameAr: 'مكان آخر',
        enabled: true,
        order: 99,
      )),
      throwsA(isA<AppException>().having((e) => e.code, 'code', 'already-exists')),
    );
  });

  test('updateCity overwrites an existing city doc, including governorateId', () async {
    final firestore = FakeFirebaseFirestore();
    final service = FirestoreService(firestore: firestore);
    await firestore.collection('cities').doc('damascus').set({
      'nameEn': 'Damascus',
      'nameAr': 'دمشق',
      'enabled': true,
      'order': 0,
    });

    await service.updateCity(const CityOption(
      id: 'damascus',
      nameEn: 'Damascus',
      nameAr: 'دمشق',
      enabled: true,
      order: 0,
      governorateId: 'damascus',
    ));

    final doc = await firestore.collection('cities').doc('damascus').get();
    expect(doc.data()!['governorateId'], 'damascus');
  });

  test('setCityEnabled updates only the enabled field', () async {
    final firestore = FakeFirebaseFirestore();
    final service = FirestoreService(firestore: firestore);
    await firestore.collection('cities').doc('damascus').set({
      'nameEn': 'Damascus',
      'nameAr': 'دمشق',
      'enabled': true,
      'order': 0,
    });

    await service.setCityEnabled('damascus', false);

    final doc = await firestore.collection('cities').doc('damascus').get();
    expect(doc.data()!['enabled'], isFalse);
  });

  test('watchDistricts returns every district ordered by `order`, regardless of insertion order',
      () async {
    final firestore = FakeFirebaseFirestore();
    final service = FirestoreService(firestore: firestore);

    await firestore.collection('districts').doc('douma').set({
      'nameEn': 'Douma',
      'nameAr': 'دوما',
      'cityId': 'damascus',
      'enabled': true,
      'order': 1,
    });
    await firestore.collection('districts').doc('al_mazzeh').set({
      'nameEn': 'Al-Mazzeh',
      'nameAr': 'المزة',
      'cityId': 'damascus',
      'enabled': false,
      'order': 0,
    });

    final districts = await service.watchDistricts().first;

    expect(districts.map((d) => d.id).toList(), ['al_mazzeh', 'douma']);
    expect(districts.firstWhere((d) => d.id == 'al_mazzeh').enabled, isFalse);
    expect(districts.firstWhere((d) => d.id == 'douma').cityId, 'damascus');
  });

  test('addDistrict creates a new district doc', () async {
    final firestore = FakeFirebaseFirestore();
    final service = FirestoreService(firestore: firestore);

    await service.addDistrict(const DistrictOption(
      id: 'al_mazzeh',
      nameEn: 'Al-Mazzeh',
      nameAr: 'المزة',
      cityId: 'damascus',
      enabled: true,
      order: 0,
    ));

    final doc = await firestore.collection('districts').doc('al_mazzeh').get();
    expect(doc.exists, isTrue);
    expect(doc.data()!['cityId'], 'damascus');
  });

  test('addDistrict throws already-exists when the id is already taken', () async {
    final firestore = FakeFirebaseFirestore();
    final service = FirestoreService(firestore: firestore);
    await firestore.collection('districts').doc('al_mazzeh').set({
      'nameEn': 'Al-Mazzeh',
      'nameAr': 'المزة',
      'cityId': 'damascus',
      'enabled': true,
      'order': 0,
    });

    await expectLater(
      service.addDistrict(const DistrictOption(
        id: 'al_mazzeh',
        nameEn: 'Somewhere else',
        nameAr: 'مكان آخر',
        cityId: 'aleppo',
        enabled: true,
        order: 99,
      )),
      throwsA(isA<AppException>().having((e) => e.code, 'code', 'already-exists')),
    );
    // The original doc must be untouched by the rejected attempt.
    final doc = await firestore.collection('districts').doc('al_mazzeh').get();
    expect(doc.data()!['cityId'], 'damascus');
  });

  test('updateDistrict overwrites an existing district doc, including cityId', () async {
    final firestore = FakeFirebaseFirestore();
    final service = FirestoreService(firestore: firestore);
    await firestore.collection('districts').doc('al_mazzeh').set({
      'nameEn': 'Al-Mazzeh',
      'nameAr': 'المزة',
      'cityId': 'damascus',
      'enabled': true,
      'order': 0,
    });

    await service.updateDistrict(const DistrictOption(
      id: 'al_mazzeh',
      nameEn: 'Al-Mazzeh',
      nameAr: 'المزة',
      cityId: 'aleppo',
      enabled: true,
      order: 5,
    ));

    final doc = await firestore.collection('districts').doc('al_mazzeh').get();
    expect(doc.data()!['cityId'], 'aleppo');
    expect(doc.data()!['order'], 5);
  });

  test('setDistrictEnabled updates only the enabled field', () async {
    final firestore = FakeFirebaseFirestore();
    final service = FirestoreService(firestore: firestore);
    await firestore.collection('districts').doc('al_mazzeh').set({
      'nameEn': 'Al-Mazzeh',
      'nameAr': 'المزة',
      'cityId': 'damascus',
      'enabled': true,
      'order': 0,
    });

    await service.setDistrictEnabled('al_mazzeh', false);

    final doc = await firestore.collection('districts').doc('al_mazzeh').get();
    expect(doc.data()!['enabled'], isFalse);
    expect(doc.data()!['cityId'], 'damascus');
  });

  group('vendor store details (Phase 23)', () {
    Future<FakeFirebaseFirestore> seededVendor() async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('vendors').doc('vendor-1').set({
        'ownerId': 'owner-1',
        'name': 'Old name',
        'description': 'Old description',
        'isOpen': true,
        'approvalStatus': 'approved',
        'ratingSum': 9,
        'ratingCount': 2,
        'category': 'restaurants',
        'city': 'damascus',
        'pickupAddress': null,
        'pickupLatitude': null,
        'pickupLongitude': null,
      });
      return firestore;
    }

    Future<Map<String, dynamic>> vendorData(FakeFirebaseFirestore firestore) async =>
        (await firestore.collection('vendors').doc('vendor-1').get()).data()!;

    test('updates name, description and pickup location; leaves protected fields alone', () async {
      final firestore = await seededVendor();
      final service = FirestoreService(firestore: firestore);

      await service.updateVendorDetails(
        'vendor-1',
        category: VendorCategory.restaurants,
        city: 'damascus',
        name: '  Abu Kamal Falafel  ',
        description: ' Best falafel in town ',
        updatePickupLocation: true,
        pickupAddress: ' Hamra St, Damascus ',
        pickupLatitude: 33.5138,
        pickupLongitude: 36.2765,
      );

      final data = await vendorData(firestore);
      expect(data['name'], 'Abu Kamal Falafel');
      expect(data['description'], 'Best falafel in town');
      expect(data['pickupAddress'], 'Hamra St, Damascus');
      expect(data['pickupLatitude'], 33.5138);
      expect(data['pickupLongitude'], 36.2765);
      expect(data['ownerId'], 'owner-1');
      expect(data['approvalStatus'], 'approved');
      expect(data['ratingSum'], 9);
      expect(data['ratingCount'], 2);
    });

    test('a caller that omits the new fields (the admin form) leaves them untouched', () async {
      final firestore = await seededVendor();
      final service = FirestoreService(firestore: firestore);

      await service.updateVendorDetails(
        'vendor-1',
        category: VendorCategory.bakery,
        city: 'aleppo',
        deliveryFee: 1000,
      );

      final data = await vendorData(firestore);
      expect(data['category'], 'bakery');
      expect(data['deliveryFee'], 1000);
      expect(data['name'], 'Old name');
      expect(data['description'], 'Old description');
      expect(data.containsKey('pickupAddress'), isTrue);
      expect(data['pickupAddress'], isNull);
    });

    test('clears the pickup location when all three pickup values are null', () async {
      final firestore = await seededVendor();
      await firestore.collection('vendors').doc('vendor-1').update({
        'pickupAddress': 'Somewhere',
        'pickupLatitude': 33.5,
        'pickupLongitude': 36.3,
      });
      final service = FirestoreService(firestore: firestore);

      await service.updateVendorDetails(
        'vendor-1',
        category: VendorCategory.restaurants,
        city: 'damascus',
        updatePickupLocation: true,
        pickupAddress: '   ',
      );

      final data = await vendorData(firestore);
      expect(data['pickupAddress'], isNull);
      expect(data['pickupLatitude'], isNull);
      expect(data['pickupLongitude'], isNull);
    });

    final invalidUpdates = <String, Future<void> Function(FirestoreService)>{
      'a blank name': (s) => s.updateVendorDetails('vendor-1',
          category: VendorCategory.restaurants, city: 'damascus', name: '   '),
      'a latitude without a longitude': (s) => s.updateVendorDetails('vendor-1',
          category: VendorCategory.restaurants,
          city: 'damascus',
          updatePickupLocation: true,
          pickupAddress: 'Addr',
          pickupLatitude: 33.5),
      'a latitude above 90': (s) => s.updateVendorDetails('vendor-1',
          category: VendorCategory.restaurants,
          city: 'damascus',
          updatePickupLocation: true,
          pickupAddress: 'Addr',
          pickupLatitude: 91,
          pickupLongitude: 36.3),
      'a longitude below -180': (s) => s.updateVendorDetails('vendor-1',
          category: VendorCategory.restaurants,
          city: 'damascus',
          updatePickupLocation: true,
          pickupAddress: 'Addr',
          pickupLatitude: 33.5,
          pickupLongitude: -181),
      'a map pin with no address text': (s) => s.updateVendorDetails('vendor-1',
          category: VendorCategory.restaurants,
          city: 'damascus',
          updatePickupLocation: true,
          pickupAddress: ' ',
          pickupLatitude: 33.5,
          pickupLongitude: 36.3),
    };
    invalidUpdates.forEach((label, update) {
      test('rejects $label without writing anything', () async {
        final firestore = await seededVendor();
        final before = await vendorData(firestore);
        final service = FirestoreService(firestore: firestore);

        await expectLater(update(service), throwsArgumentError);
        expect(await vendorData(firestore), before);
      });
    });

    test('updateVendorLogo writes only logoUrl, leaving the storefront imageUrl alone', () async {
      final firestore = await seededVendor();
      await firestore.collection('vendors').doc('vendor-1').update({'imageUrl': 'https://x/storefront.jpg'});
      final service = FirestoreService(firestore: firestore);

      await service.updateVendorLogo('vendor-1', 'https://x/logo.jpg');

      final data = await vendorData(firestore);
      expect(data['logoUrl'], 'https://x/logo.jpg');
      expect(data['imageUrl'], 'https://x/storefront.jpg');
    });
  });

  group('setDriverApprovalStatus (Phase 24)', () {
    for (final status in ApprovalStatus.values) {
      test('writes approvalStatus ${status.name} and nothing else', () async {
        final firestore = FakeFirebaseFirestore();
        final driverDoc = {
          'userId': 'driver-1',
          'isAvailable': true,
          'ratingSum': 9,
          'ratingCount': 2,
          'lastKnownLocation': null,
          'approvalStatus': 'pending',
        };
        await firestore.collection('drivers').doc('driver-1').set(driverDoc);
        final service = FirestoreService(firestore: firestore);

        await service.setDriverApprovalStatus('driver-1', status);

        final data = (await firestore.collection('drivers').doc('driver-1').get()).data()!;
        expect(data, {...driverDoc, 'approvalStatus': status.name});
      });
    }
  });
}
