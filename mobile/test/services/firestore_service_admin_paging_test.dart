import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:delivery_app/core/paging/page_result.dart';
import 'package:delivery_app/models/approval_status.dart';
import 'package:delivery_app/models/order.dart';
import 'package:delivery_app/models/promotion.dart';
import 'package:delivery_app/services/firestore_service.dart';

Future<void> _order(FakeFirebaseFirestore db, String id, OrderStatus status, DateTime createdAt) =>
    db.collection('orders').doc(id).set(DeliveryOrder(
          id: id,
          customerId: 'c',
          vendorId: 'v',
          items: const [],
          status: status,
          total: 100,
          deliveryAddress: 'a',
          createdAt: createdAt,
        ).toMap());

Future<void> _vendor(FakeFirebaseFirestore db, String id, String name, {String? status, String city = 'damascus'}) =>
    db.collection('vendors').doc(id).set({
      'ownerId': 'owner-$id',
      'name': name,
      'description': '',
      'isOpen': true,
      if (status != null) 'approvalStatus': status,
      'city': city,
    });

Future<void> _user(FakeFirebaseFirestore db, String id, String name, String email, String role) =>
    db.collection('users').doc(id).set({'email': email, 'displayName': name, 'role': role});

Future<void> _driver(FakeFirebaseFirestore db, String id, {String? status}) => db.collection('drivers').doc(id).set({
      'userId': id,
      'isAvailable': false,
      if (status != null) 'approvalStatus': status,
    });

/// Every page of [fetch], following cursors to the end.
Future<List<T>> _allPages<T>(Future<PageResult<T>> Function(Object? after) fetch) async {
  final items = <T>[];
  Object? cursor;
  while (true) {
    final page = await fetch(cursor);
    items.addAll(page.items);
    if (!page.hasMore) return items;
    cursor = page.cursor;
  }
}

