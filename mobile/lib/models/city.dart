/// The five cities this marketplace has always operated in, as canonical
/// Firestore document ids (`cities/{id}`) — same ids the retired `City`
/// enum used to declare, in the same order. Used as a last-resort picker
/// fallback wherever the live `cities` collection (see [CityOption]) is
/// empty or hasn't loaded yet (e.g. before it's been seeded, or a
/// transient network hiccup), so a city picker is never left with nothing
/// to show. Display names for these ids are resolved through
/// `cityLabel`'s own ARB-based fallback (`core/l10n/enum_labels.dart`) —
/// this list only carries the ids themselves, never a hardcoded name.
const legacyCityIds = ['damascus', 'aleppo', 'homs', 'latakia', 'tartus'];

/// Firestore-backed city record — `cities/{cityId}`. The canonical source
/// for the city list, seeded with the same five cities and the same
/// document ids [legacyCityIds] names — see
/// `functions/scripts/seed-cities.ts` — so every existing `Vendor.city`
/// string (a plain id, see models/vendor.dart) already matches a real
/// `cities/{id}` doc with no backfill needed.
class CityOption {
  final String id;
  final String nameEn;
  final String nameAr;
  final bool enabled;
  final int order;
  // Optional link to governorates/{governorateId} (see models/governorate.dart)
  // — additive, Locations Phase 3. Null for a city that hasn't been grouped
  // under a governorate yet; every existing consumer that doesn't care about
  // this field keeps working unmodified, same as enabled/order's own
  // absent-safe defaulting above.
  final String? governorateId;

  const CityOption({
    required this.id,
    required this.nameEn,
    required this.nameAr,
    required this.enabled,
    required this.order,
    this.governorateId,
  });

  factory CityOption.fromMap(String id, Map<String, dynamic> map) {
    return CityOption(
      id: id,
      nameEn: map['nameEn'] as String,
      nameAr: map['nameAr'] as String,
      enabled: map['enabled'] as bool? ?? true,
      order: map['order'] as int? ?? 0,
      governorateId: map['governorateId'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'nameEn': nameEn,
      'nameAr': nameAr,
      'enabled': enabled,
      'order': order,
      'governorateId': governorateId,
    };
  }
}

/// Enabled cities from [cities], sorted by [CityOption.order] — the shape
/// every city picker actually wants to render. Pure so it's testable
/// without Firebase/Riverpod, same reasoning as core/discovery's functions.
List<CityOption> visibleCities(List<CityOption> cities) {
  final visible = cities.where((c) => c.enabled).toList()
    ..sort((a, b) => a.order.compareTo(b.order));
  return visible;
}
