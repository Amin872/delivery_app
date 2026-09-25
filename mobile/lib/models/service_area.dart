/// Firestore-backed service-area record — `serviceAreas/{serviceAreaId}`.
/// Deliberately a minimal, standalone future layer — see Phase 4's
/// `Coordinates → ServiceArea → Vendor/Delivery Rules` requirement — not
/// wired into vendor eligibility, delivery-fee, or order-creation logic
/// anywhere yet. Same "define the shape, don't fake usage" posture this
/// codebase already used for `GeocodingService` before Mapbox was wired up
/// (see services/geocoding_service.dart's own architectural-boundary note):
/// nothing in the app queries this collection or excludes a vendor/customer
/// based on it today.
///
/// Represented as a simple circle (center + radius) rather than a polygon —
/// the simplest shape that can answer "is this coordinate inside this
/// service area" (a single distance comparison), and the smallest honest
/// model for a layer with zero consumers yet. A polygon/geofence upgrade is
/// a real future possibility but isn't built here without an actual
/// consumer driving its shape requirements — see models/coordinates.dart's
/// own [Coordinates] type, which this reuses for [center].
class ServiceArea {
  final String id;
  final String nameEn;
  final String nameAr;
  final String? governorateId;
  final String? cityId;
  final double centerLatitude;
  final double centerLongitude;
  final double radiusMeters;
  final bool enabled;
  final int order;

  const ServiceArea({
    required this.id,
    required this.nameEn,
    required this.nameAr,
    this.governorateId,
    this.cityId,
    required this.centerLatitude,
    required this.centerLongitude,
    required this.radiusMeters,
    required this.enabled,
    required this.order,
  });

  factory ServiceArea.fromMap(String id, Map<String, dynamic> map) {
    return ServiceArea(
      id: id,
      nameEn: map['nameEn'] as String,
      nameAr: map['nameAr'] as String,
      governorateId: map['governorateId'] as String?,
      cityId: map['cityId'] as String?,
      centerLatitude: (map['centerLatitude'] as num).toDouble(),
      centerLongitude: (map['centerLongitude'] as num).toDouble(),
      radiusMeters: (map['radiusMeters'] as num).toDouble(),
      enabled: map['enabled'] as bool? ?? true,
      order: map['order'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'nameEn': nameEn,
      'nameAr': nameAr,
      'governorateId': governorateId,
      'cityId': cityId,
      'centerLatitude': centerLatitude,
      'centerLongitude': centerLongitude,
      'radiusMeters': radiusMeters,
      'enabled': enabled,
      'order': order,
    };
  }
}

/// Enabled service areas from [areas], sorted by [ServiceArea.order] — same
/// shape as models/city.dart's `visibleCities`, kept for when a future
/// picker/eligibility check needs it.
List<ServiceArea> visibleServiceAreas(List<ServiceArea> areas) {
  final visible = areas.where((a) => a.enabled).toList()
    ..sort((a, b) => a.order.compareTo(b.order));
  return visible;
}