void main() {
  late FakeFirebaseFirestore db;
  late FirestoreService service;

  setUp(() {
    db = FakeFirebaseFirestore();
    service = FirestoreService(firestore: db);
  });

  group('fetchOrdersPage', () {
    test('pages newest first with the requested size, no duplicates or gaps, and a correct end', () async {
      for (var i = 0; i < 7; i++) {
        await _order(db, 'o$i', OrderStatus.pending, DateTime(2026, 1, 1 + i));
      }

      final first = await service.fetchOrdersPage(limit: 3);
      expect(first.items.map((o) => o.id), ['o6', 'o5', 'o4']);
      expect(first.hasMore, isTrue);

      final second = await service.fetchOrdersPage(limit: 3, after: first.cursor);
      expect(second.items.map((o) => o.id), ['o3', 'o2', 'o1']);
      expect(second.hasMore, isTrue);

      final third = await service.fetchOrdersPage(limit: 3, after: second.cursor);
      expect(third.items.map((o) => o.id), ['o0']);
      expect(third.hasMore, isFalse);
    });

    test('an exact multiple of the page size ends without an empty extra page', () async {
      for (var i = 0; i < 4; i++) {
        await _order(db, 'o$i', OrderStatus.pending, DateTime(2026, 1, 1 + i));
      }
      final first = await service.fetchOrdersPage(limit: 2);
      final second = await service.fetchOrdersPage(limit: 2, after: first.cursor);
      expect(second.items, hasLength(2));
      expect(second.hasMore, isFalse);
    });

    test('a status filter applies on the server, before the page limit', () async {
      for (var i = 0; i < 6; i++) {
        await _order(db, 'o$i', i.isEven ? OrderStatus.delivered : OrderStatus.pending, DateTime(2026, 1, 1 + i));
      }
      final delivered = await _allPages((after) => service.fetchOrdersPage(status: OrderStatus.delivered, limit: 2, after: after));
      expect(delivered.map((o) => o.id), ['o4', 'o2', 'o0']);
    });

    test('defaults to 25 per page', () async {
      for (var i = 0; i < 26; i++) {
        await _order(db, 'o$i', OrderStatus.pending, DateTime(2026, 1, 1, 0, i));
      }
      final first = await service.fetchOrdersPage();
      expect(first.items, hasLength(kAdminPageSize));
      expect(first.hasMore, isTrue);
    });
  });

  group('fetchVendorsPage', () {
    setUp(() async {
      await _vendor(db, 'v1', 'Burger Spot', status: 'approved');
      await _vendor(db, 'v2', 'Bakery Lane', status: 'pending');
      await _vendor(db, 'v3', 'Zaatar House', status: 'approved');
      await _vendor(db, 'v4', 'Legacy Grill'); // no approvalStatus
    });

    test('without filters, every vendor (legacy docs included) across pages', () async {
      final all = await _allPages((after) => service.fetchVendorsPage(limit: 2, after: after));
      expect(all.map((v) => v.id).toSet(), {'v1', 'v2', 'v3', 'v4'});
      expect(all, hasLength(4));
    });

    test('a status filter matches only that stored status', () async {
      final approved = await _allPages((after) => service.fetchVendorsPage(status: ApprovalStatus.approved, after: after));
      expect(approved.map((v) => v.id).toSet(), {'v1', 'v3'});
    });

    test('the search is a name prefix, case-sensitive, combinable with a status', () async {
      final b = await service.fetchVendorsPage(namePrefix: 'B');
      expect(b.items.map((v) => v.name), ['Bakery Lane', 'Burger Spot']);

      expect((await service.fetchVendorsPage(namePrefix: 'b')).items, isEmpty);
      expect((await service.fetchVendorsPage(namePrefix: 'urger')).items, isEmpty);

      final approvedB = await service.fetchVendorsPage(status: ApprovalStatus.approved, namePrefix: 'B');
      expect(approvedB.items.map((v) => v.id), ['v1']);
    });
  });

  group('fetchUsersPage', () {
    test('a plain search matches the display name, one with "@" matches the email', () async {
      await _user(db, 'u1', 'Rana Haddad', 'rana@example.com', 'customer');
      await _user(db, 'u2', 'Omar Saleh', 'omar@example.com', 'driver');

      expect((await service.fetchUsersPage(search: 'Ra')).items.map((u) => u.id), ['u1']);
      expect((await service.fetchUsersPage(search: 'omar@')).items.map((u) => u.id), ['u2']);
      expect((await service.fetchUsersPage()).items, hasLength(2));
      expect(FirestoreService.userSearchField('a@b'), 'email');
      expect(FirestoreService.userSearchField('Rana'), 'displayName');
    });
  });

  group('fetchDriverAccountsPage', () {
    setUp(() async {
      await _user(db, 'd1', 'Pending Paul', 'paul@example.com', 'driver');
      await _driver(db, 'd1', status: 'pending');
      await _user(db, 'd2', 'Approved Adam', 'adam@example.com', 'driver');
      await _driver(db, 'd2', status: 'approved');
      await _user(db, 'd3', 'Approved Amal', 'amal@example.com', 'driver');
      await _driver(db, 'd3', status: 'approved');
      await _driver(db, 'orphan', status: 'approved'); // no users doc
      await _user(db, 'c1', 'Approved Customer', 'cust@example.com', 'customer');
    });

    test('pages driver docs joined with their users, skipping accounts missing a doc', () async {
      final all = await _allPages((after) => service.fetchDriverAccountsPage(limit: 2, after: after));
      expect(all.map((a) => a.driver.id).toSet(), {'d1', 'd2', 'd3'});
      expect(all.firstWhere((a) => a.driver.id == 'd2').user.displayName, 'Approved Adam');
    });

    test('an approval status filter applies on the server', () async {
      final approved = await _allPages(
          (after) => service.fetchDriverAccountsPage(status: ApprovalStatus.approved, after: after));
      expect(approved.map((a) => a.driver.id).toSet(), {'d2', 'd3'});
    });

    test('a search pages driver-role users by name prefix and joins their driver docs', () async {
      final page = await service.fetchDriverAccountsPage(search: 'Approved A');
      expect(page.items.map((a) => a.driver.id), ['d2', 'd3']); // not the customer
    });

    test('fetchDriverAccount reads one account, or null when a doc is missing', () async {
      expect((await service.fetchDriverAccount('d1'))?.user.displayName, 'Pending Paul');
      expect(await service.fetchDriverAccount('orphan'), isNull);
    });
  });

  group('fetchMenuItemsPage', () {
    setUp(() async {
      Future<void> item(String vendorId, String id, String name, {bool? available}) =>
          db.collection('vendors').doc(vendorId).collection('menuItems').doc(id).set({
            'vendorId': vendorId,
            'name': name,
            'price': 1000,
            if (available != null) 'available': available,
          });
      await item('v1', 'i1', 'Falafel', available: true);
      await item('v1', 'i2', 'Fattoush', available: false);
      await item('v2', 'i1', 'Shawarma', available: true);
      await item('v2', 'i3', 'Legacy dish'); // no `available` field
    });

    test('pages every vendor\'s items', () async {
      final all = await _allPages((after) => service.fetchMenuItemsPage(limit: 3, after: after));
      expect(all.map((i) => '${i.vendorId}/${i.id}').toSet(), {'v1/i1', 'v1/i2', 'v2/i1', 'v2/i3'});
    });

    test('availability filter and name prefix apply on the server', () async {
      final available = await service.fetchMenuItemsPage(available: true);
      expect(available.items.map((i) => i.name).toSet(), {'Falafel', 'Shawarma'});
      final fa = await service.fetchMenuItemsPage(namePrefix: 'Fa');
      expect(fa.items.map((i) => i.name), ['Falafel', 'Fattoush']);
      final availableFa = await service.fetchMenuItemsPage(available: false, namePrefix: 'Fa');
      expect(availableFa.items.map((i) => i.name), ['Fattoush']);
    });
  });

  test('a malformed document is left out of a page instead of failing it', () async {
    await _vendor(db, 'v1', 'Good One', status: 'approved');
    await db.collection('vendors').doc('v2').set({'name': 'Broken'}); // no ownerId/description
    final page = await service.fetchVendorsPage();
    expect(page.items.map((v) => v.id), ['v1']);
    expect(page.hasMore, isFalse);
  });

  test('fetchVendorsByIds batches more than 30 ids and skips missing ones', () async {
    for (var i = 0; i < 35; i++) {
      await _vendor(db, 'v$i', 'Vendor $i', status: 'approved');
    }
    final found = await service.fetchVendorsByIds([for (var i = 0; i < 35; i++) 'v$i', 'missing', 'v0']);
    expect(found.keys.toSet(), {for (var i = 0; i < 35; i++) 'v$i'});
  });

  test('fetchVendor and fetchOrder return null for a missing doc', () async {
    expect(await service.fetchVendor('nope'), isNull);
    expect(await service.fetchOrder('nope'), isNull);
  });

  group('pending counts', () {
    test('count every vendor/driver that is neither approved nor rejected, legacy docs included', () async {
      await _vendor(db, 'v1', 'A', status: 'pending');
      await _vendor(db, 'v2', 'B'); // legacy: no status
      await _vendor(db, 'v3', 'C', status: 'approved');
      await _vendor(db, 'v4', 'D', status: 'rejected');
      await _driver(db, 'd1', status: 'pending');
      await _driver(db, 'd2');
      await _driver(db, 'd3', status: 'approved');

      expect(await service.countPendingVendors(), 2);
      expect(await service.countPendingDrivers(), 2);
    });

    test('are zero for empty collections', () async {
      expect(await service.countPendingVendors(), 0);
      expect(await service.countPendingDrivers(), 0);
    });
  });

  test('countVendorsInCities counts vendors in any of the cities, across more than 30 cities', () async {
    await _vendor(db, 'v1', 'A', city: 'damascus');
    await _vendor(db, 'v2', 'B', city: 'douma');
    await _vendor(db, 'v3', 'C', city: 'aleppo');
    await _vendor(db, 'v4', 'D', city: 'city34');

    expect(await service.countVendorsInCities(['damascus', 'douma']), 2);
    expect(await service.countVendorsInCities(['homs']), 0);
    expect(await service.countVendorsInCities(const []), 0);
    expect(await service.countVendorsInCities([for (var i = 0; i < 35; i++) 'city$i', 'aleppo']), 2);
  });

  group('updatePromotionDetails', () {
    Promotion promotion({required bool enabled, String title = 'New'}) => Promotion(
          id: 'p1',
          title: title,
          mediaUrl: 'https://example.com/m.jpg',
          mediaType: PromotionMediaType.image,
          order: 2,
          enabled: enabled,
        );

    setUp(() async {
      await db.collection('promotions').doc('p1').set({
        'title': 'Old',
        'mediaUrl': 'https://example.com/m.jpg',
        'mediaType': 'image',
        'order': 1,
        'enabled': false,
      });
    });

    test('without includeEnabled, leaves the stored enabled flag untouched', () async {
      await service.updatePromotionDetails(promotion(enabled: true), includeEnabled: false);
      final data = (await db.collection('promotions').doc('p1').get()).data()!;
      expect(data['title'], 'New');
      expect(data['order'], 2);
      expect(data['enabled'], isFalse);
    });

    test('with includeEnabled, writes it', () async {
      await service.updatePromotionDetails(promotion(enabled: true), includeEnabled: true);
      expect((await db.collection('promotions').doc('p1').get()).data()!['enabled'], isTrue);
    });
  });
}
