import 'dart:convert';
import 'dart:io';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'native_map_service.dart';
import 'package:swiftride/services/location_service.dart';

import '../core/constants/app_constants.dart';
import '../core/utils/distance_calculator.dart';
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

  /// In-memory cache for reverse-geocoded addresses keyed by lat/lng rounded to 4 decimals (~11m).
  static final Map<String, String> _reverseGeocodeCache = <String, String>{};



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

  String _buildPrecisePropertyAddress(List<dynamic> results) {
    if (results.isEmpty) return '';

    // Prioritize ROOFTOP and granular premises over broad locality/city entries
    Map<dynamic, dynamic>? best;
    for (final r in results) {
      if (r is Map) {
        final geom = r['geometry'] is Map ? r['geometry'] as Map : null;
        final locType = geom?['location_type'] as String?;
        final types = (r['types'] as List?)?.map((t) => t.toString()).toList() ?? [];
        if (locType == 'ROOFTOP' && types.any((t) => ['street_address', 'premise', 'subpremise'].contains(t))) {
          best = r;
          break;
        }
      }
    }

    best ??= results.firstWhere(
      (r) => r is Map && ((r['types'] as List?)?.any((t) => ['premise', 'subpremise', 'street_address'].contains(t.toString())) ?? false),
      orElse: () => null,
    ) as Map<dynamic, dynamic>?;

    best ??= results.firstWhere(
      (r) => r is Map && ((r['types'] as List?)?.any((t) => ['establishment', 'point_of_interest'].contains(t.toString())) ?? false),
      orElse: () => null,
    ) as Map<dynamic, dynamic>?;

    best ??= results.first is Map ? results.first as Map : null;
    if (best == null) return '';

    final comps = (best['address_components'] as List?)?.whereType<Map>().toList() ?? [];
    String getComp(String type) {
      for (final c in comps) {
        final types = (c['types'] as List?)?.map((t) => t.toString()).toList() ?? [];
        if (types.contains(type)) {
          return (c['long_name'] as String?) ?? '';
        }
      }
      return '';
    }

    final streetNumber = getComp('street_number');
    final premise = getComp('premise').isNotEmpty ? getComp('premise') : getComp('subpremise');
    final poi = getComp('point_of_interest').isNotEmpty ? getComp('point_of_interest') : getComp('establishment');
    final route = getComp('route');
    final sublocality = getComp('sublocality_level_1').isNotEmpty
        ? getComp('sublocality_level_1')
        : (getComp('sublocality').isNotEmpty ? getComp('sublocality') : getComp('neighborhood'));
    final locality = getComp('locality').isNotEmpty
        ? getComp('locality')
        : getComp('administrative_area_level_2');

    final rawFormatted = ((best['formatted_address'] as String?) ?? '')
        .replaceAll(RegExp(r',\s*Pakistan$', caseSensitive: false), '')
        .trim();

    // Synthesize exact property identifier (House/Plot Number)
    if (streetNumber.isNotEmpty || premise.isNotEmpty || poi.isNotEmpty) {
      String propertyPrefix = poi.isNotEmpty ? poi : premise;
      if (propertyPrefix.isEmpty && streetNumber.isNotEmpty) {
        final isNumeric = RegExp(r'^\d+[A-Za-z]?$').hasMatch(streetNumber.trim());
        propertyPrefix = isNumeric ? 'House ${streetNumber.trim()}' : streetNumber.trim();
      }

      if (propertyPrefix.isNotEmpty && !rawFormatted.toLowerCase().contains(propertyPrefix.toLowerCase())) {
        final parts = <String>[propertyPrefix];
        if (route.isNotEmpty && !parts.any((p) => p.toLowerCase().contains(route.toLowerCase()))) {
          parts.add(route);
        }
        if (sublocality.isNotEmpty && !parts.any((p) => p.toLowerCase().contains(sublocality.toLowerCase()))) {
          parts.add(sublocality);
        }
        if (locality.isNotEmpty && !parts.any((p) => p.toLowerCase().contains(locality.toLowerCase()))) {
          parts.add(locality);
        }
        return parts.join(', ');
      }
    }

    return rawFormatted.isNotEmpty ? rawFormatted : (best['formatted_address'] as String? ?? '');
  }

  String _buildPreciseAddressFromPlacesPlace(Map<dynamic, dynamic> place) {
    final rawFormatted = ((place['formattedAddress'] as String?) ?? '')
        .replaceAll(RegExp(r',\s*Pakistan$', caseSensitive: false), '')
        .trim();
    final displayName = place['displayName'] is Map
        ? ((place['displayName']['text'] as String?) ?? '')
        : '';

    final comps = (place['addressComponents'] as List?)?.whereType<Map>().toList() ?? [];
    String getComp(String type) {
      for (final c in comps) {
        final types = (c['types'] as List?)?.map((t) => t.toString()).toList() ?? [];
        if (types.contains(type)) {
          return (c['longText'] as String?) ?? (c['shortText'] as String?) ?? '';
        }
      }
      return '';
    }

    final streetNumber = getComp('street_number');
    final subpremise = getComp('subpremise');
    final premise = getComp('premise');
    final landmark = getComp('landmark');
    final poi = getComp('point_of_interest');
    final route = getComp('route');
    final subloc2 = getComp('sublocality_level_2');
    final subloc1 = getComp('sublocality_level_1').isNotEmpty
        ? getComp('sublocality_level_1')
        : getComp('neighborhood');
    final locality = getComp('locality').isNotEmpty
        ? getComp('locality')
        : getComp('administrative_area_level_2');

    // Filter out generic plus code from displayName
    final isNamePlusCode = RegExp(r'^[A-Za-z0-9]{4,8}\+[A-Za-z0-9]{2,4}$').hasMatch(displayName.trim());
    final effectiveName = (!isNamePlusCode && displayName.isNotEmpty && displayName.toLowerCase() != locality.toLowerCase())
        ? displayName.trim()
        : '';

    // If we have a genuine building or property name (e.g. "Babar House", "CANAL Hospital", "House 145")
    if (effectiveName.isNotEmpty) {
      if (rawFormatted.toLowerCase().contains(effectiveName.toLowerCase())) {
        return rawFormatted;
      }
      final parts = <String>[effectiveName];
      if (route.isNotEmpty && !parts.any((p) => p.toLowerCase().contains(route.toLowerCase()))) {
        parts.add(route);
      }
      if (subloc2.isNotEmpty && !parts.any((p) => p.toLowerCase().contains(subloc2.toLowerCase()))) {
        parts.add(subloc2);
      }
      if (subloc1.isNotEmpty && !parts.any((p) => p.toLowerCase().contains(subloc1.toLowerCase()))) {
        parts.add(subloc1);
      }
      if (locality.isNotEmpty && !parts.any((p) => p.toLowerCase().contains(locality.toLowerCase()))) {
        parts.add(locality);
      }
      return parts.join(', ');
    }

    // Synthesize from street number / plot / route / blocks
    final propertyPrefix = subpremise.isNotEmpty
        ? subpremise
        : (premise.isNotEmpty
            ? premise
            : (streetNumber.isNotEmpty
                ? (RegExp(r'^\d+[A-Za-z]?$').hasMatch(streetNumber.trim()) ? 'House ${streetNumber.trim()}' : streetNumber.trim())
                : (landmark.isNotEmpty ? landmark : poi)));

    if (propertyPrefix.isNotEmpty) {
      if (rawFormatted.toLowerCase().contains(propertyPrefix.toLowerCase())) {
        return rawFormatted;
      }
      final parts = <String>[propertyPrefix];
      if (route.isNotEmpty) parts.add(route);
      if (subloc2.isNotEmpty) parts.add(subloc2);
      if (subloc1.isNotEmpty && !parts.contains(subloc1)) parts.add(subloc1);
      if (locality.isNotEmpty && !parts.contains(locality)) parts.add(locality);
      return parts.join(', ');
    }

    if (rawFormatted.isNotEmpty && rawFormatted.toLowerCase() != locality.toLowerCase()) {
      return rawFormatted;
    }

    final fallbackParts = <String>[
      if (route.isNotEmpty) route,
      if (subloc2.isNotEmpty) subloc2,
      if (subloc1.isNotEmpty) subloc1,
      if (locality.isNotEmpty) locality,
    ];
    return fallbackParts.isNotEmpty ? fallbackParts.join(', ') : rawFormatted;
  }

  Future<String?> _fetchPlacesNearbyReverseGeocode(double lat, double lng) async {
    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = const Duration(milliseconds: 2500);
      final url = Uri.parse('https://places.googleapis.com/v1/places:searchNearby');
      final req = await client.postUrl(url).timeout(const Duration(milliseconds: 2500));
      const apiKey = 'AIzaSyAph82ESQ7BZkhIoaGm5BFv5wMfP1qOwqE';
      req.headers.set('Content-Type', 'application/json');
      req.headers.set('X-Goog-Api-Key', apiKey);
      req.headers.set(
        'X-Goog-FieldMask',
        'places.displayName,places.formattedAddress,places.addressComponents',
      );
      if (Platform.isIOS) {
        req.headers.set('X-Ios-Bundle-Identifier', 'com.dartnexuslab.swiftride');
      } else if (Platform.isAndroid) {
        req.headers.set('X-Android-Package', 'com.dartnexuslab.swiftride');
      }

      final body = jsonEncode({
        'locationRestriction': {
          'circle': {
            'center': {'latitude': lat, 'longitude': lng},
            'radius': 120.0,
          },
        },
        'maxResultCount': 5,
      });
      req.write(body);
      final resp = await req.close().timeout(const Duration(milliseconds: 2500));
      if (resp.statusCode == 200) {
        final respBody = await resp.transform(utf8.decoder).join().timeout(const Duration(milliseconds: 2500));
        final data = jsonDecode(respBody) as Map<String, dynamic>;
        final places = data['places'] as List?;
        if (places != null && places.isNotEmpty) {
          for (final p in places) {
            if (p is Map) {
              final formatted = _buildPreciseAddressFromPlacesPlace(p);
              if (formatted.isNotEmpty && !formatted.toLowerCase().startsWith('location (')) {
                return formatted;
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[MapService] Places API New searchNearby error: $e');
    } finally {
      client?.close();
    }
    return null;
  }

  Future<({String address, LatLng coordinates})?> _fetchPlacesTextSearch(
    String query, {
    double? lat,
    double? lng,
  }) async {
    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = const Duration(milliseconds: 2500);
      final url = Uri.parse('https://places.googleapis.com/v1/places:searchText');
      final req = await client.postUrl(url).timeout(const Duration(milliseconds: 2500));
      const apiKey = 'AIzaSyAph82ESQ7BZkhIoaGm5BFv5wMfP1qOwqE';
      req.headers.set('Content-Type', 'application/json');
      req.headers.set('X-Goog-Api-Key', apiKey);
      req.headers.set(
        'X-Goog-FieldMask',
        'places.displayName,places.formattedAddress,places.location,places.addressComponents',
      );
      if (Platform.isIOS) {
        req.headers.set('X-Ios-Bundle-Identifier', 'com.dartnexuslab.swiftride');
      } else if (Platform.isAndroid) {
        req.headers.set('X-Android-Package', 'com.dartnexuslab.swiftride');
      }

      final reqData = <String, dynamic>{
        'textQuery': query,
      };
      if (lat != null && lng != null) {
        reqData['locationBias'] = {
          'circle': {
            'center': {'latitude': lat, 'longitude': lng},
            'radius': 50000.0,
          },
        };
      }

      req.write(jsonEncode(reqData));
      final resp = await req.close().timeout(const Duration(milliseconds: 2500));
      if (resp.statusCode == 200) {
        final respBody = await resp.transform(utf8.decoder).join().timeout(const Duration(milliseconds: 2500));
        final data = jsonDecode(respBody) as Map<String, dynamic>;
        final places = data['places'] as List?;
        if (places != null && places.isNotEmpty) {
          final first = places.first as Map;
          final loc = first['location'] as Map?;
          final resLat = (loc?['latitude'] as num?)?.toDouble() ?? lat;
          final resLng = (loc?['longitude'] as num?)?.toDouble() ?? lng;

          if (resLat != null && resLng != null) {
            final nearbyAddr = await _fetchPlacesNearbyReverseGeocode(resLat, resLng);
            final builtAddr = _buildPreciseAddressFromPlacesPlace(first);
            final finalAddr = (nearbyAddr != null &&
                    nearbyAddr.isNotEmpty &&
                    nearbyAddr.length > builtAddr.length &&
                    !nearbyAddr.toLowerCase().startsWith('location ('))
                ? nearbyAddr
                : (builtAddr.isNotEmpty
                    ? builtAddr
                    : (first['formattedAddress'] as String? ?? query));

            return (address: finalAddr, coordinates: LatLng(resLat, resLng));
          }
        }
      }
    } catch (e) {
      debugPrint('[MapService] Places API New searchText error: $e');
    } finally {
      client?.close();
    }
    return null;
  }

  Future<String?> _fetchGoogleReverseGeocode(double lat, double lng) async {
    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = const Duration(milliseconds: 2500);
      const apiKey = 'AIzaSyAph82ESQ7BZkhIoaGm5BFv5wMfP1qOwqE';
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json?latlng=$lat,$lng&key=$apiKey',
      );
      final req = await client.getUrl(url).timeout(const Duration(milliseconds: 2500));
      if (Platform.isIOS) {
        req.headers.set('X-Ios-Bundle-Identifier', 'com.dartnexuslab.swiftride');
      } else if (Platform.isAndroid) {
        req.headers.set('X-Android-Package', 'com.dartnexuslab.swiftride');
      }
      final resp = await req.close().timeout(const Duration(milliseconds: 2500));
      if (resp.statusCode == 200) {
        final body = await resp.transform(utf8.decoder).join().timeout(const Duration(milliseconds: 2500));
        final data = jsonDecode(body) as Map<String, dynamic>;
        if (data['status'] == 'OK' && data['results'] is List) {
          final results = data['results'] as List;
          final precise = _buildPrecisePropertyAddress(results);
          if (precise.isNotEmpty) return precise;
        }
      }
    } catch (e) {
      debugPrint('[MapService] Direct Google reverse geocode error: $e');
    } finally {
      client?.close();
    }
    return null;
  }

  /// Resolves an exact property address and coordinates from either lat/lng or
  /// a Google Maps Plus Code / query string (e.g. "78G5+48 Jhang, Pakistan" or "House 145").
  Future<({String address, LatLng coordinates})?> resolveExactLocation({
    double? lat,
    double? lng,
    String? query,
  }) async {
    final cleanQuery = query?.trim() ?? '';

    // 1. First try Google Places API (New) Text Search with property/building resolution
    if (cleanQuery.isNotEmpty) {
      final placesRes = await _fetchPlacesTextSearch(cleanQuery, lat: lat, lng: lng);
      if (placesRes != null && placesRes.address.isNotEmpty) {
        return placesRes;
      }
    }

    // 2. If we have coordinates, try Google Places API (New) Nearby Search
    if (lat != null && lng != null) {
      final nearby = await _fetchPlacesNearbyReverseGeocode(lat, lng);
      if (nearby != null && nearby.isNotEmpty && !nearby.startsWith('Location (')) {
        return (address: nearby, coordinates: LatLng(lat, lng));
      }
    }

    // 3. Direct Google Geocoding REST fallback
    if (cleanQuery.isNotEmpty) {
      try {
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 4);
        const apiKey = 'AIzaSyAph82ESQ7BZkhIoaGm5BFv5wMfP1qOwqE';
        final url = Uri.parse(
          'https://maps.googleapis.com/maps/api/geocode/json?address=${Uri.encodeComponent(cleanQuery)}&key=$apiKey',
        );
        final req = await client.getUrl(url);
        if (Platform.isIOS) {
          req.headers.set('X-Ios-Bundle-Identifier', 'com.dartnexuslab.swiftride');
        } else if (Platform.isAndroid) {
          req.headers.set('X-Android-Package', 'com.dartnexuslab.swiftride');
        }
        final resp = await req.close();
        if (resp.statusCode == 200) {
          final body = await resp.transform(utf8.decoder).join();
          final data = jsonDecode(body) as Map<String, dynamic>;
          if (data['status'] == 'OK' && data['results'] is List && (data['results'] as List).isNotEmpty) {
            final results = data['results'] as List;
            final precise = _buildPrecisePropertyAddress(results);
            final first = results.first as Map;
            final geom = first['geometry'] as Map?;
            final loc = geom?['location'] as Map?;
            final resLat = (loc?['lat'] as num?)?.toDouble() ?? lat;
            final resLng = (loc?['lng'] as num?)?.toDouble() ?? lng;
            if (resLat != null && resLng != null) {
              return (
                address: precise.isNotEmpty ? precise : (first['formatted_address'] as String? ?? cleanQuery),
                coordinates: LatLng(resLat, resLng),
              );
            }
          }
        }
      } catch (e) {
        debugPrint('[MapService] Direct address/PlusCode geocode error: $e');
      }

      // Fallback: Cloud Function with plusCode/address
      if (Firebase.apps.isNotEmpty) {
        try {
          if (FirebaseAuth.instance.currentUser == null) {
            try { await FirebaseAuth.instance.signInAnonymously(); } catch (_) {}
          }
          final res = await FirebaseFunctions.instance
              .httpsCallable('reverseGeocode')
              .call(<String, dynamic>{
                'plusCode': cleanQuery,
                'address': cleanQuery,
                'lat': ?lat,
                'lng': ?lng,
              });
          final addr = (res.data['address'] as String?) ?? (res.data['formattedAddress'] as String?);
          final resLat = (res.data['latitude'] as num?)?.toDouble() ?? lat;
          final resLng = (res.data['longitude'] as num?)?.toDouble() ?? lng;
          if (addr != null && addr.isNotEmpty && resLat != null && resLng != null && !addr.startsWith('Pinned Spot') && !addr.startsWith('Location (')) {
            return (address: addr, coordinates: LatLng(resLat, resLng));
          }
        } catch (e) {
          debugPrint('[MapService] Cloud Function resolveExactLocation error: $e');
        }
      }
    }

    if (lat != null && lng != null) {
      final addr = await reverseGeocode(lat, lng);
      return (address: addr, coordinates: LatLng(lat, lng));
    }

    return null;
  }

  Future<String> reverseGeocode(double lat, double lng) async {
    final cacheKey = '${lat.toStringAsFixed(4)},${lng.toStringAsFixed(4)}';
    final cached = _reverseGeocodeCache[cacheKey];
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }

    // 1. FAST-PATH: Native OS Geocoder (Android Geocoder / iOS CLGeocoder)
    // Runs locally or via system location daemon; fastest & immune to HTTP stack stalls.
    try {
      final nativeAddr = await NativeMapService.instance
          .reverseGeocode(lat, lng)
          .timeout(const Duration(milliseconds: 1800));
      if (nativeAddr != null &&
          nativeAddr.trim().isNotEmpty &&
          !nativeAddr.startsWith('Location (')) {
        _reverseGeocodeCache[cacheKey] = nativeAddr.trim();
        return nativeAddr.trim();
      }
    } catch (_) {}

    // 2. Google Places API (New) Nearby Search with rich building/shop/house precision
    try {
      final nearby = await _fetchPlacesNearbyReverseGeocode(lat, lng)
          .timeout(const Duration(milliseconds: 2500));
      if (nearby != null &&
          nearby.trim().isNotEmpty &&
          !nearby.startsWith('Location (')) {
        _reverseGeocodeCache[cacheKey] = nearby.trim();
        return nearby.trim();
      }
    } catch (_) {}

    // 3. Direct Google Geocoding API with rooftop & property/house precision
    try {
      final directGoogle = await _fetchGoogleReverseGeocode(lat, lng)
          .timeout(const Duration(milliseconds: 2500));
      if (directGoogle != null &&
          directGoogle.trim().isNotEmpty &&
          !directGoogle.startsWith('Location (')) {
        _reverseGeocodeCache[cacheKey] = directGoogle.trim();
        return directGoogle.trim();
      }
    } catch (_) {}

    // 4. Firebase Functions (with server-side buildPrecisePropertyAddress)
    if (Firebase.apps.isNotEmpty) {
      try {
        if (FirebaseAuth.instance.currentUser == null) {
          try {
            await FirebaseAuth.instance
                .signInAnonymously()
                .timeout(const Duration(seconds: 2));
          } catch (_) {}
        }
        final res = await FirebaseFunctions.instance
            .httpsCallable('reverseGeocode')
            .call(<String, dynamic>{
              'latitude': lat,
              'longitude': lng,
              'lat': lat,
              'lng': lng,
            })
            .timeout(const Duration(milliseconds: 2500));
        final address = (res.data['address'] as String?) ??
            (res.data['formattedAddress'] as String?);
        if (address != null &&
            address.trim().isNotEmpty &&
            !address.startsWith('Pinned Spot') &&
            !address.startsWith('Location (')) {
          _reverseGeocodeCache[cacheKey] = address.trim();
          return address.trim();
        }
      } catch (e) {
        debugPrint('[MapService] Firebase Functions reverseGeocode error: $e');
      }
    }

    // 5. OpenStreetMap Nominatim reverse geocode with 2s strict timeout
    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 2);
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=$lat&lon=$lng&zoom=18&addressdetails=1',
      );
      final req = await client.getUrl(url).timeout(const Duration(seconds: 2));
      req.headers.set('User-Agent', 'SwiftRideApp/1.0 (RideHailing)');
      final resp = await req.close().timeout(const Duration(seconds: 2));
      if (resp.statusCode == 200) {
        final body = await resp
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: 2));
        final data = jsonDecode(body) as Map<String, dynamic>;
        final addr = data['address'] as Map<String, dynamic>?;
        if (addr != null) {
          final houseNumber =
              (addr['house_number'] ?? addr['house_name'] ?? '') as String;
          final road = (addr['road'] ??
              addr['street'] ??
              addr['pedestrian'] ??
              '') as String;
          final neighbourhood = (addr['neighbourhood'] ??
              addr['suburb'] ??
              addr['residential'] ??
              '') as String;
          final city =
              (addr['city'] ?? addr['town'] ?? addr['village'] ?? '') as String;

          final parts = <String>[];
          if (houseNumber.isNotEmpty) {
            final isPureNum =
                RegExp(r'^\d+[A-Za-z]?$').hasMatch(houseNumber.trim());
            parts.add(
              isPureNum ? 'House ${houseNumber.trim()}' : houseNumber.trim(),
            );
          }
          if (road.isNotEmpty) parts.add(road);
          if (neighbourhood.isNotEmpty) parts.add(neighbourhood);
          if (city.isNotEmpty && !parts.contains(city)) parts.add(city);

          if (parts.isNotEmpty) {
            final formatted = parts.join(', ');
            _reverseGeocodeCache[cacheKey] = formatted;
            return formatted;
          }
        }
        final displayName = data['display_name'] as String?;
        if (displayName != null && displayName.isNotEmpty) {
          final segments =
              displayName.split(',').map((s) => s.trim()).take(3).join(', ');
          if (segments.isNotEmpty) {
            _reverseGeocodeCache[cacheKey] = segments;
            return segments;
          }
        }
      }
    } catch (e) {
      debugPrint('[MapService] Nominatim reverseGeocode fallback error: $e');
    } finally {
      client?.close();
    }

    final fallback = 'Location (${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)})';
    _reverseGeocodeCache[cacheKey] = fallback;
    return fallback;
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

    if (parsed != null) {
      // Asynchronously resolve exact property address using Google Places API (New)
      final exact = await _fetchPlacesTextSearch(
        trimmed,
        lat: parsed.latitude,
        lng: parsed.longitude,
      );

      final fullAddress = (exact != null &&
              exact.address.isNotEmpty &&
              !exact.address.startsWith('Location ('))
          ? exact.address
          : (parsed.label ?? 'Pinned Location');
      final coords = exact?.coordinates ?? LatLng(parsed.latitude, parsed.longitude);

      final pinnedItem = PlaceSuggestion(
        placeId:
            'pinned:${coords.latitude},${coords.longitude}:$fullAddress',
        mainText: fullAddress,
        secondaryText:
            'Coordinates: ${coords.latitude.toStringAsFixed(5)}, ${coords.longitude.toStringAsFixed(5)}',
        coordinates: coords,
      );

      final remote = await _fetchAutocomplete(trimmed, near);
      return [pinnedItem, ...remote];
    }

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
            await FirebaseAuth.instance
                .signInAnonymously()
                .timeout(const Duration(seconds: 2));
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
            })
            .timeout(const Duration(seconds: 3));

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
      debugPrint('[MapService] _fetchAutocomplete error: $e');
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
    // 1. First try Cloud Function with responsive 4s timeout
    try {
      final plan = await _fetchRouteFromCloudFunction(origin, destination)
          .timeout(const Duration(seconds: 4));
      if (plan != null &&
          plan.routes.isNotEmpty &&
          plan.routes.first.steps.isNotEmpty) {
        return RoutePlan(
          routes: _enrichRoutes(plan.routes),
          defaultIndex: plan.defaultIndex,
        );
      }
    } catch (e) {
      debugPrint('[MapService] Cloud Function route fetch error/timeout: $e');
    }

    // 2. Direct Google Routes API v2 fallback with responsive 4s timeout
    try {
      debugPrint('[MapService] Querying direct Google Routes API v2 for detailed directions');
      final directPlan = await _fetchRouteDirect(origin, destination)
          .timeout(const Duration(seconds: 4));
      if (directPlan != null && directPlan.routes.isNotEmpty) {
        return RoutePlan(
          routes: _enrichRoutes(directPlan.routes),
          defaultIndex: directPlan.defaultIndex,
        );
      }
    } catch (e) {
      debugPrint('[MapService] Direct Google Routes API v2 error/timeout: $e');
    }

    // 3. OFFLINE / POOR NETWORK FALLBACK: Return estimated route immediately
    // so the app NEVER hangs, freezes, or fails to calculate fare & display directions.
    return _generateOfflineFallbackRoute(origin, destination);
  }

  RoutePlan _generateOfflineFallbackRoute(LatLng origin, LatLng destination) {
    final distKm = DistanceCalculator.estimatedDrivingDistance(
      origin.latitude,
      origin.longitude,
      destination.latitude,
      destination.longitude,
    );
    final durMin = DistanceCalculator.estimatedDurationMinutes(distKm);

    const baseFare = 210.0;
    const kmRate = 62.0;
    const minRate = 6.0;
    const fuelRate = 22.0;
    const maintRate = 4.0;
    final fuel = (distKm * fuelRate * 10).round() / 10.0;
    final maint = (distKm * maintRate * 10).round() / 10.0;
    const tollCost = 0.0;
    final driverCost = (fuel + maint + tollCost).round() / 1.0;
    final rawFare = baseFare + distKm * kmRate + durMin * minRate;
    final riderFare = ((rawFare / 5.0).round() * 5.0).toDouble();
    final commission = ((riderFare * 0.02) * 10).round() / 10.0;
    final driverProfit =
        (riderFare - driverCost - commission).clamp(0.0, 999999.0);
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

    final route = RouteOption(
      id: 'offline_fallback_route',
      polylinePoints: [origin, destination],
      distanceKm: distKm,
      durationMin: durMin,
      staticDurationMin: durMin,
      summary: 'Direct estimated route',
      labels: ['ESTIMATED'],
      trafficLevel: 'NORMAL',
      trafficIntervals: const [],
      steps: [
        RouteStep(
          maneuver: 'STRAIGHT',
          instruction: 'Proceed toward destination',
          primaryInstruction: 'Proceed toward destination',
          secondaryInstruction: 'Estimated ${distKm.toStringAsFixed(1)} km',
          distanceKm: distKm,
          distanceMeters: (distKm * 1000).round(),
          distanceText: '${distKm.toStringAsFixed(1)} km',
          durationMin: durMin,
          durationText: '${durMin.round()} mins',
          startLocation: origin,
          isToll: false,
        ),
      ],
      economics: economics,
      isEstimated: true,
    );

    return RoutePlan(routes: [route], defaultIndex: 0);
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
          })
          .timeout(const Duration(seconds: 4));

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
      client.connectionTimeout = const Duration(seconds: 4);
      final url = Uri.parse(
        'https://routes.googleapis.com/directions/v2:computeRoutes',
      );
      final req = await client.postUrl(url).timeout(const Duration(seconds: 4));

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
      final resp = await req.close().timeout(const Duration(seconds: 4));
      if (resp.statusCode != 200) {
        final errText = await resp.transform(utf8.decoder).join().timeout(const Duration(seconds: 3));
        debugPrint('[MapService._fetchRouteDirect] status=${resp.statusCode}: $errText');
        return null;
      }

      final jsonStr = await resp.transform(utf8.decoder).join().timeout(const Duration(seconds: 4));
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

        // Economics calibrated to realistic local market rates & 2% platform commission
        const baseFare = 210.0;
        const kmRate = 62.0;
        const minRate = 6.0;
        const fuelRate = 22.0;
        const maintRate = 4.0;
        final fuel = (distKm * fuelRate * 10).round() / 10.0;
        final maint = (distKm * maintRate * 10).round() / 10.0;
        final driverCost = (fuel + maint + tollCost).round() / 1.0;
        final rawFare = baseFare + distKm * kmRate + durMin * minRate;
        final riderFare = ((rawFare / 5.0).round() * 5.0).toDouble();
        final commission = ((riderFare * 0.02) * 10).round() / 10.0;
        final driverProfit =
            (riderFare - driverCost - commission).clamp(0.0, 999999.0);
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
