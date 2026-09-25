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

  group('pickup location', () {
    Map<String, dynamic> baseVendor() => {
          'ownerId': 'owner-1',
          'name': 'Vendor',
          'description': 'desc',
          'isOpen': true,
          'approvalStatus': 'approved',
        };

    test('parses and round-trips pickup fields when present', () {
      final vendor = Vendor.fromMap('vendor-1', {
        ...baseVendor(),
        'pickupAddress': 'Hamra St, Damascus',
        'pickupLatitude': 33.5138,
        // Firestore may hand back an int for a whole-number double.
        'pickupLongitude': 36,
      });

      expect(vendor.pickupAddress, 'Hamra St, Damascus');
      expect(vendor.pickupLatitude, 33.5138);
      expect(vendor.pickupLongitude, 36.0);

      final map = vendor.toMap();
      expect(map['pickupAddress'], 'Hamra St, Damascus');
      expect(map['pickupLatitude'], 33.5138);
      expect(map['pickupLongitude'], 36.0);
    });

    test('leaves pickup fields null for a vendor doc that predates them', () {
      final vendor = Vendor.fromMap('vendor-1', baseVendor());

      expect(vendor.pickupAddress, isNull);
      expect(vendor.pickupLatitude, isNull);
      expect(vendor.pickupLongitude, isNull);
      // No fabricated coordinate is written back either.
      final map = vendor.toMap();
      expect(map['pickupLatitude'], isNull);
      expect(map['pickupLongitude'], isNull);
    });

    test('tolerates partial pickup data without crashing or inventing values', () {
      final vendor = Vendor.fromMap('vendor-1', {
        ...baseVendor(),
        'pickupAddress': 'Address only, no pin yet',
        'pickupLatitude': null,
      });

      expect(vendor.pickupAddress, 'Address only, no pin yet');
      expect(vendor.pickupLatitude, isNull);
      expect(vendor.pickupLongitude, isNull);
    });

    test('round-trips logoUrl separately from the storefront imageUrl', () {
      final vendor = Vendor.fromMap('vendor-1', {
        ...baseVendor(),
        'imageUrl': 'https://x/storefront.jpg',
        'logoUrl': 'https://x/logo.jpg',
      });
      expect(vendor.logoUrl, 'https://x/logo.jpg');
      expect(vendor.imageUrl, 'https://x/storefront.jpg');
      expect(vendor.toMap()['logoUrl'], 'https://x/logo.jpg');
      expect(Vendor.fromMap('vendor-1', baseVendor()).logoUrl, isNull);
    });

    test('keeps the existing approvalStatus parsing: missing still reads as pending', () {
      final map = baseVendor()..remove('approvalStatus');
      final vendor = Vendor.fromMap('vendor-1', map);

      expect(vendor.approvalStatus, VendorApprovalStatus.pending);
    });
  });

  group('validatePickupLocation', () {
    test('accepts no pickup location at all, and an address without a pin yet', () {
      expect(validatePickupLocation(), isNull);
      expect(validatePickupLocation(address: 'Hamra St'), isNull);
    });

    test('accepts a pin with an address, including the coordinate boundaries', () {
      expect(validatePickupLocation(address: 'Hamra St', latitude: 33.5, longitude: 36.3), isNull);
      expect(validatePickupLocation(address: 'Edge', latitude: -90, longitude: 180), isNull);
    });

    test('requires both coordinates together', () {
      expect(validatePickupLocation(address: 'A', latitude: 33.5),
          PickupLocationError.incompleteCoordinates);
      expect(validatePickupLocation(address: 'A', longitude: 36.3),
          PickupLocationError.incompleteCoordinates);
    });

    test('rejects out-of-range or non-finite coordinates', () {
      expect(validatePickupLocation(address: 'A', latitude: 90.5, longitude: 36.3),
          PickupLocationError.latitudeOutOfRange);
      expect(validatePickupLocation(address: 'A', latitude: double.nan, longitude: 36.3),
          PickupLocationError.latitudeOutOfRange);
      expect(validatePickupLocation(address: 'A', latitude: 33.5, longitude: -180.5),
          PickupLocationError.longitudeOutOfRange);
    });

    test('a pin needs readable address text', () {
      expect(validatePickupLocation(latitude: 33.5, longitude: 36.3),
          PickupLocationError.addressRequired);
      expect(validatePickupLocation(address: '  ', latitude: 33.5, longitude: 36.3),
          PickupLocationError.addressRequired);
    });
  });
}
