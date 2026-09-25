import 'coordinates.dart';

/// A customer's saved delivery location — `users/{userId}/addresses/{id}`.
/// Location-first (Phase 4): [latitude]/[longitude] are the primary source
/// of truth for where a delivery actually goes — [addressText] is a
/// human-written description shown to the vendor/driver, not parsed for
/// routing. [governorateId]/[cityId]/[neighborhoodId] are best-effort
/// classification (auto-resolved via reverse geocoding + `LocationMatcher`
/// when the pin is placed, editable/overridable by the customer) — never
/// required to save an address, see [neighborhoodId]'s own note.
///
/// [latitude]/[longitude]/[createdAt]/[updatedAt] are nullable even though
/// every address created through the new map-first flow always sets them —
/// this is deliberate backward compatibility with any pre-existing
/// `DeliveryAddress` docs (this class's previous name/shape) written before
/// Phase 4, which only ever stored [label]/[addressText]/[isDefault] and
/// would otherwise fail to parse. Same reasoning as `CityOption
/// .governorateId`'s own nullability for pre-migration docs. A screen
/// rendering an address with a null [latitude]/[longitude] simply has no
/// map pin to show — the free-text [addressText] is still always present
/// and always renderable.
class SavedAddress {
  final String id;
  final String userId;
  final String label;
  final double? latitude;
  final double? longitude;
  final String? governorateId;
  final String? cityId;
  // Deliberately optional — see Phase 4 requirement that a neighbourhood
  // selection must never block completing an address/order. Left
  // unresolved (null) when reverse geocoding has no match, or when the
  // customer removes/never confirms the auto-suggested value.
  final String? neighborhoodId;
  final String addressText;
  final String? deliveryInstructions;
  final String? driverNote;
  final String? phone;
  final bool isDefault;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const SavedAddress({
    required this.id,
    required this.userId,
    required this.label,
    this.latitude,
    this.longitude,
    this.governorateId,
    this.cityId,
    this.neighborhoodId,
    required this.addressText,
    this.deliveryInstructions,
    this.driverNote,
    this.phone,
    this.isDefault = false,
    this.createdAt,
    this.updatedAt,
  });

  Coordinates? get coordinates =>
      (latitude != null && longitude != null) ? Coordinates(latitude: latitude!, longitude: longitude!) : null;

  factory SavedAddress.fromMap(String id, Map<String, dynamic> map) {
    return SavedAddress(
      id: id,
      userId: map['userId'] as String? ?? '',
      label: map['label'] as String? ?? '',
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      governorateId: map['governorateId'] as String?,
      cityId: map['cityId'] as String?,
      neighborhoodId: map['neighborhoodId'] as String?,
      // Pre-Phase-4 docs stored this under 'address' rather than
      // 'addressText' — fall back so an old saved address still renders its
      // full text instead of appearing blank.
      addressText: (map['addressText'] ?? map['address']) as String,
      deliveryInstructions: map['deliveryInstructions'] as String?,
      driverNote: map['driverNote'] as String?,
      phone: map['phone'] as String?,
      isDefault: map['isDefault'] as bool? ?? false,
      createdAt: map['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int)
          : null,
      updatedAt: map['updatedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['updatedAt'] as int)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'label': label,
      'latitude': latitude,
      'longitude': longitude,
      'governorateId': governorateId,
      'cityId': cityId,
      'neighborhoodId': neighborhoodId,
      'addressText': addressText,
      'deliveryInstructions': deliveryInstructions,
      'driverNote': driverNote,
      'phone': phone,
      'isDefault': isDefault,
      'createdAt': createdAt?.millisecondsSinceEpoch,
      'updatedAt': updatedAt?.millisecondsSinceEpoch,
    };
  }

  SavedAddress copyWith({
    String? label,
    double? latitude,
    double? longitude,
    String? governorateId,
    String? cityId,
    String? neighborhoodId,
    String? addressText,
    String? deliveryInstructions,
    String? driverNote,
    String? phone,
    bool? isDefault,
  }) {
    return SavedAddress(
      id: id,
      userId: userId,
      label: label ?? this.label,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      governorateId: governorateId ?? this.governorateId,
      cityId: cityId ?? this.cityId,
      neighborhoodId: neighborhoodId ?? this.neighborhoodId,
      addressText: addressText ?? this.addressText,
      deliveryInstructions: deliveryInstructions ?? this.deliveryInstructions,
      driverNote: driverNote ?? this.driverNote,
      phone: phone ?? this.phone,
      isDefault: isDefault ?? this.isDefault,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
