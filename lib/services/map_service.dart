import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:swiftride/services/location_service_io.dart';

import '../core/utils/distance_calculator.dart';
import 'polyline_service.dart';
import 'admin_service.dart';

class PlaceSuggestion {
  final String placeId;
  final String mainText;
  final String secondaryText;
  final LatLng? coordinates;

  const PlaceSuggestion({
    required this.placeId,
    required this.mainText,
    required this.secondaryText,
    this.coordinates,
  });
}

class TrafficInterval {
  final int startIndex;
  final int? endIndex;
  final String speed;

  const TrafficInterval({
    required this.startIndex,
    this.endIndex,
    required this.speed,
  });

  bool get isJam => speed == 'TRAFFIC_JAM';
  bool get isSlow => speed == 'SLOW';
  bool get isNormal => !isJam && !isSlow;

  static List<TrafficInterval> listFrom(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map(
          (entry) => TrafficInterval(
            startIndex: (entry['startIndex'] as num?)?.toInt() ?? 0,
            endIndex: (entry['endIndex'] as num?)?.toInt(),
            speed: (entry['speed'] as String?) ?? 'NORMAL',
          ),
        )
        .toList();
  }

  static List<({List<LatLng> points, TrafficInterval? interval})> segment(
    List<LatLng> points,
    List<TrafficInterval> intervals,
  ) {
    if (points.length < 2) return const [];
    if (intervals.isEmpty) {
      return [(points: points, interval: null)];
    }

    final ordered = [...intervals]
      ..sort((a, b) => a.startIndex.compareTo(b.startIndex));
    final segments = <({List<LatLng> points, TrafficInterval? interval})>[];
    final lastIndex = points.length - 1;

    for (var i = 0; i < ordered.length; i++) {
      final interval = ordered[i];
      final start = interval.startIndex.clamp(0, lastIndex);
      final end = (interval.endIndex ?? lastIndex).clamp(0, lastIndex);
      if (end <= start) continue;

      segments.add((
        points: points.sublist(start, end + 1),
        interval: interval,
      ));
    }

    return segments.isEmpty ? [(points: points, interval: null)] : segments;
  }
}

class RouteDetails {
  final List<LatLng> polylinePoints;
  final double distanceKm;
  final double durationMin;
  final String trafficLevel;
  final List<TrafficInterval> trafficIntervals;
  final bool isEstimated;

  const RouteDetails({
    required this.polylinePoints,
    required this.distanceKm,
    required this.durationMin,
    this.trafficLevel = 'NORMAL',
    this.trafficIntervals = const [],
    this.isEstimated = false,
  });
}

class MapService {
  static final MapService _instance = MapService._internal();
  factory MapService() => _instance;
  MapService._internal();

  static List<PlaceSuggestion> get fallbackLocations => _knownLocations;

  static List<PlaceSuggestion> _searchLocalGazetteer(String query) {
    final needle = query.toLowerCase();
    return _knownLocations
        .where(
          (h) =>
              h.mainText.toLowerCase().contains(needle) ||
              h.secondaryText.toLowerCase().contains(needle),
        )
        .toList();
  }

  static const List<PlaceSuggestion> _knownLocations = [
    // Jhang & Regional Locations
    PlaceSuggestion(
      placeId: 'jhang_superior_college',
      mainText: 'Superior College Jhang',
      secondaryText: 'Gojra Road, Naya Shehar, Pakistan',
      coordinates: LatLng(31.2781, 72.3317),
    ),
    PlaceSuggestion(
      placeId: 'jhang_ayub_chowk',
      mainText: 'Ayub Chowk Clock Tower',
      secondaryText: 'Riaz Cinema Street, Gohar Shah Jhang, Pakistan',
      coordinates: LatLng(31.2685, 72.3184),
    ),
    PlaceSuggestion(
      placeId: 'jhang_satellite_town',
      mainText: 'A Block Satellite Town Jhang',
      secondaryText: 'Satellite Town Block A, Jhang, Pakistan',
      coordinates: LatLng(31.2842, 72.3412),
    ),
    PlaceSuggestion(
      placeId: 'jhang_sheikh_lahori',
      mainText: 'Sheikh Lahori Bazaar',
      secondaryText: 'Jhang Sadar Mohalla Sheikh Lahori, Jhang, Pakistan',
      coordinates: LatLng(31.2650, 72.3150),
    ),

    // Islamabad
    PlaceSuggestion(
      placeId: 'isb_blue_area',
      mainText: 'Blue Area Commercial Center',
      secondaryText: 'Jinnah Avenue, Islamabad',
      coordinates: LatLng(33.7128, 73.0642),
    ),
    PlaceSuggestion(
      placeId: 'isb_centaurus',
      mainText: 'The Centaurus Mall',
      secondaryText: 'Jinnah Ave, Sector F-8/4, Islamabad',
      coordinates: LatLng(33.7078, 73.0501),
    ),
    PlaceSuggestion(
      placeId: 'isb_airport',
      mainText: 'Islamabad International Airport (ISB)',
      secondaryText: 'Airport Road, Islamabad',
      coordinates: LatLng(33.5605, 72.8518),
    ),

    // Lahore
    PlaceSuggestion(
      placeId: 'lhr_gulberg',
      mainText: 'Main Boulevard Gulberg',
      secondaryText: 'Gulberg III, Lahore',
      coordinates: LatLng(31.5126, 74.3444),
    ),
    PlaceSuggestion(
      placeId: 'lhr_airport',
      mainText: 'Allama Iqbal International Airport (LHE)',
      secondaryText: 'Airport Road, Cantt, Lahore',
      coordinates: LatLng(31.5216, 74.4036),
    ),
  ];

