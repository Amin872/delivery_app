// Basic model round-trip tests. Widget tests that build DeliveryApp require
// Firebase.initializeApp(), which needs the Firebase emulator suite or a
// configured project — see integration_test/ for those instead.

import 'package:flutter_test/flutter_test.dart';

import 'package:delivery_app/models/app_user.dart';
import 'package:delivery_app/models/city.dart';
import 'package:delivery_app/models/order.dart';
import 'package:delivery_app/models/review.dart';
import 'package:delivery_app/models/vendor.dart';

void main() {
  test('AppUser round-trips through toMap/fromMap', () {
    const user = AppUser(
      id: 'user-1',
      email: 'driver@example.com',
      displayName: 'Alex Driver',
      role: UserRole.driver,
      phoneNumber: '+15551234567',
    );

    final restored = AppUser.fromMap(user.id, user.toMap());

    expect(restored.id, user.id);
    expect(restored.email, user.email);
    expect(restored.displayName, user.displayName);
    expect(restored.role, user.role);
    expect(restored.phoneNumber, user.phoneNumber);
    expect(restored.favoriteVendorIds, isEmpty);
  });

  test('AppUser round-trips favoriteVendorIds', () {
    const user = AppUser(
      id: 'user-1',
      email: 'customer@example.com',
      displayName: 'Alex Customer',
      role: UserRole.customer,
      favoriteVendorIds: ['vendor-1', 'vendor-2'],
    );

    final restored = AppUser.fromMap(user.id, user.toMap());

    expect(restored.favoriteVendorIds, ['vendor-1', 'vendor-2']);
  });

  test('DeliveryOrder round-trips through toMap/fromMap, including proofImageUrl', () {
    final order = DeliveryOrder(
      id: 'order-1',
      customerId: 'customer-1',
      vendorId: 'vendor-1',
      driverId: 'driver-1',
      items: const [
        OrderItem(menuItemId: 'item-1', name: 'Falafel', quantity: 2, unitPrice: 5000),
      ],
      status: OrderStatus.delivered,
      total: 10000,
      deliveryAddress: '123 Main St',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      proofImageUrl: 'https://example.com/proof.jpg',
    );

    final restored = DeliveryOrder.fromMap(order.id, order.toMap());

    expect(restored.id, order.id);
    expect(restored.customerId, order.customerId);
    expect(restored.vendorId, order.vendorId);
    expect(restored.driverId, order.driverId);
    expect(restored.items.length, 1);
    expect(restored.status, order.status);
    expect(restored.total, order.total);
    expect(restored.deliveryAddress, order.deliveryAddress);
    expect(restored.createdAt, order.createdAt);
    expect(restored.proofImageUrl, order.proofImageUrl);
  });

  test('Review round-trips through toMap/fromMap, including a null comment', () {
    final review = Review(
      id: 'order-1',
      orderId: 'order-1',
      customerId: 'customer-1',
      vendorId: 'vendor-1',
      driverId: 'driver-1',
      vendorRating: 5,
      driverRating: 4,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );

    final restored = Review.fromMap(review.id, review.toMap());

    expect(restored.id, review.id);
    expect(restored.orderId, review.orderId);
    expect(restored.customerId, review.customerId);
    expect(restored.vendorId, review.vendorId);
    expect(restored.driverId, review.driverId);
    expect(restored.vendorRating, review.vendorRating);
    expect(restored.driverRating, review.driverRating);
    expect(restored.comment, isNull);
    expect(restored.createdAt, review.createdAt);
  });

  test('Vendor round-trips through toMap/fromMap, including category/fee/eta', () {
    const vendor = Vendor(
      id: 'vendor-1',
      ownerId: 'owner-1',
      name: 'Green Valley Grocers',
      description: 'Neighborhood grocer',
      imageUrl: 'https://example.com/cover.jpg',
      logoUrl: 'https://example.com/logo.jpg',
      isOpen: true,
      approvalStatus: VendorApprovalStatus.approved,
      category: VendorCategory.groceries,
      city: City.aleppo,
      deliveryFee: 0,
      etaMinMinutes: 15,
      etaMaxMinutes: 25,
      minimumOrderAmount: 5000,
      openTime: '09:00',
      closeTime: '21:00',
    );

    final restored = Vendor.fromMap(vendor.id, vendor.toMap());

    expect(restored.id, vendor.id);
    expect(restored.ownerId, vendor.ownerId);
    expect(restored.name, vendor.name);
    expect(restored.imageUrl, vendor.imageUrl);
    expect(restored.logoUrl, vendor.logoUrl);
    expect(restored.category, vendor.category);
    expect(restored.city, vendor.city);
    expect(restored.deliveryFee, vendor.deliveryFee);
    expect(restored.etaMinMinutes, vendor.etaMinMinutes);
    expect(restored.etaMaxMinutes, vendor.etaMaxMinutes);
    expect(restored.minimumOrderAmount, vendor.minimumOrderAmount);
    expect(restored.openTime, vendor.openTime);
    expect(restored.closeTime, vendor.closeTime);
  });

  test('Vendor round-trips with null deliveryFee/eta/hours (not yet set by the vendor)', () {
    const vendor = Vendor(
      id: 'vendor-1',
      ownerId: 'owner-1',
      name: 'New Vendor',
      description: 'desc',
      isOpen: false,
      approvalStatus: VendorApprovalStatus.pending,
    );

    final restored = Vendor.fromMap(vendor.id, vendor.toMap());

    expect(restored.deliveryFee, isNull);
    expect(restored.etaMinMinutes, isNull);
    expect(restored.etaMaxMinutes, isNull);
    expect(restored.minimumOrderAmount, isNull);
    expect(restored.openTime, isNull);
    expect(restored.closeTime, isNull);
    // Pre-existing vendor docs written before `logoUrl` existed must still
    // parse cleanly instead of throwing — this is the backward-compat case.
    expect(restored.logoUrl, isNull);
  });

  test('MenuItem round-trips through toMap/fromMap, including description/section/orderCount', () {
    const item = MenuItem(
      id: 'item-1',
      vendorId: 'vendor-1',
      name: 'Cheeseburger',
      price: 8000,
      available: true,
      description: 'Beef patty, cheddar, house sauce',
      section: 'Burgers',
      orderCount: 42,
    );

    final restored = MenuItem.fromMap(item.id, item.toMap());

    expect(restored.id, item.id);
    expect(restored.vendorId, item.vendorId);
    expect(restored.name, item.name);
    expect(restored.price, item.price);
    expect(restored.description, item.description);
    expect(restored.section, item.section);
    expect(restored.orderCount, item.orderCount);
  });

  test('MenuItem round-trips with no description/section and default orderCount', () {
    const item = MenuItem(
      id: 'item-1',
      vendorId: 'vendor-1',
      name: 'Mystery Item',
      price: 1000,
      available: true,
    );

    final restored = MenuItem.fromMap(item.id, item.toMap());

    expect(restored.description, isNull);
    expect(restored.section, isNull);
    expect(restored.orderCount, 0);
  });
}
