import 'package:flutter_test/flutter_test.dart';

import 'package:delivery_app/core/discovery/vendor_carousels.dart';
import 'package:delivery_app/models/vendor.dart';

Vendor _vendor(
  String id, {
  VendorCategory category = VendorCategory.groceries,
  double? deliveryFee,
  int? etaMinMinutes,
  int ratingCount = 0,
}) {
  return Vendor(
    id: id,
    ownerId: 'owner-$id',
    name: 'Vendor $id',
    description: 'desc',
    isOpen: true,
    approvalStatus: VendorApprovalStatus.approved,
    category: category,
    deliveryFee: deliveryFee,
    etaMinMinutes: etaMinMinutes,
    ratingCount: ratingCount,
  );
}

void main() {
  group('fastestDeliveryVendors', () {
    test('sorts by etaMinMinutes ascending, nulls last, and respects limit', () {
      final vendors = [
        _vendor('slow', etaMinMinutes: 40),
        _vendor('no-eta'),
        _vendor('fast', etaMinMinutes: 10),
        _vendor('medium', etaMinMinutes: 20),
      ];

      final result = fastestDeliveryVendors(vendors, limit: 3);

      expect(result.map((v) => v.id), ['fast', 'medium', 'slow']);
    });

    test('returns an empty list for an empty input', () {
      expect(fastestDeliveryVendors(const []), isEmpty);
    });
  });

  group('dealVendors', () {
    test('returns only vendors with deliveryFee == 0', () {
      final vendors = [
        _vendor('free', deliveryFee: 0),
        _vendor('paid', deliveryFee: 500),
        _vendor('unset'),
      ];

      expect(dealVendors(vendors).map((v) => v.id), ['free']);
    });
  });

  group('selfcareVendors', () {
    test('returns only pharmacy-category vendors', () {
      final vendors = [
        _vendor('pharmacy-1', category: VendorCategory.pharmacy),
        _vendor('groceries-1'),
      ];

      expect(selfcareVendors(vendors).map((v) => v.id), ['pharmacy-1']);
    });
  });

  group('popularVendors', () {
    test('sorts by ratingCount descending and excludes unrated vendors', () {
      final vendors = [
        _vendor('unrated'),
        _vendor('bronze', ratingCount: 5),
        _vendor('gold', ratingCount: 50),
        _vendor('silver', ratingCount: 20),
      ];

      final result = popularVendors(vendors, limit: 2);

      expect(result.map((v) => v.id), ['gold', 'silver']);
    });
  });

  group('vendorsInCategory', () {
    test('filters by exact category equality', () {
      final vendors = [
        _vendor('restaurant-1', category: VendorCategory.restaurants),
        _vendor('bakery-1', category: VendorCategory.bakery),
      ];

      expect(
        vendorsInCategory(vendors, VendorCategory.restaurants).map((v) => v.id),
        ['restaurant-1'],
      );
    });
  });

  group('productsFromVendors', () {
    MenuItem item(String id, String vendorId, {bool available = true}) => MenuItem(
          id: id,
          vendorId: vendorId,
          name: 'Item $id',
          price: 10,
          available: available,
        );

    test('keeps only available items whose vendor is in the given list, capped at limit', () {
      final vendors = [_vendor('v1'), _vendor('v2')];
      final items = [
        item('a', 'v1'),
        item('b', 'v2'),
        item('c', 'v3'), // vendor not in the list — excluded
        item('d', 'v1', available: false), // unavailable — excluded
      ];

      final result = productsFromVendors(items, vendors, limit: 1);

      expect(result.map((i) => i.id), ['a']);
    });

    test('returns an empty list when no vendors are given', () {
      expect(productsFromVendors([item('a', 'v1')], const []), isEmpty);
    });
  });
}
