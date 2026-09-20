import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';

import 'package:delivery_app/core/errors/app_exception.dart';
import 'package:delivery_app/models/coordinates.dart';
import 'package:delivery_app/services/mapbox_geocoding_service.dart';

// http.Client is a plain abstract class (unlike cloud_firestore's sealed
// Query/DocumentReference), so it's fine to mocktail-mock directly — same
// reasoning already documented for MockFirebaseAuth in auth_service_test.dart.
// This test file never imports cloud_firestore/fake_cloud_firestore at
// all, since MapboxGeocodingService has no Firestore dependency to begin
// with — there is nothing here that could touch Firestore.
class MockHttpClient extends Mock implements http.Client {}

const _reverseFeature = {
  'type': 'Feature',
  'geometry': {
    'type': 'Point',
    'coordinates': [36.2765, 33.5138], // [longitude, latitude] — GeoJSON order
  },
  'properties': {
    'name': 'Al-Mazzeh',
    'full_address': 'Al-Mazzeh, Damascus, Syria',
    'place_formatted': 'Damascus, Syria',
    'context': {
      'country': {'name': 'Syria'},
      'region': {'name': 'Damascus Governorate'},
      'place': {'name': 'Damascus'},
      'district': {'name': 'Al-Mazzeh District'},
      'neighborhood': {'name': 'Al-Mazzeh'},
    },
  },
};

String _featureCollectionBody(List<Map<String, dynamic>> features) {
  return '{"type": "FeatureCollection", "features": ${_encodeFeatures(features)}}';
}

String _encodeFeatures(List<Map<String, dynamic>> features) {
  // Hand-built rather than dart:convert's jsonEncode, to keep this fixture
  // builder trivially readable — features never contain anything but
  // strings/numbers/nested maps/lists here.
  String encode(Object? value) {
    if (value is Map) {
      return '{${value.entries.map((e) => '"${e.key}": ${encode(e.value)}').join(', ')}}';
    }
    if (value is List) {
      return '[${value.map(encode).join(', ')}]';
    }
    if (value is String) return '"${value.replaceAll('"', '\\"')}"';
    return '$value';
  }

  return encode(features);
}

