import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:delivery_app/core/location/navigation_launcher.dart';
import 'package:delivery_app/models/coordinates.dart';
import 'package:delivery_app/models/order.dart';

DeliveryOrder _order({double? pickupLat, double? pickupLng, double? dropLat, double? dropLng}) =>
    DeliveryOrder(
      id: 'o',
      customerId: 'c',
      vendorId: 'v',
      items: const [],
      status: OrderStatus.driverAssigned,
      total: 1,
      deliveryAddress: 'addr',
      createdAt: DateTime(2026),
      pickupLatitude: pickupLat,
      pickupLongitude: pickupLng,
      deliveryLatitude: dropLat,
      deliveryLongitude: dropLng,
    );

void main() {
  group('googleMapsDirectionsUri', () {
    test('builds the Google Maps https directions link', () {
      final uri = googleMapsDirectionsUri(const Coordinates(latitude: 33.5138, longitude: 36.2765));

      expect(uri.scheme, 'https');
      expect(uri.host, 'www.google.com');
      expect(uri.path, '/maps/dir/');
      expect(uri.queryParameters, {
        'api': '1',
        'destination': '33.513800,36.276500',
        'travelmode': 'driving',
      });
    });

    test('works for a pickup and a drop-off point taken from an order', () {
      final order = _order(pickupLat: 33.51, pickupLng: 36.27, dropLat: 33.5, dropLng: 36.25);

      expect(googleMapsDirectionsUri(order.pickupCoordinates!).queryParameters['destination'],
          '33.510000,36.270000');
      expect(googleMapsDirectionsUri(order.deliveryCoordinates!).queryParameters['destination'],
          '33.500000,36.250000');
    });

    test('uses "." decimals and keeps negative coordinates', () {
      final uri = googleMapsDirectionsUri(const Coordinates(latitude: -33.8688, longitude: -151.2093));

      expect(uri.queryParameters['destination'], '-33.868800,-151.209300');
      expect(uri.queryParameters['destination'], isNot(contains(' ')));
    });

    test('an order without pins yields no coordinates, so there is nothing to navigate to', () {
      final order = _order();

      expect(order.pickupCoordinates, isNull);
      expect(order.deliveryCoordinates, isNull);
      // Half a pin is still no pin.
      expect(_order(pickupLat: 33.5).pickupCoordinates, isNull);
    });
  });

  group('launchDirections', () {
    const destination = Coordinates(latitude: 33.5, longitude: 36.3);

    test('opens the directions link in an external app', () async {
      Uri? launched;
      LaunchMode? usedMode;
      final ok = await launchDirections(destination, launch: (uri, {mode = LaunchMode.platformDefault}) async {
        launched = uri;
        usedMode = mode;
        return true;
      });

      expect(ok, isTrue);
      expect(launched, googleMapsDirectionsUri(destination));
      expect(usedMode, LaunchMode.externalApplication);
    });

    test('returns false when nothing can open the link', () async {
      final ok = await launchDirections(destination,
          launch: (uri, {mode = LaunchMode.platformDefault}) async => false);

      expect(ok, isFalse);
    });

    test('returns false instead of throwing when launching throws', () async {
      final ok = await launchDirections(destination,
          launch: (uri, {mode = LaunchMode.platformDefault}) async => throw Exception('no handler'));

      expect(ok, isFalse);
    });
  });
}
