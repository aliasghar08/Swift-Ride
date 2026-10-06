import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:swiftride/services/map_service.dart';

void main() {
  group('MapService.searchPlaces', () {
    test('never invents a destination for an unmatched query', () async {
      final results = await MapService().searchPlaces('zzzz-no-such-place-zzzz');

      // Regression guard: this used to return a fabricated
      // "Custom Destination, Islamabad" pin placed at an arbitrary offset from
      // the map centre, so a rider could be sent somewhere that does not exist.
      expect(results, isEmpty);
    });

    test('still matches the bundled local gazetteer with real coordinates', () async {
      final results = await MapService().searchPlaces('blue area');

      expect(results, isNotEmpty);
      // Gazetteer entries carry real coordinates; remote predictions resolve
      // theirs later via getPlaceDetails.
      expect(results.first.coordinates, isNotNull);
      expect(results.first.placeId, isNotEmpty);
    });
  });

  group('MapService.estimateStraightLineRoute', () {
    test('is explicitly flagged as an estimate and keeps both endpoints', () {
      final route = MapService().estimateStraightLineRoute(
        const LatLng(33.70, 73.05),
        const LatLng(33.56, 72.85),
      );

      // The route is a straight line between two real points — never the old
      // invented bend points that merely looked like a road.
      expect(route.isEstimated, isTrue);
      expect(route.polylinePoints.length, 2);
      expect(route.polylinePoints.first, const LatLng(33.70, 73.05));
      expect(route.polylinePoints.last, const LatLng(33.56, 72.85));
      expect(route.distanceKm, greaterThan(0));
      expect(route.durationMin, greaterThan(0));
    });
  });
}