void main() {
  setUpAll(() {
    registerFallbackValue(Uri.parse('https://example.com'));
  });

  late MockHttpClient client;

  setUp(() {
    client = MockHttpClient();
  });

  group('missing token', () {
    test('reverseGeocode throws missing-token without making a network call', () async {
      final service = MapboxGeocodingService(client: client, accessToken: '');

      await expectLater(
        service.reverseGeocode(const Coordinates(latitude: 33.5138, longitude: 36.2765)),
        throwsA(isA<AppException>().having((e) => e.code, 'code', 'missing-token')),
      );
      verifyNever(() => client.get(any()));
    });

    test('forwardGeocode throws missing-token without making a network call', () async {
      final service = MapboxGeocodingService(client: client, accessToken: null);

      await expectLater(
        service.forwardGeocode('Al-Mazzeh'),
        throwsA(isA<AppException>().having((e) => e.code, 'code', 'missing-token')),
      );
      verifyNever(() => client.get(any()));
    });
  });

  group('invalid coordinates', () {
    test('reverseGeocode throws invalid-coordinates for an out-of-range latitude', () async {
      final service = MapboxGeocodingService(client: client, accessToken: 'pk.test');

      await expectLater(
        service.reverseGeocode(const Coordinates(latitude: 120, longitude: 36.2765)),
        throwsA(isA<AppException>().having((e) => e.code, 'code', 'invalid-coordinates')),
      );
      verifyNever(() => client.get(any()));
    });
  });

  group('reverse geocode', () {
    test('success — maps provider fields into GeocodeResult, including coordinate order', () async {
      when(() => client.get(any())).thenAnswer(
        (_) async => http.Response(_featureCollectionBody([_reverseFeature]), 200),
      );
      final service = MapboxGeocodingService(client: client, accessToken: 'pk.test');

      final result = await service
          .reverseGeocode(const Coordinates(latitude: 33.5138, longitude: 36.2765));

      expect(result, isNotNull);
      expect(result!.coordinates, const Coordinates(latitude: 33.5138, longitude: 36.2765));
      expect(result.formattedAddress, 'Al-Mazzeh, Damascus, Syria');
      expect(result.country, 'Syria');
      expect(result.region, 'Damascus Governorate');
      expect(result.city, 'Damascus');
      expect(result.district, 'Al-Mazzeh District');
      expect(result.neighborhood, 'Al-Mazzeh');
    });

    test('sends the reverse endpoint with longitude/latitude/access_token', () async {
      when(() => client.get(any())).thenAnswer(
        (_) async => http.Response(_featureCollectionBody([_reverseFeature]), 200),
      );
      final service = MapboxGeocodingService(client: client, accessToken: 'pk.test');

      await service.reverseGeocode(const Coordinates(latitude: 33.5138, longitude: 36.2765));

      final captured = verify(() => client.get(captureAny())).captured;
      final uri = captured.single as Uri;
      expect(uri.host, 'api.mapbox.com');
      expect(uri.path, '/search/geocode/v6/reverse');
      expect(uri.queryParameters['longitude'], '36.2765');
      expect(uri.queryParameters['latitude'], '33.5138');
      expect(uri.queryParameters['access_token'], 'pk.test');
      // Temporary geocoding by default — permanent must never be sent as true.
      expect(uri.queryParameters['permanent'], isNot('true'));
    });

    test('empty results resolve to null, not an error', () async {
      when(() => client.get(any())).thenAnswer(
        (_) async => http.Response(_featureCollectionBody(const []), 200),
      );
      final service = MapboxGeocodingService(client: client, accessToken: 'pk.test');

      final result = await service
          .reverseGeocode(const Coordinates(latitude: 33.5138, longitude: 36.2765));

      expect(result, isNull);
    });
  });

  group('forward geocode', () {
    test('success — maps provider fields into a list of PlaceMatch', () async {
      when(() => client.get(any())).thenAnswer(
        (_) async => http.Response(_featureCollectionBody([_reverseFeature]), 200),
      );
      final service = MapboxGeocodingService(client: client, accessToken: 'pk.test');

      final results = await service.forwardGeocode('Al-Mazzeh, Damascus');

      expect(results, hasLength(1));
      expect(results.single.name, 'Al-Mazzeh');
      expect(results.single.coordinates, const Coordinates(latitude: 33.5138, longitude: 36.2765));
      expect(results.single.city, 'Damascus');
      expect(results.single.district, 'Al-Mazzeh District');
    });

    test('sends the forward endpoint with q/access_token', () async {
      when(() => client.get(any())).thenAnswer(
        (_) async => http.Response(_featureCollectionBody([_reverseFeature]), 200),
      );
      final service = MapboxGeocodingService(client: client, accessToken: 'pk.test');

      await service.forwardGeocode('Al-Mazzeh, Damascus');

      final captured = verify(() => client.get(captureAny())).captured;
      final uri = captured.single as Uri;
      expect(uri.path, '/search/geocode/v6/forward');
      expect(uri.queryParameters['q'], 'Al-Mazzeh, Damascus');
      expect(uri.queryParameters['access_token'], 'pk.test');
    });

    test('empty results resolve to an empty list, not an error', () async {
      when(() => client.get(any())).thenAnswer(
        (_) async => http.Response(_featureCollectionBody(const []), 200),
      );
      final service = MapboxGeocodingService(client: client, accessToken: 'pk.test');

      final results = await service.forwardGeocode('nowhere at all');

      expect(results, isEmpty);
    });
  });

  group('HTTP/parsing failures', () {
    test('a non-2xx HTTP status throws geocoding-failed', () async {
      when(() => client.get(any())).thenAnswer((_) async => http.Response('{}', 500));
      final service = MapboxGeocodingService(client: client, accessToken: 'pk.test');

      await expectLater(
        service.forwardGeocode('Al-Mazzeh'),
        throwsA(isA<AppException>().having((e) => e.code, 'code', 'geocoding-failed')),
      );
    });

    test('malformed JSON throws geocoding-failed, not a raw FormatException', () async {
      when(() => client.get(any())).thenAnswer((_) async => http.Response('{not valid json', 200));
      final service = MapboxGeocodingService(client: client, accessToken: 'pk.test');

      await expectLater(
        service.forwardGeocode('Al-Mazzeh'),
        throwsA(isA<AppException>().having((e) => e.code, 'code', 'geocoding-failed')),
      );
    });

    test('a response with no coordinates on a feature throws geocoding-failed', () async {
      final malformedFeature = Map<String, dynamic>.from(_reverseFeature)
        ..['geometry'] = {'type': 'Point', 'coordinates': <double>[]};
      when(() => client.get(any())).thenAnswer(
        (_) async => http.Response(_featureCollectionBody([malformedFeature]), 200),
      );
      final service = MapboxGeocodingService(client: client, accessToken: 'pk.test');

      await expectLater(
        service.reverseGeocode(const Coordinates(latitude: 33.5138, longitude: 36.2765)),
        throwsA(isA<AppException>().having((e) => e.code, 'code', 'geocoding-failed')),
      );
    });
  });

  group('network failures', () {
    test('a timeout throws network-error, not a raw TimeoutException', () async {
      when(() => client.get(any())).thenThrow(TimeoutException('deadline exceeded'));
      final service = MapboxGeocodingService(client: client, accessToken: 'pk.test');

      await expectLater(
        service.forwardGeocode('Al-Mazzeh'),
        throwsA(isA<AppException>().having((e) => e.code, 'code', 'network-error')),
      );
    });

    test('a generic transport failure throws network-error, not a raw exception', () async {
      when(() => client.get(any())).thenThrow(Exception('connection reset'));
      final service = MapboxGeocodingService(client: client, accessToken: 'pk.test');

      await expectLater(
        service.forwardGeocode('Al-Mazzeh'),
        throwsA(isA<AppException>().having((e) => e.code, 'code', 'network-error')),
      );
    });
  });
}
