import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/core/utils/geohash_util.dart';

void main() {
  group('GeohashUtil Comprehensive Geotagging Tests', () {
    const islamabadLat = 33.6844;
    const islamabadLng = 73.0479;
    const lahoreLat = 31.5204;
    const lahoreLng = 74.3587;
    const karachiLat = 24.8607;
    const karachiLng = 67.0011;

    test('validates geohash strings correctly', () {
      expect(GeohashUtil.isValid('ttgzwhp'), isTrue);
      expect(GeohashUtil.isValid('ezs42'), isTrue);
      expect(GeohashUtil.isValid(''), isFalse);
      expect(GeohashUtil.isValid(null), isFalse);
      expect(GeohashUtil.isValid('invalid!'), isFalse); // contains '!'
      expect(GeohashUtil.isValid('ttgza'), isFalse); // 'a' is not in base32
    });

    test('encodes major Pakistani urban hubs correctly', () {
      expect(GeohashUtil.encode(islamabadLat, islamabadLng, 7), 'ttgzwhp');
      expect(GeohashUtil.encode(lahoreLat, lahoreLng, 7), 'ttsgk44');
      expect(GeohashUtil.encode(karachiLat, karachiLng, 7), 'tkrtktu');
    });

    test('decodes geohashes back to coordinates within error bounds', () {
      final decoded = GeohashUtil.decode('ttgzwhp');
      expect((decoded.latitude - islamabadLat).abs(), lessThanOrEqualTo(decoded.latError));
      expect((decoded.longitude - islamabadLng).abs(), lessThanOrEqualTo(decoded.lngError));

      final bounds = GeohashUtil.bounds('ttgzwhp');
      expect(bounds.contains(islamabadLat, islamabadLng), isTrue);
      expect(bounds.contains(lahoreLat, lahoreLng), isFalse);
    });

    test('computes 8 adjacent neighbor geohashes accurately', () {
      const hash = 'ttgzwhp';
      final n = GeohashUtil.neighbor(hash, 'n');
      final s = GeohashUtil.neighbor(hash, 's');
      final e = GeohashUtil.neighbor(hash, 'e');
      final w = GeohashUtil.neighbor(hash, 'w');

      expect(n.length, hash.length);
      expect(s.length, hash.length);
      expect(e.length, hash.length);
      expect(w.length, hash.length);
      expect(n != hash, isTrue);
      expect(s != hash, isTrue);

      final allNeighbors = GeohashUtil.neighbors(hash);
      expect(allNeighbors.length, 8);
      expect(allNeighbors.containsKey('north'), isTrue);
      expect(allNeighbors.containsKey('south'), isTrue);
      expect(allNeighbors.containsKey('east'), isTrue);
      expect(allNeighbors.containsKey('west'), isTrue);
      expect(allNeighbors.containsKey('northEast'), isTrue);
      expect(allNeighbors.containsKey('northWest'), isTrue);
      expect(allNeighbors.containsKey('southEast'), isTrue);
      expect(allNeighbors.containsKey('southWest'), isTrue);

      // Verify that every neighbor is unique and valid
      final set = allNeighbors.values.toSet();
      expect(set.length, 8);
      for (final neighborHash in set) {
        expect(GeohashUtil.isValid(neighborHash), isTrue);
      }
    });

    test('computes Firestore geohash query bounds matching GeoFire specification', () {
      // 5km query bounds in Islamabad
      final isbBounds = GeohashUtil.queryBounds(islamabadLat, islamabadLng, 5.0);
      expect(isbBounds.isNotEmpty, isTrue);
      expect(isbBounds.length, lessThanOrEqualTo(9));
      expect(isbBounds.map((b) => [b.start, b.end]).toList(), [
        ['ttgzs', 'ttgz~'],
        ['ttgzh', 'ttgzs'],
      ]);

      // 5km query bounds in Lahore
      final lhrBounds = GeohashUtil.queryBounds(lahoreLat, lahoreLng, 5.0);
      expect(lhrBounds.map((b) => [b.start, b.end]).toList(), [
        ['ttsgh', 'ttsgs'],
        ['ttsg0', 'ttsg8'],
        ['ttsgs', 'ttsg~'],
        ['ttsg8', 'ttsgh'],
      ]);

      // 5km query bounds in Karachi
      final khiBounds = GeohashUtil.queryBounds(karachiLat, karachiLng, 5.0);
      expect(khiBounds.map((b) => [b.start, b.end]).toList(), [
        ['tkrth', 'tkrts'],
        ['tkrt0', 'tkrt8'],
        ['tkrts', 'tkrt~'],
        ['tkrt8', 'tkrth'],
      ]);
    });

    test('computes distance and bearing correctly', () {
      // Distance between Islamabad and Lahore is approx 270-280 km
      final distKm = GeohashUtil.distanceKm(islamabadLat, islamabadLng, lahoreLat, lahoreLng);
      expect(distKm, greaterThan(260.0));
      expect(distKm, lessThan(290.0));

      final distMeters = GeohashUtil.distanceMeters(islamabadLat, islamabadLng, lahoreLat, lahoreLng);
      expect(distMeters, closeTo(distKm * 1000.0, 0.01));

      // Heading from Islamabad south-east to Lahore (~150-160 degrees)
      final brng = GeohashUtil.bearing(islamabadLat, islamabadLng, lahoreLat, lahoreLng);
      expect(brng, greaterThan(140.0));
      expect(brng, lessThan(170.0));
    });
  });
}
