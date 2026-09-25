import '../core/parsing/safe_enum.dart';
import 'coordinates.dart';

enum OrderStatus {
  pending,
  accepted,
  preparing,
  readyForPickup,
  // Phase 4 addition: a driver has claimed the order (via the
  // `acceptDelivery` callable) but hasn't yet physically collected it from
  // the vendor — distinct from [pickedUp]. Inserted between
  // [readyForPickup] and [pickedUp] as a pure addition; every other value's
  // name/wire string is unchanged from before Phase 4, so no already-stored
  // order document's status needs migrating. See functions/src/orders.ts's
  // `acceptDelivery`/`advanceDelivery`/DRIVER_PROGRESSION.
  driverAssigned,
  pickedUp,
  delivering,
  delivered,
  cancelled,
}

class OrderItem {
  final String menuItemId;
  final String name;
  final int quantity;
  final double unitPrice;

  const OrderItem({
    required this.menuItemId,
    required this.name,
    required this.quantity,
    required this.unitPrice,
  });

  factory OrderItem.fromMap(Map<String, dynamic> map) {
    return OrderItem(
      menuItemId: map['menuItemId'] as String,
      name: map['name'] as String,
      quantity: map['quantity'] as int,
      unitPrice: (map['unitPrice'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'menuItemId': menuItemId,
      'name': name,
      'quantity': quantity,
      'unitPrice': unitPrice,
    };
  }
}

class DeliveryOrder {
  final String id;
  final String customerId;
  final String vendorId;
  final String? driverId;
  final List<OrderItem> items;
  final OrderStatus status;
  final double total;
  final String deliveryAddress;
  final DateTime createdAt;
  // Set by the `advanceDelivery` callable when the assigned driver marks the
  // order delivered with a photo attached — see functions/src/orders.ts and
  // storage.rules' orderProofs/{orderId} match block.
  final String? proofImageUrl;

  // Phase 4 location-first additions — all optional so every order created
  // before this phase (which only ever had the free-text [deliveryAddress]
  // above) keeps parsing unchanged. [deliveryLatitude]/[deliveryLongitude]
  // are the PRIMARY source of where a delivery goes once set (copied from
  // the customer's chosen SavedAddress/map pin at order-creation time, see
  // CartScreen) — [deliveryAddress] remains the human-readable text shown
  // to the vendor/driver, never parsed for routing/distance.
  final double? deliveryLatitude;
  final double? deliveryLongitude;
  final String? governorateId;
  final String? cityId;
  // Never required — see models/address.dart's SavedAddress.neighborhoodId
  // note; an order can be placed with a precise pin and no neighbourhood
  // classification at all.
  final String? neighborhoodId;
  final String? deliveryInstructions;
  final String? driverNote;

  // Pricing breakdown — target model is `total = subtotal + deliveryFee`.
  // All optional: orders created before these fields existed carry only
  // [total], which historically was the item subtotal alone (no fee was
  // ever added). Read through [effectiveSubtotal]/[effectiveDeliveryFee]
  // rather than these raw fields; stored documents are never rewritten to
  // fill them in.
  final double? subtotal;
  final double? deliveryFee;

  // Vendor snapshot taken when the order is placed, so the order keeps
  // showing where to collect it even if the vendor later edits their
  // storefront. Same names as the Vendor fields they're copied from. Null on
  // orders created before these fields existed.
  final String? vendorName;
  final String? pickupAddress;
  final double? pickupLatitude;
  final double? pickupLongitude;

  const DeliveryOrder({
    required this.id,
    required this.customerId,
    required this.vendorId,
    this.driverId,
    required this.items,
    required this.status,
    required this.total,
    required this.deliveryAddress,
    required this.createdAt,
    this.proofImageUrl,
    this.deliveryLatitude,
    this.deliveryLongitude,
    this.governorateId,
    this.cityId,
    this.neighborhoodId,
    this.deliveryInstructions,
    this.driverNote,
    this.subtotal,
    this.deliveryFee,
    this.vendorName,
    this.pickupAddress,
    this.pickupLatitude,
    this.pickupLongitude,
  });

  /// Item subtotal. Falls back to [total] for orders created before
  /// [subtotal] existed, when [total] was the item subtotal.
  double get effectiveSubtotal => subtotal ?? total;

  /// Delivery fee, 0 when not recorded (every order created before
  /// [deliveryFee] existed was placed without one).
  double get effectiveDeliveryFee => deliveryFee ?? 0;

  /// The drop-off point, or null when the order has no pin (orders placed
  /// before coordinates were required). Read-only convenience — same shape
  /// as SavedAddress.coordinates; nothing new is stored.
  Coordinates? get deliveryCoordinates =>
      (deliveryLatitude != null && deliveryLongitude != null)
          ? Coordinates(latitude: deliveryLatitude!, longitude: deliveryLongitude!)
          : null;

  /// The vendor's pickup point snapshotted at order time, or null when the
  /// vendor hadn't set one (or the order predates the snapshot).
  Coordinates? get pickupCoordinates =>
      (pickupLatitude != null && pickupLongitude != null)
          ? Coordinates(latitude: pickupLatitude!, longitude: pickupLongitude!)
          : null;

  factory DeliveryOrder.fromMap(String id, Map<String, dynamic> map) {
    return DeliveryOrder(
      id: id,
      customerId: map['customerId'] as String,
      vendorId: map['vendorId'] as String,
      driverId: map['driverId'] as String?,
      items: (map['items'] as List<dynamic>)
          .map((item) => OrderItem.fromMap(item as Map<String, dynamic>))
          .toList(),
      status: enumByName(OrderStatus.values, map['status'] as String?),
      total: (map['total'] as num).toDouble(),
      deliveryAddress: map['deliveryAddress'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        map['createdAt'] as int,
      ),
      proofImageUrl: map['proofImageUrl'] as String?,
      deliveryLatitude: (map['deliveryLatitude'] as num?)?.toDouble(),
      deliveryLongitude: (map['deliveryLongitude'] as num?)?.toDouble(),
      governorateId: map['governorateId'] as String?,
      cityId: map['cityId'] as String?,
      neighborhoodId: map['neighborhoodId'] as String?,
      deliveryInstructions: map['deliveryInstructions'] as String?,
      driverNote: map['driverNote'] as String?,
      subtotal: (map['subtotal'] as num?)?.toDouble(),
      deliveryFee: (map['deliveryFee'] as num?)?.toDouble(),
      vendorName: map['vendorName'] as String?,
      pickupAddress: map['pickupAddress'] as String?,
      pickupLatitude: (map['pickupLatitude'] as num?)?.toDouble(),
      pickupLongitude: (map['pickupLongitude'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'customerId': customerId,
      'vendorId': vendorId,
      'driverId': driverId,
      'items': items.map((item) => item.toMap()).toList(),
      'status': status.name,
      'total': total,
      'deliveryAddress': deliveryAddress,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'proofImageUrl': proofImageUrl,
      'deliveryLatitude': deliveryLatitude,
      'deliveryLongitude': deliveryLongitude,
      'governorateId': governorateId,
      'cityId': cityId,
      'neighborhoodId': neighborhoodId,
      'deliveryInstructions': deliveryInstructions,
      'driverNote': driverNote,
      'subtotal': subtotal,
      'deliveryFee': deliveryFee,
      'vendorName': vendorName,
      'pickupAddress': pickupAddress,
      'pickupLatitude': pickupLatitude,
      'pickupLongitude': pickupLongitude,
    };
  }
}
