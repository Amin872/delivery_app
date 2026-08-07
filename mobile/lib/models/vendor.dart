class Vendor {
  final String id;
  final String ownerId;
  final String name;
  final String description;
  final String? imageUrl;
  final bool isOpen;

  const Vendor({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.description,
    this.imageUrl,
    required this.isOpen,
  });

  factory Vendor.fromMap(String id, Map<String, dynamic> map) {
    return Vendor(
      id: id,
      ownerId: map['ownerId'] as String,
      name: map['name'] as String,
      description: map['description'] as String,
      imageUrl: map['imageUrl'] as String?,
      isOpen: map['isOpen'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'ownerId': ownerId,
      'name': name,
      'description': description,
      'imageUrl': imageUrl,
      'isOpen': isOpen,
    };
  }
}

class MenuItem {
  final String id;
  final String vendorId;
  final String name;
  final double price;
  final String? imageUrl;
  final bool available;

  const MenuItem({
    required this.id,
    required this.vendorId,
    required this.name,
    required this.price,
    this.imageUrl,
    required this.available,
  });

  factory MenuItem.fromMap(String id, Map<String, dynamic> map) {
    return MenuItem(
      id: id,
      vendorId: map['vendorId'] as String,
      name: map['name'] as String,
      price: (map['price'] as num).toDouble(),
      imageUrl: map['imageUrl'] as String?,
      available: map['available'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'vendorId': vendorId,
      'name': name,
      'price': price,
      'imageUrl': imageUrl,
      'available': available,
    };
  }
}
