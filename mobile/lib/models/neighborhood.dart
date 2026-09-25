/// Firestore-backed neighbourhood record — `neighborhoods/{neighborhoodId}`.
/// Sits one tier below `cities/{cityId}` (see models/city.dart) in the
/// Governorate → City → Neighborhood architecture — a deliberately
/// independent model from `DistrictOption` (models/district.dart), not a
/// reuse of it: `district.dart`'s own data foundation was seeded from no
/// authoritative dataset and has no consumers anywhere in the app; this
/// model is instead backed by the validated OCHA COD-AB-SYR neighbourhood
/// extraction (see the Phase 2/3 data-acquisition reports) and is the one
/// customer-facing screens/admin tooling should use going forward.
/// `district.dart`/`districts/{districtId}` is left in place, untouched and
/// unreferenced by this model, rather than deleted — removing it is a
/// separate decision for later, not made here.
///
/// Structurally identical to `DistrictOption`/`CityOption`/`GovernorateOption`
/// (same public-read/admin-write shape in firestore.rules, same seeding
/// conventions) with one addition: [ochaPcode], an optional traceability
/// link back to the OCHA source record (e.g. "N0249") a seeded neighbourhood
/// was extracted from — null for any neighbourhood added by hand later
/// through the admin UI, never fabricated for one that wasn't OCHA-sourced.
///
/// [enabled] is also how OCHA-sourced records the Phase 3 validation report
/// classified as `INDUSTRIAL_AREA`/`SPECIAL_AREA`/`CAMP` (e.g. Aleppo's
/// "Industrial Area in Jibreen" or "University of Aleppo") are kept in the
/// dataset without deleting them — seeded with `enabled: false` so they
/// don't appear in the customer-facing neighbourhood picker, without losing
/// the underlying OCHA record. See functions/scripts/seed-neighborhoods.ts.
class NeighborhoodOption {
  final String id;
  final String nameEn;
  final String nameAr;
  final String cityId;
  final bool enabled;
  final int order;
  final String? ochaPcode;

  const NeighborhoodOption({
    required this.id,
    required this.nameEn,
    required this.nameAr,
    required this.cityId,
    required this.enabled,
    required this.order,
    this.ochaPcode,
  });

  factory NeighborhoodOption.fromMap(String id, Map<String, dynamic> map) {
    return NeighborhoodOption(
      id: id,
      nameEn: map['nameEn'] as String,
      nameAr: map['nameAr'] as String,
      cityId: map['cityId'] as String,
      enabled: map['enabled'] as bool? ?? true,
      order: map['order'] as int? ?? 0,
      ochaPcode: map['ochaPcode'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'nameEn': nameEn,
      'nameAr': nameAr,
      'cityId': cityId,
      'enabled': enabled,
      'order': order,
      'ochaPcode': ochaPcode,
    };
  }
}

/// Enabled neighbourhoods from [neighborhoods], sorted by
/// [NeighborhoodOption.order] — same shape and reasoning as
/// models/city.dart's `visibleCities`. A customer-facing neighbourhood
/// picker should always render from this, never the raw stream, so a
/// disabled (non-standard/special-area) OCHA record never appears as a
/// selectable option.
List<NeighborhoodOption> visibleNeighborhoods(List<NeighborhoodOption> neighborhoods) {
  final visible = neighborhoods.where((n) => n.enabled).toList()
    ..sort((a, b) => a.order.compareTo(b.order));
  return visible;
}
