import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/services/map_service.dart';
import 'package:swiftride/services/native_map_service.dart';

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

  group('MapService granular plot/premise extraction', () {
    test('extracts street_number, subpremise, premise, and route additively from Geocoding results', () {
      final service = MapService();
      final results = [
        {
          'types': ['street_address', 'premise'],
          'geometry': {'location_type': 'ROOFTOP'},
          'formatted_address': '78G5+48, Satellite Town, Jhang, Pakistan',
          'address_components': [
            {
              'long_name': '145-B',
              'types': ['street_number'],
            },
            {
              'long_name': '4',
              'types': ['subpremise'],
            },
            {
              'long_name': 'Al-Noor Plaza',
              'types': ['premise'],
            },
            {
              'long_name': 'Street 7',
              'types': ['route'],
            },
            {
              'long_name': 'Block Y',
              'types': ['sublocality_level_2'],
            },
            {
              'long_name': 'Satellite Town',
              'types': ['sublocality_level_1'],
            },
            {
              'long_name': 'Jhang',
              'types': ['locality'],
            },
          ],
        },
      ];

      final formatted = service.buildPrecisePropertyAddressForTest(results);
      expect(
        formatted,
        equals('Plot 145-B, Unit 4, Al-Noor Plaza, Street 7, Block Y, Satellite Town, Jhang'),
      );
    });

    test('extracts street_number, premise, and displayName from Places API (New) place object', () {
      final service = MapService();
      final place = {
        'displayName': {'text': 'City Care Hospital'},
        'formattedAddress': 'Satellite Town, Jhang, Pakistan',
        'addressComponents': [
          {
            'longText': '42',
            'types': ['street_number'],
          },
          {
            'longText': 'Medical Complex',
            'types': ['premise'],
          },
          {
            'longText': 'Gojra Road',
            'types': ['route'],
          },
          {
            'longText': 'Satellite Town',
            'types': ['sublocality_level_1'],
          },
          {
            'longText': 'Jhang',
            'types': ['locality'],
          },
        ],
      };

      final formatted = service.buildPreciseAddressFromPlacesPlaceForTest(place);
      expect(
        formatted,
        equals('Plot 42, Medical Complex, City Care Hospital, Gojra Road, Satellite Town, Jhang'),
      );
    });

    test('buildPreciseAddressFromPlacesPlace extracts full police lines landmark without bare city collapse', () {
      final service = MapService();
      final policeLinesPlace = {
        'formattedAddress': '78FH+H6F DSP Patrolling Office, Police Lines, Jhang Sadar Jhang, 35550, Pakistan',
        'displayName': {
          'text': 'DSP Patrolling Office Jhang, Police Lines Jhang, Punjab Pakistan',
        },
        'addressComponents': [
          {'longText': 'DSP Patrolling Office', 'types': ['point_of_interest', 'establishment']},
          {'longText': 'Police Lines', 'types': ['route']},
          {'longText': 'Jhang Sadar', 'types': ['neighborhood', 'political']},
          {'longText': 'Jhang', 'types': ['locality', 'political']},
          {'longText': '35550', 'types': ['postal_code']},
        ],
      };

      final formatted = service.buildPreciseAddressFromPlacesPlaceForTest(policeLinesPlace);
      expect(
        formatted,
        equals('DSP Patrolling Office, Police Lines, Jhang Sadar, Jhang'),
      );
    });

    test('NativeMapService.isGranularAddress distinguishes plot/premise addresses from broad neighborhoods', () {
      expect(NativeMapService.isGranularAddress('Satellite Town, Jhang'), isFalse);
      expect(NativeMapService.isGranularAddress('Mayo Gardens, Lahore'), isFalse);
      expect(NativeMapService.isGranularAddress('78G5+48, Jhang'), isFalse);
      expect(NativeMapService.isGranularAddress('Location (31.2681, 72.3181)'), isFalse);

      expect(NativeMapService.isGranularAddress('Plot 145-B, Street 7, Satellite Town, Jhang'), isTrue);
      expect(NativeMapService.isGranularAddress('Al-Noor Plaza, Gojra Road, Jhang'), isTrue);
      expect(NativeMapService.isGranularAddress('House 12, Block Y, Peoples Colony, Faisalabad'), isTrue);
      expect(NativeMapService.isGranularAddress('Police Lines, Jhang Sadar, Jhang'), isTrue);
      expect(NativeMapService.isGranularAddress('DSP Patrolling Office, Police Lines, Jhang'), isTrue);
      expect(NativeMapService.isGranularAddress('Police Lines, Jhang'), isTrue);
    });
  });
}
