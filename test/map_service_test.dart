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

    test('returns empty when backend is unreachable instead of falling back to stale data', () async {
      final results = await MapService().searchPlaces('blue area');

      // Verified removal of bundled local gazetteer: when remote backend is uninitialized
      // or returns empty, MapService returns empty rather than substituting hardcoded landmarks.
      expect(results, isEmpty);
    });
  });
}
