import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/services/coordinate_parser.dart';

void main() {
  group('CoordinateParser', () {
    test('1. Standard decimal (comma separated)', () {
      final p1 = CoordinateParser.tryParse('31.2634, 72.3517');
      expect(p1, isNotNull);
      expect(p1!.latitude, closeTo(31.2634, 0.0001));
      expect(p1.longitude, closeTo(72.3517, 0.0001));

      final p2 = CoordinateParser.tryParse('31.2634,72.3517');
      expect(p2, isNotNull);
      expect(p2!.latitude, closeTo(31.2634, 0.0001));
      expect(p2.longitude, closeTo(72.3517, 0.0001));

      final p3 = CoordinateParser.tryParse('31.2634, 72.3517, 15z');
      expect(p3, isNotNull);
      expect(p3!.latitude, closeTo(31.2634, 0.0001));
      expect(p3.longitude, closeTo(72.3517, 0.0001));

      final p4 = CoordinateParser.tryParse('31.263400, 72.351700');
      expect(p4, isNotNull);
      expect(p4!.latitude, closeTo(31.2634, 0.0001));
      expect(p4.longitude, closeTo(72.3517, 0.0001));
    });

    test('1b. Standard decimal (space separated)', () {
      final p = CoordinateParser.tryParse('31.2634 72.3517');
      expect(p, isNotNull);
      expect(p!.latitude, closeTo(31.2634, 0.0001));
      expect(p.longitude, closeTo(72.3517, 0.0001));
    });

    test('2. Signed decimal', () {
      final p = CoordinateParser.tryParse('-31.2634, 72.3517');
      expect(p, isNotNull);
      expect(p!.latitude, closeTo(-31.2634, 0.0001));
      expect(p.longitude, closeTo(72.3517, 0.0001));
    });

    test('3. Google URL fragment', () {
      final p = CoordinateParser.tryParse('@31.2634,72.3517,15z');
      expect(p, isNotNull);
      expect(p!.latitude, closeTo(31.2634, 0.0001));
      expect(p.longitude, closeTo(72.3517, 0.0001));
    });

    test('4. Full Google Maps URL', () {
      final p1 = CoordinateParser.tryParse(
        'https://maps.google.com/?q=31.2634,72.3517',
      );
      expect(p1, isNotNull);
      expect(p1!.latitude, closeTo(31.2634, 0.0001));
      expect(p1.longitude, closeTo(72.3517, 0.0001));

      final p2 = CoordinateParser.tryParse(
        'https://www.google.com/maps/@31.2634,72.3517,15z',
      );
      expect(p2, isNotNull);
      expect(p2!.latitude, closeTo(31.2634, 0.0001));
      expect(p2.longitude, closeTo(72.3517, 0.0001));
    });

    test('5. DMS format', () {
      final p1 = CoordinateParser.tryParse('31°15\'48.2"N 72°21\'06.1"E');
      expect(p1, isNotNull);
      expect(p1!.latitude, closeTo(31.2634, 0.001));
      expect(p1.longitude, closeTo(72.3517, 0.001));

      final p2 = CoordinateParser.tryParse('31°15\'48.2"N, 72°21\'06.1"E');
      expect(p2, isNotNull);
      expect(p2!.latitude, closeTo(31.2634, 0.001));
      expect(p2.longitude, closeTo(72.3517, 0.001));
    });

    test('6. Google Maps Plus Codes / Open Location Codes', () {
      // 6a. Compound Plus Code with city: "78G5+48 Jhang, Pakistan"
      final p1 = CoordinateParser.tryParse('78G5+48 Jhang, Pakistan');
      expect(p1, isNotNull);
      expect(p1!.latitude, closeTo(31.2753, 0.01));
      expect(p1.longitude, closeTo(72.3083, 0.01));
      expect(p1.originalCode, equals('78G5+48'));

      // 6b. Short Plus Code with comma: "78G5+48, Jhang"
      final p2 = CoordinateParser.tryParse('78G5+48, Jhang');
      expect(p2, isNotNull);
      expect(p2!.latitude, closeTo(31.2753, 0.01));
      expect(p2.longitude, closeTo(72.3083, 0.01));

      // 6c. Short Plus Code with reference coordinates
      final p3 = CoordinateParser.tryParse(
        '78G5+48',
        referenceLat: 31.2785,
        referenceLng: 72.3317,
      );
      expect(p3, isNotNull);
      expect(p3!.latitude, closeTo(31.2753, 0.01));
      expect(p3.longitude, closeTo(72.3083, 0.01));

      // 6d. Full global Plus Code: "8J3J78G5+48"
      final p4 = CoordinateParser.tryParse('8J3J78G5+48');
      expect(p4, isNotNull);
      expect(p4!.latitude, closeTo(31.2753, 0.01));
      expect(p4.longitude, closeTo(72.3083, 0.01));

      // 6e. Dropped pin text from Google Maps: "Dropped pin near 78G5+48 Jhang, Pakistan"
      final p5 = CoordinateParser.tryParse(
        'Dropped pin near 78G5+48 Jhang, Pakistan',
      );
      expect(p5, isNotNull);
      expect(p5!.latitude, closeTo(31.2753, 0.01));
      expect(p5.longitude, closeTo(72.3083, 0.01));

      // 6f. Google Maps URL with Plus Code: "https://maps.google.com/?q=78G5%2B48+Jhang"
      final p6 = CoordinateParser.tryParse(
        'https://maps.google.com/?q=78G5%2B48+Jhang',
      );
      expect(p6, isNotNull);
      expect(p6!.latitude, closeTo(31.2753, 0.01));
      expect(p6.longitude, closeTo(72.3083, 0.01));

      // 6g. Dropped pin text with raw coordinates: "Dropped pin\nnear 31.2785, 72.3317"
      final p7 = CoordinateParser.tryParse(
        'Dropped pin\nnear 31.2785, 72.3317',
      );
      expect(p7, isNotNull);
      expect(p7!.latitude, closeTo(31.2785, 0.0001));
      expect(p7.longitude, closeTo(72.3317, 0.0001));

      // 6h. User query: "7972+7PF Jhang, Pakistan"
      final p8 = CoordinateParser.tryParse('7972+7PF Jhang, Pakistan');
      expect(p8, isNotNull);
      expect(p8!.latitude, closeTo(31.2631, 0.005));
      expect(p8.longitude, closeTo(72.3518, 0.005));
      expect(p8.label, contains('7972+7PF'));

      // 6i. 11-digit building-entrance subgrid round-trip accuracy (~2.8m x 3.5m)
      const buildingLat = 31.263185;
      const buildingLng = 72.351812;
      final encoded11 = CoordinateParser.encodePlusCode(
        buildingLat,
        buildingLng,
        codeLength: 11,
      );
      expect(encoded11.length, equals(12)); // 11 digits + '+'
      final decoded11 = CoordinateParser.tryParse(encoded11);
      expect(decoded11, isNotNull);
      expect(decoded11!.latitude, closeTo(buildingLat, 0.00003));
      expect(decoded11.longitude, closeTo(buildingLng, 0.00004));

      // 6j. recoverNearest across 1-degree grid boundary (e.g. code at 30.999 near ref 31.001)
      final nearBoundaryCode = CoordinateParser.encodePlusCode(30.9992, 72.3181, codeLength: 11);
      final shortBoundaryCode = nearBoundaryCode.substring(4); // strip 4-char prefix
      final recovered = CoordinateParser.tryParse(
        shortBoundaryCode,
        referenceLat: 31.0010,
        referenceLng: 72.3181,
      );
      expect(recovered, isNotNull);
      expect(recovered!.latitude, closeTo(30.9992, 0.0001));
      expect(recovered.longitude, closeTo(72.3181, 0.0001));
    });

    test('Validation and non-coordinate inputs return null', () {
      expect(CoordinateParser.tryParse('72.35'), isNull);
      expect(CoordinateParser.tryParse('Lahore Fort'), isNull);
      expect(CoordinateParser.tryParse('Street 5, House 12'), isNull);
      expect(CoordinateParser.tryParse(''), isNull);
      expect(CoordinateParser.tryParse('120.5, 45.2'), isNull); // Lat > 90
      expect(CoordinateParser.tryParse('45.2, 200.5'), isNull); // Lng > 180
    });
  });
}
