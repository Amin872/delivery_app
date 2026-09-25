import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:delivery_app/features/customer/widgets/driver_tracking_map.dart';

void main() {
  const driver = LatLng(33.52, 36.29);
  const dropOff = LatLng(33.50, 36.25);

  group('trackingMarkers', () {
    test('shows the driver and the drop-off when the order has a drop-off pin', () {
      final markers = trackingMarkers(driver, dropOff, destinationTitle: 'Drop-off');

      final byId = {for (final m in markers) m.markerId.value: m};
      expect(byId.keys, unorderedEquals(['driver', 'drop_off']));
      expect(byId['driver']!.position, driver);
      expect(byId['drop_off']!.position, dropOff);
      expect(byId['drop_off']!.infoWindow.title, 'Drop-off');
    });

    test('shows only the driver when there is no drop-off pin', () {
      final markers = trackingMarkers(driver, null);

      expect(markers.map((m) => m.markerId.value), ['driver']);
    });
  });

  group('trackingBounds', () {
    test('contains both points regardless of argument order', () {
      for (final bounds in [trackingBounds(driver, dropOff), trackingBounds(dropOff, driver)]) {
        expect(bounds.southwest, const LatLng(33.50, 36.25));
        expect(bounds.northeast, const LatLng(33.52, 36.29));
        expect(bounds.contains(driver), isTrue);
        expect(bounds.contains(dropOff), isTrue);
      }
    });

    test('handles negative coordinates', () {
      final bounds = trackingBounds(const LatLng(-10, -20), const LatLng(5, 15));

      expect(bounds.southwest, const LatLng(-10, -20));
      expect(bounds.northeast, const LatLng(5, 15));
    });
  });
}
