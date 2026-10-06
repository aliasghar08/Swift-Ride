import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart'; // <-- ADDED IMPORT
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
        .map((entry) => TrafficInterval(
              startIndex: (entry['startIndex'] as num?)?.toInt() ?? 0,
              endIndex: (entry['endIndex'] as num?)?.toInt(),
              speed: (entry['speed'] as String?) ?? 'NORMAL',
            ))
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

    final ordered = [...intervals]..sort((a, b) => a.startIndex.compareTo(b.startIndex));
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

  static List<PlaceSuggestion> _searchLocalGazetteer(String query) {
    final needle = query.toLowerCase();
    return _knownLocations
        .where((h) =>
            h.mainText.toLowerCase().contains(needle) ||
            h.secondaryText.toLowerCase().contains(needle))
        .toList();
  }

  static const List<PlaceSuggestion> _knownLocations = [
    // Islamabad
    PlaceSuggestion(placeId: 'isb_blue_area', mainText: 'Blue Area Commercial Center', secondaryText: 'Jinnah Avenue, Islamabad', coordinates: LatLng(33.7128, 73.0642)),
    PlaceSuggestion(placeId: 'isb_centaurus', mainText: 'The Centaurus Mall', secondaryText: 'Jinnah Ave, Sector F-8/4, Islamabad', coordinates: LatLng(33.7078, 73.0501)),
    PlaceSuggestion(placeId: 'isb_airport', mainText: 'Islamabad International Airport (ISB)', secondaryText: 'Airport Road, Islamabad', coordinates: LatLng(33.5605, 72.8518)),
    PlaceSuggestion(placeId: 'isb_f9_park', mainText: 'Fatima Jinnah Park (F-9 Park)', secondaryText: 'Sector F-9, Islamabad', coordinates: LatLng(33.7032, 73.0232)),
    PlaceSuggestion(placeId: 'isb_f6_super', mainText: 'Super Market (F-6 Markaz)', secondaryText: 'School Road, Sector F-6, Islamabad', coordinates: LatLng(33.7297, 73.0746)),
    PlaceSuggestion(placeId: 'isb_f7_jinnah', mainText: 'Jinnah Super Market (F-7 Markaz)', secondaryText: 'College Road, Sector F-7, Islamabad', coordinates: LatLng(33.7208, 73.0573)),
    PlaceSuggestion(placeId: 'isb_f10_markaz', mainText: 'F-10 Markaz', secondaryText: 'Sector F-10, Islamabad', coordinates: LatLng(33.6934, 73.0116)),
    PlaceSuggestion(placeId: 'isb_g9_karachi_co', mainText: 'Karachi Company (G-9 Markaz)', secondaryText: 'Manghopir Road, Sector G-9, Islamabad', coordinates: LatLng(33.6874, 73.0305)),
    PlaceSuggestion(placeId: 'isb_i8_markaz', mainText: 'I-8 Markaz Business Hub', secondaryText: 'Sector I-8, Islamabad', coordinates: LatLng(33.6685, 73.0760)),
    PlaceSuggestion(placeId: 'isb_faisal_mosque', mainText: 'Faisal Mosque', secondaryText: 'Shah Faisal Avenue, E-8, Islamabad', coordinates: LatLng(33.7298, 73.0372)),
    PlaceSuggestion(placeId: 'isb_daman_e_koh', mainText: 'Daman-e-Koh Viewpoint', secondaryText: 'Margalla Hills, Islamabad', coordinates: LatLng(33.7438, 73.0694)),

    // Rawalpindi
    PlaceSuggestion(placeId: 'rwp_saddar', mainText: 'Saddar Rawalpindi Commercial Center', secondaryText: 'The Mall, Saddar, Rawalpindi', coordinates: LatLng(33.5936, 73.0531)),
    PlaceSuggestion(placeId: 'rwp_bahria_town', mainText: 'Bahria Town Phase 4 Civic Center', secondaryText: 'Civic Center, Bahria Town, Rawalpindi', coordinates: LatLng(33.5350, 73.1020)),
    PlaceSuggestion(placeId: 'rwp_dha_phase1', mainText: 'DHA Phase 1 Commercial', secondaryText: 'Grand Trunk Road, Rawalpindi', coordinates: LatLng(33.5412, 73.1235)),
    PlaceSuggestion(placeId: 'rwp_chandni_chowk', mainText: 'Chandni Chowk Murree Road', secondaryText: 'Murree Road, Rawalpindi', coordinates: LatLng(33.6267, 73.0715)),

    // Lahore
    PlaceSuggestion(placeId: 'lhr_gulberg', mainText: 'Main Boulevard Gulberg', secondaryText: 'Gulberg III, Lahore', coordinates: LatLng(31.5126, 74.3444)),
    PlaceSuggestion(placeId: 'lhr_dha_phase5', mainText: 'DHA Phase 5 Commercial', secondaryText: 'DHA, Lahore', coordinates: LatLng(31.4674, 74.4023)),
    PlaceSuggestion(placeId: 'lhr_airport', mainText: 'Allama Iqbal International Airport (LHE)', secondaryText: 'Airport Road, Cantt, Lahore', coordinates: LatLng(31.5216, 74.4036)),
    PlaceSuggestion(placeId: 'lhr_liberty_market', mainText: 'Liberty Market Gulberg', secondaryText: 'Noor Jehan Road, Gulberg III, Lahore', coordinates: LatLng(31.5103, 74.3431)),

    // Karachi
    PlaceSuggestion(placeId: 'khi_clifton', mainText: 'Clifton Beach & Sea View', secondaryText: 'Block 4, Clifton, Karachi', coordinates: LatLng(24.8138, 67.0300)),
    PlaceSuggestion(placeId: 'khi_dha_phase6', mainText: 'DHA Phase 6 Commercial', secondaryText: 'Khayaban-e-Shahbaz, DHA, Karachi', coordinates: LatLng(24.8052, 67.0620)),
    PlaceSuggestion(placeId: 'khi_airport', mainText: 'Jinnah International Airport (KHI)', secondaryText: 'Airport Road, Karachi', coordinates: LatLng(24.9065, 67.1608)),
    PlaceSuggestion(placeId: 'khi_shahrah_faisal', mainText: 'Shahrah-e-Faisal Business Corridor', secondaryText: 'Shahrah-e-Faisal, Karachi', coordinates: LatLng(24.8716, 67.0673)),
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
    // --- NEW: Added auth guard ---
    if (Firebase.apps.isNotEmpty && FirebaseAuth.instance.currentUser != null) {
      try {
        final res = await FirebaseFunctions.instance.httpsCallable('reverseGeocode').call(
          <String, dynamic>{'latitude': lat, 'longitude': lng},
        );
        final address = res.data['address'] as String?;
        if (address != null && address.trim().isNotEmpty) return address;
      } catch (e) {
        debugPrint('[MapService] reverseGeocode failed: $e');
      }
    }

    return 'Location (${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)})';
  }

  Future<List<PlaceSuggestion>> searchPlaces(String query, {LatLng? near}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final remote = await _fetchAutocomplete(trimmed, near);
    if (remote.isNotEmpty) return remote;

    return _searchLocalGazetteer(trimmed);
  }

  

  Future<List<PlaceSuggestion>> _fetchAutocomplete(String query, LatLng? near) async {
    // --- NEW: Added auth guard to gracefully fail if logged out ---
    if (Firebase.apps.isEmpty || FirebaseAuth.instance.currentUser == null) {
      debugPrint('[MapService] Skipping remote autocomplete: User not authenticated.');
      return const [];
    }

    try {
      final res = await FirebaseFunctions.instance.httpsCallable('getAutocomplete').call(
        <String, dynamic>{
          'query': query,
          if (near != null)
            'location': {'latitude': near.latitude, 'longitude': near.longitude},
        },
      );

      final predictions = res.data['predictions'];
      if (predictions is! List) return const [];

      return predictions
          .whereType<Map>()
          .map((p) => PlaceSuggestion(
                placeId: (p['placeId'] as String?) ?? '',
                mainText: (p['mainText'] as String?) ?? '',
                secondaryText: (p['secondaryText'] as String?) ?? '',
              ))
          .where((p) => p.placeId.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('[MapService] autocomplete failed: $e');
      return const [];
    }
  }

  Future<LatLng?> resolvePlace(String placeId) async {
    // --- NEW: Added auth guard ---
    if (Firebase.apps.isEmpty || FirebaseAuth.instance.currentUser == null || placeId.isEmpty) return null;

    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('getPlaceDetails')
          .call(<String, dynamic>{'placeId': placeId});

      final lat = (res.data['lat'] as num?)?.toDouble();
      final lng = (res.data['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return null;
      return LatLng(lat, lng);
    } catch (e) {
      debugPrint('[MapService] resolvePlace failed: $e');
      return null;
    }
  }

  Future<RouteDetails?> fetchRoute(LatLng origin, LatLng destination) async {
    // --- NEW: Added auth guard ---
    if (Firebase.apps.isEmpty || FirebaseAuth.instance.currentUser == null) return null;

    try {
      final res = await FirebaseFunctions.instance.httpsCallable('getRoute').call({
        'origin': {'latitude': origin.latitude, 'longitude': origin.longitude},
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