import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/app_exception.dart';
import '../core/errors/guard.dart';
import '../models/coordinates.dart';
import 'mapbox_geocoding_service.dart';

// Architectural boundary (see the Location/Maps Architecture audit):
//   Coordinates      = application-level geographic value (models/coordinates.dart)
//   GeocodingService = this file — external geocoding abstraction
//   LocationService  = device GPS + existing driver publishing (services/location_service.dart) — unchanged
//   Firestore        = source of truth for our OWN Governorate/City/District IDs
//   Google Maps      = current map renderer (DriverTrackingMap) — unchanged, not part of this file
//   Mapbox           = future GeocodingService implementation (Geocoding v6) — not implemented yet
//
// A GeocodeResult's city/district/region fields are the EXTERNAL PROVIDER's
// own free-text geographic vocabulary — never a governorates/{id},
// cities/{id}, or districts/{id} document id. Matching a result's `city`/
// `district` text against the live GovernorateOption/CityOption/
// DistrictOption lists (the same client-side "fetch small, resolve in
// Dart" pattern core/l10n/enum_labels.dart's cityLabel()/governorateLabel()
// already use) is a separate, later concern — this model must never be
// mistaken for, or written directly into, our own domain hierarchy.

/// A place/address resolved from [coordinates] by an external geocoding
/// provider — see the architectural boundary note above.
class GeocodeResult {
  final Coordinates coordinates;
  final String? formattedAddress;
  final String? country;
  final String? region;
  final String? city;
  final String? district;
  final String? neighborhood;

  const GeocodeResult({
    required this.coordinates,
    this.formattedAddress,
    this.country,
    this.region,
    this.city,
    this.district,
    this.neighborhood,
  });
}

/// A single candidate from a forward-geocoding/place search — same
/// provider-independent geographic vocabulary as [GeocodeResult], plus an
/// optional [name] for a named place/point of interest (not just a bare
/// address).
class PlaceMatch {
  final String? name;
  final Coordinates coordinates;
  final String? formattedAddress;
  final String? country;
  final String? region;
  final String? city;
  final String? district;
  final String? neighborhood;

  const PlaceMatch({
    this.name,
    required this.coordinates,
    this.formattedAddress,
    this.country,
    this.region,
    this.city,
    this.district,
    this.neighborhood,
  });
}

/// Provider-independent external geocoding boundary. The eventual
/// implementation behind this interface will call Mapbox's Geocoding v6
/// API (see [UnimplementedGeocodingService] below for this phase) — no
/// Mapbox package, type, or network call exists anywhere yet. Every call
/// site depends only on this abstract class and the plain
/// [GeocodeResult]/[PlaceMatch] models above; a future
/// `MapboxGeocodingService` is the only file allowed to import a Mapbox
/// package or reference a Mapbox-specific type.
abstract class GeocodingService {
  /// Resolves [coordinates] to the external provider's geographic context,
  /// or null if the provider has no match.
  Future<GeocodeResult?> reverseGeocode(Coordinates coordinates);

  /// Resolves a free-text search [query] (an address or place name) to
  /// zero or more candidate matches.
  Future<List<PlaceMatch>> forwardGeocode(String query);
}

/// Placeholder implementation for this phase — no external geocoding
/// provider is wired up yet (Mapbox integration is a later phase, see the
/// Location/Maps Architecture audit's implementation plan). Deliberately
/// throws `AppException('not-implemented')` rather than returning
/// fabricated geographic data, so a screen that mistakenly starts
/// depending on this before a real implementation exists fails loudly
/// instead of silently showing a wrong address/city to a user.
///
/// No dedicated localized message exists yet for `'not-implemented'`
/// (falls back to `error_messages.dart`'s generic message) — nothing in
/// the UI can trigger this path yet, so a UI-facing string isn't needed
/// until a real screen starts calling this service.
class UnimplementedGeocodingService implements GeocodingService {
  const UnimplementedGeocodingService();

  @override
  Future<GeocodeResult?> reverseGeocode(Coordinates coordinates) {
    return guardFuture(() => throw const AppException('not-implemented'));
  }

  @override
  Future<List<PlaceMatch>> forwardGeocode(String query) {
    return guardFuture(() => throw const AppException('not-implemented'));
  }
}

// Co-located with the service (rather than in a feature's own provider
// file, the pattern locationServiceProvider/firestoreServiceProvider
// follow) since GeocodingService has no feature owner yet — nothing
// consumes it in this phase. This is the one place allowed to construct a
// concrete implementation (DI wiring is inherently the composition root —
// the abstraction above stays Mapbox-free; only this provider and
// mapbox_geocoding_service.dart itself know a MapboxGeocodingService
// exists). Always constructs MapboxGeocodingService, even when
// mapboxPublicToken is empty — MapboxGeocodingService itself detects a
// missing token and throws AppException('missing-token') without ever
// making a network request, so no separate "is it configured" branch is
// needed here. UnimplementedGeocodingService remains available as an
// explicit test double via ProviderScope overrides.
final geocodingServiceProvider = Provider<GeocodingService>((ref) {
  return MapboxGeocodingService(accessToken: mapboxPublicToken);
});
