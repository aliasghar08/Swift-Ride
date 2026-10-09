import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:swiftride/services/location_service.dart';

import '../core/utils/distance_calculator.dart';
import '../core/constants/app_constants.dart';
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

class RouteEconomics {
  final double fuelCost;
  final double maintenanceCost;
  final double tollCost;
  final double driverCost;
  final double riderFare;
  final double commission;
  final double driverProfit;
  final double profitPerMin;

  const RouteEconomics({
    required this.fuelCost,
    required this.maintenanceCost,
    required this.tollCost,
    required this.driverCost,
    required this.riderFare,
    required this.commission,
    required this.driverProfit,
    required this.profitPerMin,
  });

  factory RouteEconomics.fromJson(Map<dynamic, dynamic> json) {
    return RouteEconomics(
      fuelCost: (json['fuelCost'] as num?)?.toDouble() ?? 0.0,
      maintenanceCost: (json['maintenanceCost'] as num?)?.toDouble() ?? 0.0,
      tollCost: (json['tollCost'] as num?)?.toDouble() ?? 0.0,
      driverCost: (json['driverCost'] as num?)?.toDouble() ?? 0.0,
      riderFare: (json['riderFare'] as num?)?.toDouble() ?? 0.0,
      commission: (json['commission'] as num?)?.toDouble() ?? 0.0,
      driverProfit: (json['driverProfit'] as num?)?.toDouble() ?? 0.0,
      profitPerMin: (json['profitPerMin'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
    'fuelCost': fuelCost,
    'maintenanceCost': maintenanceCost,
    'tollCost': tollCost,
    'driverCost': driverCost,
    'riderFare': riderFare,
    'commission': commission,
    'driverProfit': driverProfit,
    'profitPerMin': profitPerMin,
  };
}

class RouteStep {
  final String maneuver; // TURN_LEFT, TURN_RIGHT, STRAIGHT, ...
  final String instruction; // "Turn left onto Jhang Road"
  final double distanceKm;
  final double durationMin;

  const RouteStep({
    required this.maneuver,
    required this.instruction,
    required this.distanceKm,
    required this.durationMin,
  });

  factory RouteStep.fromJson(Map<dynamic, dynamic> json) {
    return RouteStep(
      maneuver: (json['maneuver'] as String?) ?? 'STRAIGHT',
      instruction: (json['instruction'] as String?) ?? 'Continue',
      distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 0.0,
      durationMin: (json['durationMin'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
    'maneuver': maneuver,
    'instruction': instruction,
    'distanceKm': distanceKm,
    'durationMin': durationMin,
  };
}

class RouteOption {
  final String id;
  final List<LatLng> polylinePoints;
  final double distanceKm;
  final double durationMin;
  final double staticDurationMin;
  final String summary;
  final List<String> labels;
  final String trafficLevel;
  final List<TrafficInterval> trafficIntervals;
  final List<RouteStep> steps;
  final RouteEconomics economics;
  final bool isEstimated;

  const RouteOption({
    required this.id,
    required this.polylinePoints,
    required this.distanceKm,
    required this.durationMin,
    required this.staticDurationMin,
    required this.summary,
    required this.labels,
    required this.trafficLevel,
    required this.trafficIntervals,
    this.steps = const [],
    required this.economics,
    this.isEstimated = false,
  });

  factory RouteOption.fromJson(
    Map<dynamic, dynamic> json,
    List<LatLng> points,
  ) {
    return RouteOption(
      id: (json['id'] as String?) ?? '',
      polylinePoints: points,
      distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 0.0,
      durationMin: (json['durationMin'] as num?)?.toDouble() ?? 0.0,
      staticDurationMin:
          (json['staticDurationMin'] as num?)?.toDouble() ?? 0.0,
      summary: (json['summary'] as String?) ?? '',
      labels: (json['labels'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      trafficLevel: (json['trafficLevel'] as String?) ?? 'NORMAL',
      trafficIntervals: TrafficInterval.listFrom(json['trafficIntervals']),
      steps: (json['steps'] as List?)
              ?.whereType<Map>()
              .map((s) => RouteStep.fromJson(s))
              .toList() ??
          const [],
      economics: json['economics'] is Map
          ? RouteEconomics.fromJson(json['economics'] as Map)
          : const RouteEconomics(
              fuelCost: 0,
              maintenanceCost: 0,
              tollCost: 0,
              driverCost: 0,
              riderFare: 0,
              commission: 0,
              driverProfit: 0,
              profitPerMin: 0,
            ),
    );
  }
}

class RoutePlan {
  final List<RouteOption> routes;
  final int defaultIndex;

  const RoutePlan({
    required this.routes,
    this.defaultIndex = 0,
  });
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
    if (Firebase.apps.isNotEmpty) {
      if (FirebaseAuth.instance.currentUser == null) {
        try {
          await FirebaseAuth.instance.signInAnonymously();
        } catch (_) {}
      }
      try {
        final res = await FirebaseFunctions.instance
            .httpsCallable('reverseGeocode')
            .call(<String, dynamic>{
              'latitude': lat,
              'longitude': lng,
              'lat': lat,
              'lng': lng,
            });
        final address = (res.data['address'] as String?) ??
            (res.data['formattedAddress'] as String?);
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

    return await _fetchAutocomplete(trimmed, near);
  }

  Future<List<PlaceSuggestion>> _fetchAutocomplete(
    String query,
    LatLng? near,
  ) async {
    try {
      if (Firebase.apps.isNotEmpty) {
        if (FirebaseAuth.instance.currentUser == null) {
          try {
            await FirebaseAuth.instance.signInAnonymously();
          } catch (authErr) {
            debugPrint('[MapService] signInAnonymously failed: $authErr');
          }
        }

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
      debugPrint('[MapService] Remote autocomplete failed: $e');
    }

    return const [];
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

  Future<RoutePlan?> fetchRoute(LatLng origin, LatLng destination) async {
    if (Firebase.apps.isEmpty) return null;

    if (FirebaseAuth.instance.currentUser == null) {
      try {
        await FirebaseAuth.instance.signInAnonymously();
      } catch (authErr) {
        debugPrint('[MapService] signInAnonymously failed: $authErr');
      }
    }

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
            'vehicleType': 'CAR',
            'commissionRate': AppConstants.commissionRateYear1,
          });

      final data = res.data as Map<dynamic, dynamic>;
      final rawRoutes = data['routes'];
      final defaultIndex = (data['defaultRouteIndex'] as num?)?.toInt() ?? 0;

      if (rawRoutes is List) {
        final routes = <RouteOption>[];
        for (final item in rawRoutes) {
          if (item is Map) {
            final encoded = (item['encodedPolyline'] as String?) ?? '';
            final points = encoded.isNotEmpty
                ? decodePolyline(encoded)
                : <LatLng>[];
            if (points.length >= 2) {
              routes.add(RouteOption.fromJson(item, points));
            }
          }
        }

        return RoutePlan(
          routes: routes,
          defaultIndex: (defaultIndex >= 0 && defaultIndex < routes.length)
              ? defaultIndex
              : 0,
        );
      }
      return const RoutePlan(routes: [], defaultIndex: 0);
    } catch (e) {
      debugPrint('[MapService.fetchRoute] failed: $e');
      return null;
    }
  }

  List<LatLng> decodePolyline(String encoded) {
    return PolylineService.decodePolyline(encoded);
  }

  String encodePolyline(List<LatLng> points) {
    return PolylineService.encodePolyline(points);
  }
}
