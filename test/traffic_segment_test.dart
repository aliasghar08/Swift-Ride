import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:swiftride/services/map_service.dart';

void main() {
  List<LatLng> line(int count) =>
      List.generate(count, (i) => LatLng(33.70 + i * 0.001, 73.05));

  group('TrafficInterval.segment', () {
    test('returns the whole route when there is no traffic data', () {
      final points = line(6);
      final segments = TrafficInterval.segment(points, const []);

      expect(segments, hasLength(1));
      expect(segments.first.points, points);
      expect(segments.first.interval, isNull);
    });

    test('splits the route by speed and keeps segments contiguous', () {
      final points = line(10);
      final segments = TrafficInterval.segment(points, const [
        TrafficInterval(startIndex: 0, endIndex: 4, speed: 'NORMAL'),
        TrafficInterval(startIndex: 4, endIndex: 7, speed: 'SLOW'),
        TrafficInterval(startIndex: 7, endIndex: 9, speed: 'TRAFFIC_JAM'),
      ]);

      expect(segments, hasLength(3));

      expect(segments[0].interval!.isNormal, isTrue);
      expect(segments[1].interval!.isSlow, isTrue);
      expect(segments[2].interval!.isJam, isTrue);

      // Adjacent runs share their boundary point so the drawn line has no gaps.
      expect(segments[0].points.last, segments[1].points.first);
      expect(segments[1].points.last, segments[2].points.first);

      // Every point is covered.
      expect(segments.first.points.first, points.first);
      expect(segments.last.points.last, points.last);
    });

    test('an open-ended interval runs to the end of the route', () {
      final points = line(8);
      final segments = TrafficInterval.segment(points, const [
        TrafficInterval(startIndex: 2, speed: 'SLOW'),
      ]);

      expect(segments, hasLength(1));
      expect(segments.first.points.last, points.last);
    });

    test('clamps indices that fall outside the polyline', () {
      final points = line(5);
      final segments = TrafficInterval.segment(points, const [
        TrafficInterval(startIndex: 0, endIndex: 999, speed: 'NORMAL'),
      ]);

      expect(segments, hasLength(1));
      expect(segments.first.points.last, points.last);
    });

    test('a zero-length interval is skipped without throwing', () {
      final points = line(4);
      final segments = TrafficInterval.segment(points, const [
        TrafficInterval(startIndex: 2, endIndex: 2, speed: 'SLOW'),
      ]);

      // Degenerate run: nothing to draw, so the route falls back to uncoloured
      // rather than the segmenter throwing on an inverted clamp range.
      expect(segments, hasLength(1));
      expect(segments.first.interval, isNull);
      expect(segments.first.points, points);
    });

    test('falls back to the whole route when every interval is out of range', () {
      final points = line(4);
      final segments = TrafficInterval.segment(points, const [
        TrafficInterval(startIndex: 99, speed: 'SLOW'),
      ]);

      // Everything clamped to the last point, so no drawable run survives and
      // the route is drawn uncoloured rather than vanishing.
      expect(segments, hasLength(1));
      expect(segments.first.interval, isNull);
      expect(segments.first.points, points);
    });

    test('returns nothing for a route with fewer than two points', () {
      expect(TrafficInterval.segment(const [LatLng(33.7, 73.0)], const []), isEmpty);
      expect(TrafficInterval.segment(const [], const []), isEmpty);
    });
  });

  group('TrafficInterval.listFrom', () {
    test('parses the backend payload', () {
      final intervals = TrafficInterval.listFrom([
        {'startIndex': 0, 'endIndex': 5, 'speed': 'NORMAL'},
        {'startIndex': 5, 'endIndex': 12, 'speed': 'TRAFFIC_JAM'},
      ]);

      expect(intervals, hasLength(2));
      expect(intervals[1].isJam, isTrue);
      expect(intervals[1].startIndex, 5);
      expect(intervals[1].endIndex, 12);
    });

    test('tolerates a missing or malformed payload', () {
      expect(TrafficInterval.listFrom(null), isEmpty);
      expect(TrafficInterval.listFrom('nonsense'), isEmpty);
      // Missing speed defaults to NORMAL rather than throwing.
      expect(TrafficInterval.listFrom([{'startIndex': 1}]).first.isNormal, isTrue);
    });
  });
}
