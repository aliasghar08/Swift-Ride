import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/services/map_service.dart';
import 'package:swiftride/services/native_map_service.dart';

class _UnreachableHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    throw const SocketException('Backend unreachable in unit test');
  }
}

void main() {
  setUp(() {
    HttpOverrides.global = _UnreachableHttpOverrides();
  });

  tearDown(() {
    HttpOverrides.global = null;
  });

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

    test('GeoGuard quarantines dirty Google Places city metadata (Sargodha -> Jhang) at (31.26320, 72.35184)', () {
      final service = MapService();
      // Exact mock of dirty Google Place record found at user coordinates in Satellite Town, Jhang
      final dirtyPlace = {
        'displayName': {'text': 'Dr Azra Baloch Clinic'},
        'formattedAddress': 'H, 755, Satellite Block A Town, Sargodha, 40100, Pakistan',
        'location': {'latitude': 31.2633055, 'longitude': 72.3515775},
        'addressComponents': [
          {'longText': 'H', 'types': ['subpremise']},
          {'longText': '755', 'types': ['premise']},
          {'longText': 'Satellite', 'types': ['neighborhood']},
          {'longText': 'Block A', 'types': ['sublocality_level_2']},
          {'longText': 'Town', 'types': ['sublocality_level_1']},
          {'longText': 'Sargodha', 'types': ['locality']},
          {'longText': 'Jhang', 'types': ['administrative_area_level_2']},
          {'longText': 'Punjab', 'types': ['administrative_area_level_1']},
          {'longText': 'Pakistan', 'types': ['country']},
          {'longText': '40100', 'types': ['postal_code']},
        ],
      };

      final formatted = service.buildPreciseAddressFromPlacesPlaceForTest(
        dirtyPlace,
        userLat: 31.26320,
        userLng: 72.35184,
      );

      // Must enforce authoritative city (Jhang) and quarantine Sargodha
      expect(formatted, contains('Jhang'));
      expect(formatted, isNot(contains('Sargodha')));
      expect(formatted, isNot(contains('40100')));
      expect(formatted, isNot(contains('35200')));
      expect(formatted, isNot(contains('Satellite Town Block A Satellite Town')));
      expect(formatted, contains('755'));
    });

    test('GeoGuard distant city quarantine helper replaces distant city (>45km away)', () {
      final enforced = MapService.enforceAuthoritativeCity(31.26320, 72.35184, 'Sargodha');
      expect(enforced, equals('Jhang'));

      final validCity = MapService.enforceAuthoritativeCity(31.26320, 72.35184, 'Jhang');
      expect(validCity, equals('Jhang'));
    });

    test('sanitizeAddressWithGeoGuard strips foreign postal codes and distant cities', () {
      const dirty = ' 35200, Green Belt, Satellite Town Block A Satellite Town, Jhang, 35200, Pakistan';
      final clean = MapService.sanitizeAddressWithGeoGuard(31.26320, 72.35184, dirty);
      expect(clean, isNot(contains('35200')));
      expect(clean, isNot(contains('Pakistan')));
      expect(clean, isNot(contains('Satellite Town Block A Satellite Town')));
      expect(clean, contains('Green Belt'));
      expect(clean, contains('Satellite Town Block A'));
      expect(clean, contains('Jhang'));
    });

    test('extracts spaced rooftop plots (e.g. 772 A, 763 A, 694 A, 4) cleanly with Plot prefix', () {
      final service = MapService();
      final results772 = [
        {
          'types': ['street_address'],
          'geometry': {'location_type': 'ROOFTOP'},
          'formatted_address': '772 A, Usmania Road, Satellite Town Block A, Jhang, Pakistan',
          'address_components': [
            {'long_name': '772 A', 'types': ['street_number']},
            {'long_name': 'Usmania Road', 'types': ['route']},
            {'long_name': 'Satellite Town Block A', 'types': ['sublocality_level_1']},
            {'long_name': 'Jhang', 'types': ['locality']},
          ],
        },
      ];
      final formatted772 = service.buildPrecisePropertyAddressForTest(results772);
      expect(formatted772, equals('Plot 772 A, Usmania Road, Satellite Town Block A, Jhang'));

      final resultsPolice = [
        {
          'types': ['premise'],
          'geometry': {'location_type': 'ROOFTOP'},
          'formatted_address': 'Plot 4, Police Lines, Jhang Sadar, Jhang, Pakistan',
          'address_components': [
            {'long_name': '4', 'types': ['street_number']},
            {'long_name': 'Police Lines', 'types': ['route']},
            {'long_name': 'Jhang Sadar', 'types': ['neighborhood']},
            {'long_name': 'Jhang', 'types': ['locality']},
          ],
        },
      ];
      final formattedPolice = service.buildPrecisePropertyAddressForTest(resultsPolice);
      expect(formattedPolice, equals('Plot 4, Police Lines, Jhang Sadar, Jhang'));
    });

    test('snapToNearestRoad handles network exception non-blocking without throwing', () async {
      final service = MapService();
      final result = await service.snapToNearestRoad(31.26320, 72.35184);
      expect(result, isNull);
    });

    test('snapBreadcrumbsToRoads returns original raw points on network exception', () async {
      final service = MapService();
      final rawPoints = [
        const LatLng(31.26320, 72.35184),
        const LatLng(31.26300, 72.35200),
      ];
      final snapped = await service.snapBreadcrumbsToRoads(rawPoints);
      expect(snapped, equals(rawPoints));
    });

    test('validateAddress returns null non-blocking on network failure or unsupported region', () async {
      final service = MapService();
      final result = await service.validateAddress('Satellite Town, Jhang', regionCode: 'PK');
      expect(result, isNull);
    });
  });
}
