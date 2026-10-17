import 'dart:convert';
import 'dart:io';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'native_map_service.dart';
import 'package:swiftride/services/location_service.dart';

import '../core/constants/app_constants.dart';
import 'coordinate_parser.dart';
import 'polyline_service.dart';

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
  final String instruction; // Raw full instruction
  final String primaryInstruction; // Bold main action e.g. "Turn left onto Toba Tek Singh Road"
  final String? secondaryInstruction; // Landmark / sub-note e.g. "Pass by Graveyard (on the right in 500m)"
  final double distanceKm;
  final int distanceMeters;
  final String distanceText; // e.g. "1.5 km", "52 m"
  final double durationMin;
  final String durationText; // e.g. "4 mins", "1 min"
  final String? roadName;
  final LatLng? startLocation;
  final LatLng? endLocation;
  final String? encodedPolyline;
  final bool isToll;

  const RouteStep({
    required this.maneuver,
    required this.instruction,
    required this.primaryInstruction,
    this.secondaryInstruction,
    required this.distanceKm,
    this.distanceMeters = 0,
    required this.distanceText,
    required this.durationMin,
    required this.durationText,
    this.roadName,
    this.startLocation,
    this.endLocation,
    this.encodedPolyline,
    this.isToll = false,
  });

  List<LatLng> get stepPoints {
    if (encodedPolyline != null && encodedPolyline!.isNotEmpty) {
      return PolylineService.decodePolyline(encodedPolyline!);
    }
    return const [];
  }

  factory RouteStep.fromJson(Map<dynamic, dynamic> json) {
    final navInstruction = json['navigationInstruction'] is Map
        ? json['navigationInstruction'] as Map
        : null;
    final rawInstruction = (json['instruction'] as String?) ??
        (navInstruction?['instructions'] as String?) ??
        'Continue';

    final lines = rawInstruction
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final primary = (json['primaryInstruction'] as String?) ??
        (lines.isNotEmpty ? lines.first : rawInstruction);
    final secondary = (json['secondaryInstruction'] as String?) ??
        (lines.length > 1 ? lines.sublist(1).join(' · ') : null);

    final maneuver = (json['maneuver'] as String?) ??
        (navInstruction?['maneuver'] as String?) ??
        'STRAIGHT';

    final rawMeters = (json['distanceMeters'] as num?)?.toInt();
    final distKm = (json['distanceKm'] as num?)?.toDouble() ??
        (rawMeters != null ? rawMeters / 1000.0 : 0.0);
    final distMeters = rawMeters ?? (distKm * 1000).round();

    final locValues =
        json['localizedValues'] is Map ? json['localizedValues'] as Map : null;
    final distText = (json['distanceText'] as String?) ??
        (locValues?['distance'] is Map
            ? locValues!['distance']['text'] as String?
            : null) ??
        (distKm >= 1.0 ? '${distKm.toStringAsFixed(1)} km' : '$distMeters m');

    var durMin = (json['durationMin'] as num?)?.toDouble() ?? 0.0;
    if (durMin == 0.0 && json['staticDuration'] is String) {
      final sec = int.tryParse(
            (json['staticDuration'] as String).replaceAll('s', ''),
          ) ??
          0;
      durMin = (sec / 60.0).roundToDouble();
    }
    final durText = (json['durationText'] as String?) ??
        (locValues?['staticDuration'] is Map
            ? locValues!['staticDuration']['text'] as String?
            : null) ??
        (durMin >= 60
            ? '${durMin ~/ 60} hr ${(durMin % 60).round()} min'
            : '${durMin < 1 ? "< 1" : durMin.round()} min');

    LatLng? startLoc;
    if (json['startLocation'] is Map) {
      final s = json['startLocation'] as Map;
      final latLngMap = s['latLng'] is Map ? s['latLng'] as Map : s;
      final lat = (latLngMap['latitude'] as num?)?.toDouble();
      final lng = (latLngMap['longitude'] as num?)?.toDouble();
      if (lat != null && lng != null) startLoc = LatLng(lat, lng);
    }

    LatLng? endLoc;
    if (json['endLocation'] is Map) {
      final e = json['endLocation'] as Map;
      final latLngMap = e['latLng'] is Map ? e['latLng'] as Map : e;
      final lat = (latLngMap['latitude'] as num?)?.toDouble();
      final lng = (latLngMap['longitude'] as num?)?.toDouble();
      if (lat != null && lng != null) endLoc = LatLng(lat, lng);
    }

    final polyObj = json['polyline'] is Map ? json['polyline'] as Map : null;
    final encPoly = (json['encodedPolyline'] as String?) ??
        (polyObj?['encodedPolyline'] as String?);

    final roadName = (json['roadName'] as String?);
    final isToll = (json['isToll'] as bool?) ??
        rawInstruction.toLowerCase().contains('toll');

    return RouteStep(
      maneuver: maneuver,
      instruction: rawInstruction,
      primaryInstruction: primary,
      secondaryInstruction: secondary,
      distanceKm: distKm,
      distanceMeters: distMeters,
      distanceText: distText,
      durationMin: durMin,
      durationText: durText,
      roadName: roadName,
      startLocation: startLoc,
      endLocation: endLoc,
      encodedPolyline: encPoly,
      isToll: isToll,
    );
  }

  Map<String, dynamic> toJson() => {
    'maneuver': maneuver,
    'instruction': instruction,
    'primaryInstruction': primaryInstruction,
    'secondaryInstruction': secondaryInstruction,
    'distanceKm': distanceKm,
    'distanceMeters': distanceMeters,
    'distanceText': distanceText,
    'durationMin': durationMin,
    'durationText': durationText,
    'roadName': roadName,
    'startLocation': startLocation != null
        ? {'latitude': startLocation!.latitude, 'longitude': startLocation!.longitude}
        : null,
    'endLocation': endLocation != null
        ? {'latitude': endLocation!.latitude, 'longitude': endLocation!.longitude}
        : null,
    'encodedPolyline': encodedPolyline,
    'isToll': isToll,
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
  static MapService get instance => _instance;
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

    // 2. Native OS Geocoder fallback (Android Geocoder / iOS CLGeocoder)
    try {
      final nativeAddr = await NativeMapService.instance.reverseGeocode(lat, lng);
      if (nativeAddr != null && nativeAddr.trim().isNotEmpty) {
        return nativeAddr;
      }
    } catch (_) {}

    return 'Location (${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)})';
  }

  Future<List<PlaceSuggestion>> searchPlaces(
    String query, {
    LatLng? near,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    // Check if query is a pinned location, Plus Code (e.g. 78G5+48 Jhang, Pakistan),
    // DMS, or coordinate pair.
    final parsed = CoordinateParser.tryParse(
      trimmed,
      referenceLat: near?.latitude,
      referenceLng: near?.longitude,
    );

    final remote = await _fetchAutocomplete(trimmed, near);

    if (parsed != null) {
      final pinnedItem = PlaceSuggestion(
        placeId:
            'pinned:${parsed.latitude},${parsed.longitude}:${parsed.label ?? 'Pinned Location'}',
        mainText: parsed.label ?? 'Pinned Location',
        secondaryText:
            'Coordinates: ${parsed.latitude.toStringAsFixed(5)}, ${parsed.longitude.toStringAsFixed(5)}',
        coordinates: LatLng(parsed.latitude, parsed.longitude),
      );

      // Prepend pinned result so it appears as the immediate #1 suggestion
      return [pinnedItem, ...remote];
    }

    return remote;
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
    // 1. Instantly resolve client-parsed pinned locations and Plus Codes
    if (placeId.startsWith('pinned:') || placeId.startsWith('plus:')) {
      final parts = placeId.split(':');
      if (parts.length >= 2) {
        final coordsPart = parts[1].split(',');
        if (coordsPart.length == 2) {
          final lat = double.tryParse(coordsPart[0]);
          final lng = double.tryParse(coordsPart[1]);
          if (lat != null && lng != null) {
            return LatLng(lat, lng);
          }
        }
      }
    }

    // 2. Resolve Google Place ID via Cloud Functions
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
    // 1. First try Cloud Function
    RoutePlan? plan = await _fetchRouteFromCloudFunction(origin, destination);
    if (plan != null &&
        plan.routes.isNotEmpty &&
        plan.routes.first.steps.isNotEmpty) {
      return RoutePlan(
        routes: _enrichRoutes(plan.routes),
        defaultIndex: plan.defaultIndex,
      );
    }

    // 2. Direct Google Routes API v2 fallback (ensures 100% full detail always)
    debugPrint('[MapService] Querying direct Google Routes API v2 for detailed directions');
    final directPlan = await _fetchRouteDirect(origin, destination);
    if (directPlan != null && directPlan.routes.isNotEmpty) {
      return RoutePlan(
        routes: _enrichRoutes(directPlan.routes),
        defaultIndex: directPlan.defaultIndex,
      );
    }

    if (plan != null && plan.routes.isNotEmpty) {
      return RoutePlan(
        routes: _enrichRoutes(plan.routes),
        defaultIndex: plan.defaultIndex,
      );
    }

    return null;
  }

  Future<RoutePlan?> _fetchRouteFromCloudFunction(
    LatLng origin,
    LatLng destination,
  ) async {
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
      debugPrint('[MapService._fetchRouteFromCloudFunction] failed: $e');
      return null;
    }
  }

  Future<RoutePlan?> _fetchRouteDirect(
    LatLng origin,
    LatLng destination,
  ) async {
    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);
      final url = Uri.parse(
        'https://routes.googleapis.com/directions/v2:computeRoutes',
      );
      final req = await client.postUrl(url);

      const apiKey = 'AIzaSyAph82ESQ7BZkhIoaGm5BFv5wMfP1qOwqE';
      req.headers.set('Content-Type', 'application/json');
      req.headers.set('X-Goog-Api-Key', apiKey);
      if (Platform.isIOS) {
        req.headers.set('X-Ios-Bundle-Identifier', 'com.dartnexuslab.swiftride');
      } else if (Platform.isAndroid) {
        req.headers.set('X-Android-Package', 'com.dartnexuslab.swiftride');
      }
      req.headers.set(
        'X-Goog-FieldMask',
        'routes.travelAdvisory.tollInfo,'
        'routes.description,'
        'routes.duration,'
        'routes.staticDuration,'
        'routes.distanceMeters,'
        'routes.polyline.encodedPolyline,'
        'routes.legs.travelAdvisory.speedReadingIntervals,'
        'routes.legs.steps.distanceMeters,'
        'routes.legs.steps.staticDuration,'
        'routes.legs.steps.polyline.encodedPolyline,'
        'routes.legs.steps.startLocation,'
        'routes.legs.steps.endLocation,'
        'routes.legs.steps.navigationInstruction,'
        'routes.legs.steps.localizedValues',
      );

      final body = jsonEncode({
        'origin': {
          'location': {
            'latLng': {
              'latitude': origin.latitude,
              'longitude': origin.longitude,
            },
          },
        },
        'destination': {
          'location': {
            'latLng': {
              'latitude': destination.latitude,
              'longitude': destination.longitude,
            },
          },
        },
        'travelMode': 'DRIVE',
        'routingPreference': 'TRAFFIC_AWARE_OPTIMAL',
        'computeAlternativeRoutes': true,
      });

      req.write(body);
      final resp = await req.close();
      if (resp.statusCode != 200) {
        final errText = await resp.transform(utf8.decoder).join();
        debugPrint('[MapService._fetchRouteDirect] status=${resp.statusCode}: $errText');
        return null;
      }

      final jsonStr = await resp.transform(utf8.decoder).join();
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final rawRoutes = data['routes'];
      if (rawRoutes is! List || rawRoutes.isEmpty) return null;

      final routes = <RouteOption>[];
      for (var i = 0; i < rawRoutes.length; i++) {
        final r = rawRoutes[i] as Map<String, dynamic>;
        final poly = r['polyline']?['encodedPolyline'] as String? ?? '';
        final points = poly.isNotEmpty ? decodePolyline(poly) : <LatLng>[];
        if (points.length < 2) continue;

        final distMeters = (r['distanceMeters'] as num?)?.toDouble() ?? 0.0;
        final distKm = (distMeters / 1000.0 * 10).round() / 10.0;
        final durSec = int.tryParse(
              (r['duration'] as String? ?? '').replaceAll('s', ''),
            ) ??
            0;
        final staticDurSec = int.tryParse(
              (r['staticDuration'] as String? ?? '').replaceAll('s', ''),
            ) ??
            durSec;
        final durMin = (durSec / 60.0).round().toDouble().clamp(1.0, 99999.0);
        final staticDurMin =
            (staticDurSec / 60.0).round().toDouble().clamp(1.0, 99999.0);

        // Toll
        var tollCost = 0.0;
        final estPrices =
            r['travelAdvisory']?['tollInfo']?['estimatedPrice'] as List?;
        if (estPrices != null) {
          for (final p in estPrices) {
            final u = (p['units'] as num?)?.toDouble() ?? 0.0;
            final n = (p['nanos'] as num?)?.toDouble() ?? 0.0;
            tollCost += u + n / 1e9;
          }
        }

        // Economics
        const fuelRate = 14.5;
        const maintRate = 4.0;
        final fuel = (distKm * fuelRate * 10).round() / 10.0;
        final maint = (distKm * maintRate * 10).round() / 10.0;
        final driverCost = (fuel + maint + tollCost * 10).round() / 10.0;
        final riderFare =
            (150 + distKm * 45 + durMin * 5 * 10).round() / 10.0;
        final commission = (riderFare * 0.10 * 10).round() / 10.0;
        final driverProfit =
            (riderFare - driverCost - commission * 10).round() / 10.0;
        final profitPerMin =
            (driverProfit / durMin.clamp(1.0, 99999.0) * 10).round() / 10.0;

        final economics = RouteEconomics(
          fuelCost: fuel,
          maintenanceCost: maint,
          tollCost: tollCost,
          driverCost: driverCost,
          riderFare: riderFare,
          commission: commission,
          driverProfit: driverProfit,
          profitPerMin: profitPerMin,
        );

        // Speed intervals
        final rawIntervals =
            r['legs']?[0]?['travelAdvisory']?['speedReadingIntervals'] ??
            r['travelAdvisory']?['speedReadingIntervals'];
        final intervals = TrafficInterval.listFrom(rawIntervals);
        final trafficLevel = intervals.any((i) => i.isJam)
            ? 'HEAVY'
            : intervals.any((i) => i.isSlow)
                ? 'MODERATE'
                : 'NORMAL';

        // Steps
        final steps = <RouteStep>[];
        final rawLegs = r['legs'] as List? ?? [];
        for (final leg in rawLegs) {
          final legSteps = leg['steps'] as List? ?? [];
          for (final s in legSteps) {
            if (s is Map) {
              steps.add(RouteStep.fromJson(s));
            }
          }
        }

        routes.add(
          RouteOption(
            id: 'direct_route_$i',
            polylinePoints: points,
            distanceKm: distKm,
            durationMin: durMin,
            staticDurationMin: staticDurMin,
            summary: (r['description'] as String?) ?? '',
            labels: i == 0 ? ['FASTEST'] : ['ALTERNATIVE'],
            trafficLevel: trafficLevel,
            trafficIntervals: intervals,
            steps: steps,
            economics: economics,
          ),
        );
      }

      return RoutePlan(routes: routes, defaultIndex: 0);
    } catch (e) {
      debugPrint('[MapService._fetchRouteDirect] error: $e');
      return null;
    } finally {
      client?.close();
    }
  }

  List<RouteOption> _enrichRoutes(List<RouteOption> routes) {
    return routes.map((route) {
      final enrichedSteps = _decomposeLongSteps(route.steps);
      return RouteOption(
        id: route.id,
        polylinePoints: route.polylinePoints,
        distanceKm: route.distanceKm,
        durationMin: route.durationMin,
        staticDurationMin: route.staticDurationMin,
        summary: route.summary,
        labels: route.labels,
        trafficLevel: route.trafficLevel,
        trafficIntervals: route.trafficIntervals,
        steps: enrichedSteps,
        economics: route.economics,
        isEstimated: route.isEstimated,
      );
    }).toList();
  }

  List<RouteStep> _decomposeLongSteps(List<RouteStep> originalSteps) {
    if (originalSteps.isEmpty) return originalSteps;
    final result = <RouteStep>[];

    for (final step in originalSteps) {
      // If a single highway step exceeds 25 km, create sub-milestones
      if (step.distanceKm > 25.0 && step.stepPoints.length >= 10) {
        result.add(step);

        final points = step.stepPoints;
        final totalDist = step.distanceKm;
        final totalDur = step.durationMin;
        final segmentsCount = (totalDist / 25.0).floor().clamp(1, 8);
        final segmentDist = totalDist / (segmentsCount + 1);
        final segmentDur = totalDur / (segmentsCount + 1);

        for (var k = 1; k <= segmentsCount; k++) {
          final sampleIdx = ((points.length - 1) * (k / (segmentsCount + 1))).round();
          final loc = points[sampleIdx];
          final completedKm = (segmentDist * k).toStringAsFixed(0);
          final remainingKm = (totalDist - segmentDist * k).toStringAsFixed(0);

          final road = step.roadName ?? 'expressway/motorway';
          result.add(
            RouteStep(
              maneuver: 'STRAIGHT',
              instruction: 'Continue on $road past intermediate interchanges ($remainingKm km remaining)',
              primaryInstruction: 'Continue on $road ($remainingKm km remaining)',
              secondaryInstruction: 'Stay in lane · Milestone reached at $completedKm km',
              distanceKm: segmentDist,
              distanceMeters: (segmentDist * 1000).round(),
              distanceText: '${segmentDist.toStringAsFixed(1)} km',
              durationMin: segmentDur,
              durationText: '${segmentDur.round()} mins',
              roadName: step.roadName,
              startLocation: loc,
              isToll: step.isToll,
            ),
          );
        }
      } else {
        result.add(step);
      }
    }

    return result;
  }

  List<LatLng> decodePolyline(String encoded) {
    return PolylineService.decodePolyline(encoded);
  }

  String encodePolyline(List<LatLng> points) {
    return PolylineService.encodePolyline(points);
  }
}
