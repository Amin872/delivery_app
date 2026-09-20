/// Cities this delivery marketplace operates in — a small fixed set, mirroring
/// [VendorCategory]'s shape. Used both as a field on [Vendor] (which city a
/// vendor operates in) and as the customer's browsing preference (see
/// `selectedCityProvider` in `core/providers/preferences_provider.dart`).
enum City { damascus, aleppo, homs, latakia, tartus }

/// Firestore-backed city record — `cities/{cityId}`. Distinct from the
/// fixed [City] enum above: this is the future canonical source for the
/// city list (eventually managed by an Admin Locations screen, not built
/// yet), seeded with the same five cities using the exact same document
/// ids as [City]'s enum values — see `functions/scripts/seed-cities.ts` —
/// so every existing `Vendor.city` string already matches a real
/// `cities/{id}` doc with no backfill needed.
///
/// Purely additive in this phase: nothing reads [CityOption] yet. [City]
/// remains the only city type any screen or model actually uses until a
/// later migration phase switches them over.
class CityOption {
  final String id;
  final String nameEn;
  final String nameAr;
  final bool enabled;
  final int order;

  const CityOption({
    required this.id,
    required this.nameEn,
    required this.nameAr,
    required this.enabled,
    required this.order,
  });

  factory CityOption.fromMap(String id, Map<String, dynamic> map) {
    return CityOption(
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
