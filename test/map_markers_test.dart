import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/services/native_map_service.dart';
import 'package:swiftride/presentation/common/map_marker_icons.dart';
import 'package:swiftride/presentation/common/map_markers.dart';

void main() {
  group('Map marker glyphs', () {
    testWidgets('renders the custom vector glyphs', (tester) async {
      // Picture.toImage needs a real engine frame, so run it outside the fake
      // async zone.
      await tester.runAsync(() async {
        await MapMarkerIcons.ensureLoaded();
      });

      expect(MapMarkerIcons.isLoaded, isTrue);
      expect(MapMarkerIcons.pickup, isNotNull);
      expect(MapMarkerIcons.dropoff, isNotNull);
      expect(MapMarkerIcons.car, isNotNull);
      expect(MapMarkerIcons.puck, isNotNull);
    });
  });

  group('MapMarkers', () {
    test('pickup and dropoff support distinct ids', () {
      final preview = MapMarkers.pickup(const LatLng(33.70, 73.05));
      final confirmed = MapMarkers.pickup(
        const LatLng(33.70, 73.05),
        id: 'ride_pickup',
      );

      // These used to share the id 'pickup', so the search-preview pin and the
      // confirmed-trip pin collided in the same Marker set.
      expect(preview.markerId.value, 'pickup');
      expect(confirmed.markerId.value, 'ride_pickup');
      expect(preview.markerId, isNot(equals(confirmed.markerId)));

      expect(MapMarkers.dropoff(const LatLng(33.7, 73.0), id: 'ride_dropoff')
          .markerId
          .value, 'ride_dropoff');
    });

    test('driver marker is flat and rotated to the heading', () {
      final marker = MapMarkers.driver(
        driverId: 'driver_1',
        pos: const LatLng(33.70, 73.05),
        heading: 137.5,
      );

      expect(marker.markerId.value, 'driver_driver_1');
      expect(marker.rotation, 137.5);
      expect(marker.flat, isTrue);
      expect(marker.zIndexInt, 2);
    });

    test('location puck carries rotation and sits above other markers', () {
      final puck = MapMarkers.locationPuck(
        pos: const LatLng(33.70, 73.05),
        heading: 42,
      );

      expect(puck.rotation, 42);
      expect(puck.flat, isTrue);
      expect(puck.zIndexInt, 3);
    });
  });
}
