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
      status: OrderStatus.values.byName(map['status'] as String),
      total: (map['total'] as num).toDouble(),
      deliveryAddress: map['deliveryAddress'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        map['createdAt'] as int,
      ),
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
    };
  }
}