  Future<LatLng?> getCurrentPosition() async {
    try {
      final loc = await LocationService().fetchCurrentPosition();
      if (loc != null) {
        return LatLng(loc.latitude, loc.longitude);
      }
    } catch (e) {
      debugPrint('MapService.getCurrentPosition error: $e');
    }
    return null;
  }

  Future<String> reverseGeocode(double lat, double lng) async {
    if (Firebase.apps.isNotEmpty && FirebaseAuth.instance.currentUser != null) {
      try {
        final res = await FirebaseFunctions.instance
            .httpsCallable('reverseGeocode')
            .call(<String, dynamic>{'latitude': lat, 'longitude': lng});
        final address = res.data['address'] as String?;
        if (address != null && address.trim().isNotEmpty) return address;
      } catch (e) {
        debugPrint('[MapService] reverseGeocode failed: $e');
      }
    }

    return 'Location (${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)})';
  }

  Future<List<PlaceSuggestion>> searchPlaces(
    String query, {
    LatLng? near,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final remote = await _fetchAutocomplete(trimmed, near);
    if (remote.isNotEmpty) return remote;

    return _searchLocalGazetteer(trimmed);
  }

  Future<List<PlaceSuggestion>> _fetchAutocomplete(
    String query,
    LatLng? near,
  ) async {
    try {
      if (Firebase.apps.isNotEmpty) {
        final res = await FirebaseFunctions.instance
            .httpsCallable('getAutocomplete')
            .call(<String, dynamic>{
              'query': query,
              if (near != null)
                'location': {
                  'latitude': near.latitude,
                  'longitude': near.longitude,
                },
            });

        final predictions = res.data['predictions'];
        if (predictions is List) {
          return predictions
              .whereType<Map>()
              .map(
                (p) => PlaceSuggestion(
                  placeId: (p['placeId'] as String?) ?? '',
                  mainText: (p['mainText'] as String?) ?? '',
                  secondaryText: (p['secondaryText'] as String?) ?? '',
                ),
              )
              .where((p) => p.placeId.isNotEmpty)
              .toList();
        }
      }
    } catch (e) {
      debugPrint(
        '[MapService] Remote autocomplete failed, falling back to local gazetteer: $e',
      );
    }

    return _searchLocalGazetteer(query);
  }

  Future<LatLng?> resolvePlace(String placeId) async {
    if (Firebase.apps.isNotEmpty && placeId.isNotEmpty) {
      try {
        final res = await FirebaseFunctions.instance
            .httpsCallable('getPlaceDetails')
            .call(<String, dynamic>{'placeId': placeId});

        final lat = (res.data['lat'] as num?)?.toDouble();
        final lng = (res.data['lng'] as num?)?.toDouble();
        if (lat != null && lng != null) return LatLng(lat, lng);
      } catch (e) {
        debugPrint('[MapService] resolvePlace failed: $e');
      }
    }
    return null;
  }

  Future<RouteDetails?> fetchRoute(LatLng origin, LatLng destination) async {
    if (Firebase.apps.isEmpty) return null;

    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('getRoute')
          .call({
            'origin': {
              'latitude': origin.latitude,
              'longitude': origin.longitude,
            },
            'destination': {
              'latitude': destination.latitude,
              'longitude': destination.longitude,
            },
          });

      final data = res.data as Map<String, dynamic>;
      final distanceKm = (data['distanceKm'] as num?)?.toDouble();
      final durationMin = (data['durationMin'] as num?)?.toDouble();
      if (distanceKm == null || durationMin == null) return null;

      final encoded = (data['encodedPolyline'] as String?) ?? '';
      final isEstimated = (data['isEstimated'] as bool?) ?? encoded.isEmpty;

      final points = encoded.isEmpty
          ? <LatLng>[origin, destination]
          : decodePolyline(encoded);

      if (points.length < 2) return null;

      return RouteDetails(
        polylinePoints: points,
        distanceKm: distanceKm,
        durationMin: durationMin,
        trafficLevel: (data['trafficLevel'] as String?) ?? 'NORMAL',
        trafficIntervals: TrafficInterval.listFrom(data['trafficIntervals']),
        isEstimated: isEstimated,
      );
    } catch (e) {
      debugPrint('[MapService.fetchRoute] failed: $e');
      return null;
    }
  }

  RouteDetails estimateStraightLineRoute(LatLng origin, LatLng destination) {
    final distanceKm = DistanceCalculator.estimatedDrivingDistance(
      origin.latitude,
      origin.longitude,
      destination.latitude,
      destination.longitude,
    );

    return RouteDetails(
      polylinePoints: <LatLng>[origin, destination],
      distanceKm: distanceKm,
      durationMin: DistanceCalculator.estimatedDurationMinutes(distanceKm),
      trafficLevel: 'NORMAL',
      isEstimated: true,
    );
  }

  List<LatLng> decodePolyline(String encoded) {
    return PolylineService.decodePolyline(encoded);
  }

  String encodePolyline(List<LatLng> points) {
    return PolylineService.encodePolyline(points);
  }
}
