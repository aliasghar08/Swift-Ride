import 'package:flutter_test/flutter_test.dart';
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

    test('parses Plus Code and prepends high precision pinned location suggestion', () async {
      final results = await MapService().searchPlaces('78G5+48 Jhang, Pakistan');

      expect(results, isNotEmpty);
      final first = results.first;
      expect(first.placeId, startsWith('pinned:'));
      expect(first.mainText, contains('78G5+48'));
      expect(first.secondaryText, contains('Coordinates:'));
      expect(first.coordinates, isNotNull);
      expect(first.coordinates!.latitude, closeTo(31.25, 0.1));
      expect(first.coordinates!.longitude, closeTo(72.32, 0.1));
    });

    test('reverseGeocode returns formatted location string without throwing', () async {
      final address = await MapService().reverseGeocode(31.2681, 72.3181);
      expect(address, isNotEmpty);
    });
  });
}
