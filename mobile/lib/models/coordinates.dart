/// A plain latitude/longitude pair — the application's own
/// provider-independent geographic value type (see the Location/Maps
/// Architecture audit). Deliberately NOT `geolocator`'s `Position` (a
/// device-GPS reading, carries accuracy/heading/speed/timestamp — stays
/// internal to [LocationService]) and NOT any map SDK's own point type
/// (Google Maps' `LatLng`, or a future Mapbox equivalent). Every
/// provider-independent abstraction that deals with "a place" —
/// `GeocodingService` today, a future map-picker/`RoutingService` — speaks
/// in this type, never in a provider-specific one, so the geocoding and
/// map-display providers stay swappable independently of each other and
/// of `LocationService`'s own device-GPS responsibility.
class Coordinates {
  final double latitude;
  final double longitude;

  const Coordinates({required this.latitude, required this.longitude});

  factory Coordinates.fromMap(Map<String, dynamic> map) {
    return Coordinates(
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {'latitude': latitude, 'longitude': longitude};
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Coordinates && other.latitude == latitude && other.longitude == longitude;
  }

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'Coordinates($latitude, $longitude)';
}
