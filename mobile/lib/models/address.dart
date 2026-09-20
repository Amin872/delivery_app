/// A customer's saved delivery address — deliberately just a free-form
/// [address] string plus a [label] (e.g. "Home", "Work"), no separate
/// street/building/apartment/postal-code fields. Matches how deliveries are
/// actually addressed in this app's target market (Syria): a full written
/// description ("Damascus, Al-Mazzeh, near ...") rather than a structured
/// Western postal address.
class DeliveryAddress {
  final String id;
  final String label;
  final String address;
  final bool isDefault;

  const DeliveryAddress({
    required this.id,
    required this.label,
    required this.address,
    this.isDefault = false,
  });

  factory DeliveryAddress.fromMap(String id, Map<String, dynamic> map) {
    return DeliveryAddress(
      id: id,
      label: map['label'] as String? ?? '',
      address: map['address'] as String,
      isDefault: map['isDefault'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'label': label,
      'address': address,
      'isDefault': isDefault,
    };
  }
}
