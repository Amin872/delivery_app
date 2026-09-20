import 'package:flutter_test/flutter_test.dart';

import 'package:delivery_app/core/errors/app_exception.dart';
import 'package:delivery_app/models/coordinates.dart';
import 'package:delivery_app/services/geocoding_service.dart';

void main() {
  group('UnimplementedGeocodingService', () {
    const service = UnimplementedGeocodingService();

    test('reverseGeocode throws not-implemented rather than returning fake data', () {
      expect(
        service.reverseGeocode(const Coordinates(latitude: 33.5138, longitude: 36.2765)),
        throwsA(isA<AppException>().having((e) => e.code, 'code', 'not-implemented')),
      );
    });

    test('forwardGeocode throws not-implemented rather than returning fake data', () {
      expect(
        service.forwardGeocode('Al-Mazzeh, Damascus'),
        throwsA(isA<AppException>().having((e) => e.code, 'code', 'not-implemented')),
      );
    });
  });
}
