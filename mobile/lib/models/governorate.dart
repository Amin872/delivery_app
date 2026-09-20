/// Firestore-backed governorate record — `governorates/{governorateId}`.
/// Sits one tier above `cities/{cityId}` (see models/city.dart's
/// `governorateId`) in the approved Governorate → City architecture.
/// Structurally identical to [CityOption] — same public-read/admin-write
/// shape in firestore.rules, same seeding conventions.
class GovernorateOption {
  final String id;
  final String nameEn;
  final String nameAr;
  final bool enabled;
  final int order;

  const GovernorateOption({
    required this.id,
    required this.nameEn,
    required this.nameAr,
    required this.enabled,
    required this.order,
  });

  factory GovernorateOption.fromMap(String id, Map<String, dynamic> map) {
    return GovernorateOption(
      id: id,
      nameEn: map['nameEn'] as String,
      nameAr: map['nameAr'] as String,
      enabled: map['enabled'] as bool? ?? true,
      order: map['order'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'nameEn': nameEn,
      'nameAr': nameAr,
      'enabled': enabled,
      'order': order,
    };
  }
}
