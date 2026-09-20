/// Firestore-backed district record — `districts/{districtId}`. Sits one
/// tier below `cities/{cityId}` (see models/city.dart) in the approved
/// Governorate → City → District architecture. Structurally close to
/// [CityOption]/`GovernorateOption`, but [cityId] is required (not
/// nullable) — unlike `CityOption.governorateId`, a district with no city
/// isn't a meaningful interim state, it only ever exists as a subdivision
/// of a specific city (see firestore.rules' districts/{districtId} block,
/// which enforces the referenced city actually exists on both create and
/// update).
class DistrictOption {
  final String id;
  final String nameEn;
  final String nameAr;
  final String cityId;
  final bool enabled;
  final int order;

  const DistrictOption({
    required this.id,
    required this.nameEn,
    required this.nameAr,
    required this.cityId,
    required this.enabled,
    required this.order,
  });

  factory DistrictOption.fromMap(String id, Map<String, dynamic> map) {
    return DistrictOption(
      id: id,
      nameEn: map['nameEn'] as String,
      nameAr: map['nameAr'] as String,
      cityId: map['cityId'] as String,
      enabled: map['enabled'] as bool? ?? true,
      order: map['order'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'nameEn': nameEn,
      'nameAr': nameAr,
      'cityId': cityId,
      'enabled': enabled,
      'order': order,
    };
  }
}

/// Enabled districts from [districts], sorted by [DistrictOption.order] —
/// same shape and reasoning as models/city.dart's `visibleCities` and
/// models/governorate.dart's `visibleGovernorates`.
List<DistrictOption> visibleDistricts(List<DistrictOption> districts) {
  final visible = districts.where((d) => d.enabled).toList()
    ..sort((a, b) => a.order.compareTo(b.order));
  return visible;
}
