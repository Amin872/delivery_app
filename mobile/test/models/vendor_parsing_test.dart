import 'package:flutter_test/flutter_test.dart';

import 'package:delivery_app/models/vendor.dart';

void main() {
  test('Vendor.fromMap defaults category to groceries when the field is missing', () {
    // Every vendor doc written before this field existed (and any written by
    // another integration entirely) lacks `category` — this must not throw,
    // unlike AppUser's unknown-role handling, since watchOpenVendors() would
    // otherwise break for every pre-existing vendor. See the comment on
    // Vendor.fromMap.
    final vendor = Vendor.fromMap('vendor-1', {
      'ownerId': 'owner-1',
      'name': 'Legacy Vendor',
      'description': 'No category field at all',
      'isOpen': true,
      'approvalStatus': 'approved',
    });

    expect(vendor.category, VendorCategory.groceries);
  });

  test('Vendor.fromMap defaults category to groceries for an unrecognized value', () {
    final vendor = Vendor.fromMap('vendor-1', {
      'ownerId': 'owner-1',
      'name': 'Vendor',
      'description': 'desc',
      'isOpen': true,
      'approvalStatus': 'approved',
      'category': 'not-a-real-category',
    });

    expect(vendor.category, VendorCategory.groceries);
  });

  test('Vendor.fromMap defaults city to damascus when the field is missing', () {
    // Same backward-compatibility reasoning as category above — city
    // postdates every pre-existing vendor doc.
    final vendor = Vendor.fromMap('vendor-1', {
      'ownerId': 'owner-1',
      'name': 'Legacy Vendor',
      'description': 'No city field at all',
      'isOpen': true,
      'approvalStatus': 'approved',
    });

    expect(vendor.city, 'damascus');
  });

  test('Vendor.fromMap preserves a city id string it doesn\'t recognize', () {
    // Unlike the fixed category enum above, `city` is now an open string id
    // (see the Locations/City migration) — a value that isn't one of the
    // five legacy ids might be a real, live `cities/{id}` doc (e.g. one an
    // admin added later), so it must be preserved rather than silently
    // reset to a default.
    final vendor = Vendor.fromMap('vendor-1', {
      'ownerId': 'owner-1',
      'name': 'Vendor',
      'description': 'desc',
      'isOpen': true,
      'approvalStatus': 'approved',
      'city': 'a-future-admin-added-city',
    });

    expect(vendor.city, 'a-future-admin-added-city');
  });

  test('Vendor round-trips a legacy city id unchanged', () {
    final vendor = Vendor.fromMap('vendor-1', {
      'ownerId': 'owner-1',
      'name': 'Vendor',
      'description': 'desc',
      'isOpen': true,
      'approvalStatus': 'approved',
      'city': 'aleppo',
    });

    expect(vendor.city, 'aleppo');
    expect(vendor.toMap()['city'], 'aleppo');
  });
}
