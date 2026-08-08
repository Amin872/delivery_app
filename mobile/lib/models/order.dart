import '../core/parsing/safe_enum.dart';

enum OrderStatus {
  pending,
  accepted,
  preparing,
  readyForPickup,
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
  });

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
    };
  }
}
