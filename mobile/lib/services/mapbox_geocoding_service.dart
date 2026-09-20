import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/errors/app_exception.dart';
import '../core/errors/guard.dart';
import '../models/coordinates.dart';
import 'geocoding_service.dart';

/// Build-time Mapbox public (`pk.*`) access token — see
/// [MapboxGeocodingService] and the Location/Maps Architecture audit's API
/// key/secret section. Supplied via
/// `flutter run --dart-define=MAPBOX_PUBLIC_TOKEN=pk.xxx` (or
/// `--dart-define-from-file`) at build time — never committed to source
/// control. Empty when not supplied; [MapboxGeocodingService] treats an
/// empty token as "not configured" and throws `AppException('missing-token')`
/// without ever making a network request.
///
/// Must only ever be a PUBLIC token (Mapbox's own `pk.*` scoping,
/// restricted by URL/usage on the Mapbox account dashboard) — a secret
/// (`sk.*`) token must never be embedded in a client app. Any future
/// Mapbox capability that genuinely needs a secret token belongs behind a
/// Cloud Function instead (not built in this phase — see the audit).
const String mapboxPublicToken = String.fromEnvironment('MAPBOX_PUBLIC_TOKEN');

const _requestTimeout = Duration(seconds: 10);

/// Mapbox Geocoding v6 (`/search/geocode/v6/reverse`, `/search/geocode/v6/forward`)
/// implementation of [GeocodingService] — see geocoding_service.dart's own
/// architectural-boundary note. This is the only file in the app allowed
/// to know about Mapbox's request/response shape; every call site depends
/// only on [GeocodingService]/[GeocodeResult]/[PlaceMatch]/[Coordinates].
///
/// Requests are "temporary" geocoding — the `permanent` query parameter is
/// deliberately omitted (never set to `true`), since no result is stored
/// anywhere yet (no Firestore write, no persistent cache — see the audit's
/// caching section).
///
/// No Firestore dependency, no Governorate/City/District dependency:
/// reconciling a result's free-text city/district against our own
/// `cities/{id}`/`districts/{id}` is a separate, later concern (see
/// geocoding_service.dart).
class MapboxGeocodingService implements GeocodingService {
  MapboxGeocodingService({http.Client? client, required String? accessToken})
      : _client = client ?? http.Client(),
        _accessToken = accessToken;

  final http.Client _client;
  final String? _accessToken;

  static const _host = 'api.mapbox.com';

  @override
  Future<GeocodeResult?> reverseGeocode(Coordinates coordinates) {
    return guardFuture(() async {
      final token = _requireToken();
      _requireValidCoordinates(coordinates);

      final uri = Uri.https(_host, '/search/geocode/v6/reverse', {
        'longitude': coordinates.longitude.toString(),
        'latitude': coordinates.latitude.toString(),
        'access_token': token,
      });

      final body = await _get(uri);
      final features = _featuresFrom(body);
      if (features.isEmpty) return null;
      return _toGeocodeResult(_asMap(features.first));
    });
  }

  @override
  Future<List<PlaceMatch>> forwardGeocode(String query) {
    return guardFuture(() async {
      final token = _requireToken();
      if (query.trim().isEmpty) return const [];

      final uri = Uri.https(_host, '/search/geocode/v6/forward', {
        'q': query,
        'access_token': token,
      });

      final body = await _get(uri);
      final features = _featuresFrom(body);
      return features.map((feature) => _toPlaceMatch(_asMap(feature))).toList();
    });
  }

  String _requireToken() {
    final token = _accessToken;
    if (token == null || token.isEmpty) {
      throw const AppException('missing-token');
    }
    return token;
  }

  void _requireValidCoordinates(Coordinates coordinates) {
    final validLatitude = coordinates.latitude >= -90 && coordinates.latitude <= 90;
    final validLongitude = coordinates.longitude >= -180 && coordinates.longitude <= 180;
    if (!validLatitude || !validLongitude) {
      throw const AppException('invalid-coordinates');
    }
  }

  Future<Map<String, dynamic>> _get(Uri uri) async {
    final http.Response response;
    try {
      response = await _client.get(uri).timeout(_requestTimeout);
    } on TimeoutException {
      throw const AppException('network-error');
    } catch (_) {
      // Any other transport-level failure (SocketException, http's own
      // ClientException, DNS failure, ...) — normalized the same way,
      // never leaked as a raw platform/package exception to callers.
      throw const AppException('network-error');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const AppException('geocoding-failed');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const AppException('geocoding-failed');
    }

    if (decoded is! Map<String, dynamic>) {
      throw const AppException('geocoding-failed');
    }
    return decoded;
  }

  List<dynamic> _featuresFrom(Map<String, dynamic> body) {
    final features = body['features'];
    return features is List ? features : const [];
  }

  GeocodeResult _toGeocodeResult(Map<String, dynamic> feature) {
    final properties = _asMap(feature['properties']);
    final context = _asMap(properties['context']);
    return GeocodeResult(
      coordinates: _coordinatesFrom(feature),
      formattedAddress: _stringField(properties, 'full_address') ??
          _stringField(properties, 'place_formatted') ??
          _stringField(properties, 'name'),
      country: _contextName(context, 'country'),
      region: _contextName(context, 'region'),
      // Mapbox's "place" feature type is the closest match to a city/town.
      city: _contextName(context, 'place'),
      district: _contextName(context, 'district'),
      // "locality" is a Mapbox feature type our GeocodeResult has no
      // dedicated field for — folded into neighborhood as a fallback only
      // when the more specific neighborhood tag isn't present.
      neighborhood: _contextName(context, 'neighborhood') ?? _contextName(context, 'locality'),
    );
  }

  PlaceMatch _toPlaceMatch(Map<String, dynamic> feature) {
    final properties = _asMap(feature['properties']);
    final context = _asMap(properties['context']);
    return PlaceMatch(
      name: _stringField(properties, 'name'),
      coordinates: _coordinatesFrom(feature),
      formattedAddress: _stringField(properties, 'full_address') ??
          _stringField(properties, 'place_formatted'),
      country: _contextName(context, 'country'),
      region: _contextName(context, 'region'),
      city: _contextName(context, 'place'),
      district: _contextName(context, 'district'),
      neighborhood: _contextName(context, 'neighborhood') ?? _contextName(context, 'locality'),
    );
  }

  Coordinates _coordinatesFrom(Map<String, dynamic> feature) {
    final geometry = _asMap(feature['geometry']);
    final coords = geometry['coordinates'];
    if (coords is! List || coords.length < 2) {
      throw const AppException('geocoding-failed');
    }
    final longitude = coords[0];
    final latitude = coords[1];
    if (longitude is! num || latitude is! num) {
      throw const AppException('geocoding-failed');
    }
    return Coordinates(latitude: latitude.toDouble(), longitude: longitude.toDouble());
  }

  Map<String, dynamic> _asMap(Object? value) {
    return value is Map<String, dynamic> ? value : const {};
  }

  String? _stringField(Map<String, dynamic> map, String key) {
    final value = map[key];
    return value is String && value.isNotEmpty ? value : null;
  }

  String? _contextName(Map<String, dynamic> context, String key) {
    final entry = context[key];
    if (entry is! Map<String, dynamic>) return null;
    return _stringField(entry, 'name');
  }
}
