import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'native_map_service.dart';
import 'package:swiftride/services/location_service.dart';

import '../core/constants/app_constants.dart';
import '../core/utils/distance_calculator.dart';
import '../core/utils/geohash_util.dart';
import 'coordinate_parser.dart';
import 'polyline_service.dart';

class ValidatedAddressResult {
  final String formattedAddress;
  final String granularity; // e.g. PREMISE, SUB_PREMISE
  final bool isComplete;
  final LatLng? coordinates;

  const ValidatedAddressResult({
    required this.formattedAddress,
    required this.granularity,
    this.isComplete = false,
    this.coordinates,
  });
}

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

/// Encapsulates a search query tailored with proximity, city-lock, and area-lock scoping.
class ScopedSearchQuery {
  final String rawQuery;
  final String scopedQuery;
  final double radiusMeters;
  final bool isCityLocked;
  final bool isAreaLocked;
  final String? targetCity;
  final String? targetArea;

  const ScopedSearchQuery({
    required this.rawQuery,
    required this.scopedQuery,
    required this.radiusMeters,
    this.isCityLocked = false,
    this.isAreaLocked = false,
    this.targetCity,
    this.targetArea,
  });

  @override
  String toString() =>
      'ScopedSearchQuery(raw: "$rawQuery", scoped: "$scopedQuery", radius: ${radiusMeters}m, cityLocked: $isCityLocked, areaLocked: $isAreaLocked)';
}

class MapService {
  static final MapService _instance = MapService._internal();
  factory MapService() => _instance;
  static MapService get instance => _instance;
  MapService._internal();

  /// Centralized Google Maps API key for direct Google Places & Geocoding REST calls.
  /// On iOS & Android, uses the working key with Places API (New) enabled.
  static String get googleMapsApiKey => 'AIzaSyAph82ESQ7BZkhIoaGm5BFv5wMfP1qOwqE';

  /// In-memory cache for reverse-geocoded addresses keyed by lat/lng rounded to 4 decimals (~11m).
  static final Map<String, String> _reverseGeocodeCache = <String, String>{};

  /// Enforces geographic ground-truth consistency. If [candidateCity] is > 45km
  /// away from [lat, lng], it is quarantined and replaced with the authoritative nearest city.
  static String enforceAuthoritativeCity(double lat, double lng, String? candidateCity) {
    final nearest = CoordinateParser.findNearestCity(lat, lng);
    if (candidateCity == null || candidateCity.trim().isEmpty) {
      return nearest.city;
    }
    final cleanCandidate = candidateCity.trim().toLowerCase();
    final cityCoords = CoordinateParser.pakistanCities[cleanCandidate];
    if (cityCoords != null) {
      final dLat = (lat - cityCoords.lat) * 111.0;
      final dLng = (lng - cityCoords.lng) * 96.0;
      final distKm = math.sqrt(dLat * dLat + dLng * dLng);
      if (distKm > 45.0) {
        debugPrint(
          '[MapService][GeoGuard] Quarantined dirty city "$candidateCity" '
          '(${distKm.toStringAsFixed(1)}km away) -> enforced authoritative "${nearest.city}"',
        );
        return nearest.city;
      }
    }
    return candidateCity.trim();
  }

  /// Sanitizes any resolved address string with GeoGuard to ensure no distant quarantined
  /// city name (>45km away) or foreign postal code leaks through free-text fields.
  static String sanitizeAddressWithGeoGuard(double lat, double lng, String address) {
    final nearest = CoordinateParser.findNearestCity(lat, lng);
    String sanitized = address;
    for (final entry in CoordinateParser.pakistanCities.entries) {
      if (entry.key == nearest.city.toLowerCase()) continue;
      final dLat = (lat - entry.value.lat) * 111.0;
      final dLng = (lng - entry.value.lng) * 96.0;
      final distKm = math.sqrt(dLat * dLat + dLng * dLng);
      if (distKm > 45.0) {
        final regex = RegExp('\\b${RegExp.escape(entry.key)}\\b', caseSensitive: false);
        if (regex.hasMatch(sanitized)) {
          debugPrint(
            '[MapService][GeoGuard] Sanitized distant city "${entry.key}" '
            '(${distKm.toStringAsFixed(1)}km away) -> replaced with "${nearest.city}"',
          );
          sanitized = sanitized.replaceAll(regex, nearest.city);
        }
      }
    }
    return sanitized
        .replaceAll(RegExp(r'\bNaya Shehar\b', caseSensitive: false), nearest.city)
        .replaceAll(RegExp(r'^\s*\d{5},?\s*'), '')
        .replaceAll(RegExp(r',\s*\d{5}\b'), '')
        .replaceAll(RegExp(r'\b\d{5}\b'), '')
        .replaceAll(RegExp(r',\s*Pakistan$', caseSensitive: false), '')
        .replaceAll(RegExp(r',\s*Block,\s*', caseSensitive: false), ', ')
        .replaceAll(RegExp(r'\bBlock,\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'Satellite Town Block A Satellite Town', caseSensitive: false), 'Satellite Town Block A')
        .replaceAll(RegExp(r'Satellite Block A Town', caseSensitive: false), 'Satellite Town Block A')
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && e.toLowerCase() != 'block')
        .join(', ')
        .trim();
  }

  static String toTitleCase(String text) {
    if (text.isEmpty) return text;
    return text.split(' ').map((word) {
      if (word.isEmpty) return word;
      if (word.toUpperCase() == word && word.length <= 4) return word;
      if (word.contains('-')) {
        return word.split('-').map((part) => toTitleCase(part)).join('-');
      }
      return '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}';
    }).join(' ');
  }

  static String cleanSublocalityRepetitions(String raw) {
    return raw
        .replaceAll(RegExp(r'Satellite Town Block A Satellite Town', caseSensitive: false), 'Satellite Town Block A')
        .replaceAll(RegExp(r'Satellite Block A Town', caseSensitive: false), 'Satellite Town Block A')
        .trim();
  }

  /// Safely stores an address in cache only if it is not a bare single-word city or placeholder.
  static void _cacheIfGranular(String cacheKey, String address) {
    final trimmed = address.trim();
    if (trimmed.isEmpty ||
        trimmed.startsWith('Location (') ||
        trimmed.startsWith('Pinned Spot') ||
        trimmed.startsWith('Coordinates:')) {
      return;
    }
    // Never cache single-word broad cities (like "Jhang") so subsequent retries can resolve street/plot detail
    final isSingleWordCity = !trimmed.contains(',') &&
        CoordinateParser.pakistanCities.containsKey(trimmed.toLowerCase());
    if (isSingleWordCity) {
      return;
    }
    _reverseGeocodeCache[cacheKey] = trimmed;
  }



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
        if (locType == 'ROOFTOP' &&
            types.any((t) => ['street_address', 'premise', 'subpremise'].contains(t))) {
          best = r;
          break;
        }
      }
    }

    best ??= results.firstWhere(
      (r) =>
          r is Map &&
          ((r['types'] as List?)?.any(
                (t) => ['premise', 'subpremise', 'street_address'].contains(t.toString()),
              ) ??
              false),
      orElse: () => null,
    ) as Map<dynamic, dynamic>?;

    best ??= results.firstWhere(
      (r) =>
          r is Map &&
          ((r['types'] as List?)?.any(
                (t) => ['establishment', 'point_of_interest'].contains(t.toString()),
              ) ??
              false),
      orElse: () => null,
    ) as Map<dynamic, dynamic>?;

    best ??= results.first is Map ? results.first as Map : null;
    if (best == null) return '';

    // Helper that searches `best` first, then falls back across all results so
    // street_number / premise / route are never missed when split across results.
    String getComp(String type) {
      final bestComps = (best!['address_components'] as List?)?.whereType<Map>().toList() ?? [];
      for (final c in bestComps) {
        final types = (c['types'] as List?)?.map((t) => t.toString()).toList() ?? [];
        if (types.contains(type)) {
          final val = ((c['long_name'] as String?) ?? (c['short_name'] as String?) ?? '').trim();
          if (val.isNotEmpty) return val;
        }
      }
      for (final r in results) {
        if (r is Map) {
          final comps = (r['address_components'] as List?)?.whereType<Map>().toList() ?? [];
          for (final c in comps) {
            final types = (c['types'] as List?)?.map((t) => t.toString()).toList() ?? [];
            if (types.contains(type)) {
              final val = ((c['long_name'] as String?) ?? (c['short_name'] as String?) ?? '').trim();
              if (val.isNotEmpty) return val;
            }
          }
        }
      }
      return '';
    }

    final streetNumber = getComp('street_number');
    final subpremise = getComp('subpremise');
    final premise = getComp('premise');
    final poi = getComp('point_of_interest').isNotEmpty
        ? getComp('point_of_interest')
        : (getComp('establishment').isNotEmpty ? getComp('establishment') : getComp('landmark'));
    final route = getComp('route');
    final subloc2 = getComp('sublocality_level_2');
    final subloc1 = getComp('sublocality_level_1').isNotEmpty
        ? getComp('sublocality_level_1')
        : (getComp('sublocality').isNotEmpty ? getComp('sublocality') : getComp('neighborhood'));
    var locality = getComp('locality').isNotEmpty
        ? getComp('locality')
        : getComp('administrative_area_level_2');

    final geom = best['geometry'] as Map?;
    final locMap = geom?['location'] as Map?;
    final pLat = (locMap?['lat'] as num?)?.toDouble();
    final pLng = (locMap?['lng'] as num?)?.toDouble();
    if (pLat != null && pLng != null) {
      locality = enforceAuthoritativeCity(pLat, pLng, locality);
    }

    final rawFormatted = ((best['formatted_address'] as String?) ?? '')
        .replaceAll(RegExp(r',\s*Pakistan$', caseSensitive: false), '')
        .replaceAll(RegExp(r'^[A-Za-z0-9]{4,8}\+[A-Za-z0-9]{2,5},?\s*'), '')
        .trim();

    final parts = <String>[];
    void addPart(String candidate, {bool isLocality = false}) {
      final clean = candidate.trim();
      if (clean.isEmpty) return;
      if (RegExp(r'^[A-Za-z0-9]{4,8}\+[A-Za-z0-9]{2,5}$').hasMatch(clean)) return;
      final lower = clean.toLowerCase();
      if (isLocality) {
        if (parts.isNotEmpty && parts.last.toLowerCase() == lower) return;
        parts.add(clean);
        return;
      }
      if (parts.any((existing) =>
          existing.toLowerCase() == lower || existing.toLowerCase().contains(lower))) {
        return;
      }
      for (int i = 0; i < parts.length; i++) {
        if (lower.contains(parts[i].toLowerCase())) {
          parts[i] = clean;
          return;
        }
      }
      parts.add(clean);
    }

    if (streetNumber.isNotEmpty) {
      final cleanNumber = streetNumber.trim();
      final isPureNum = RegExp(r'^\d+\s*[A-Za-z]?(-[A-Za-z0-9]+)?$').hasMatch(cleanNumber);
      final hasPrefix = RegExp(
        r'^(plot|house|shop|flat|suite|unit|street|st|block|sector)\b',
        caseSensitive: false,
      ).hasMatch(cleanNumber);
      addPart(isPureNum && !hasPrefix ? 'Plot $cleanNumber' : cleanNumber);
    }
    if (subpremise.isNotEmpty) {
      final cleanSubpremise = subpremise.trim();
      final isPureNum = RegExp(r'^\d+\s*[A-Za-z]?$').hasMatch(cleanSubpremise);
      addPart(isPureNum ? 'Unit $cleanSubpremise' : cleanSubpremise);
    }
    if (premise.isNotEmpty) addPart(premise);
    if (poi.isNotEmpty && poi.toLowerCase() != locality.toLowerCase()) addPart(poi);
    if (route.isNotEmpty && route.toLowerCase() != 'block') {
      var cleanRoute = route;
      if (streetNumber.isNotEmpty || premise.isNotEmpty) {
        cleanRoute = cleanRoute.replaceFirst(RegExp(r'^\d+[A-Za-z]?(?:[/-]\d+[A-Za-z]?)?[\s,-]+'), '').trim();
      }
      if (cleanRoute.isNotEmpty) addPart(toTitleCase(cleanRoute));
    }

    if (subloc2.isNotEmpty && !subloc1.toLowerCase().contains(subloc2.toLowerCase())) {
      addPart(toTitleCase(cleanSublocalityRepetitions(subloc2)));
    } else if (subloc2.isEmpty) {
      final blockMatch = RegExp(r'\b(?:Block\s+[A-Za-z0-9]+|[A-Za-z0-9]+-Block|Phase\s+[0-9]+)\b', caseSensitive: false).firstMatch(rawFormatted);
      if (blockMatch != null) {
        final bToken = blockMatch.group(0)!;
        if (!subloc1.toLowerCase().contains(bToken.toLowerCase())) {
          addPart(toTitleCase(bToken));
        }
      }
    }
    if (subloc1.isNotEmpty) {
      addPart(toTitleCase(cleanSublocalityRepetitions(subloc1)));
    }
    if (locality.isNotEmpty) addPart(toTitleCase(locality), isLocality: true);

    if (parts.isNotEmpty &&
        (streetNumber.isNotEmpty ||
            subpremise.isNotEmpty ||
            premise.isNotEmpty ||
            poi.isNotEmpty ||
            route.isNotEmpty)) {
      return parts.join(', ');
    }

    if (rawFormatted.isNotEmpty && rawFormatted.toLowerCase() != locality.toLowerCase()) {
      return rawFormatted;
    }

    return parts.isNotEmpty
        ? parts.join(', ')
        : (rawFormatted.isNotEmpty ? rawFormatted : (best['formatted_address'] as String? ?? ''));
  }

  String _buildPreciseAddressFromPlacesPlace(
    Map<dynamic, dynamic> place, {
    double? userLat,
    double? userLng,
  }) {
    final rawFormatted = ((place['formattedAddress'] as String?) ?? '')
        .replaceAll(RegExp(r',\s*Pakistan$', caseSensitive: false), '')
        .replaceAll(RegExp(r'^[A-Za-z0-9]{4,8}\+[A-Za-z0-9]{2,5},?\s*'), '')
        .replaceAll(RegExp(r',\s*\d{5}\b'), '')
        .trim();
    final rawDisplayName = place['displayName'] is Map
        ? ((place['displayName']['text'] as String?) ?? '')
        : (place['displayName'] is String ? place['displayName'] as String : '');
    final displayName = rawDisplayName
        .replaceAll(RegExp(r',\s*Pakistan$', caseSensitive: false), '')
        .replaceAll(RegExp(r',\s*Punjab\s*Pakistan$', caseSensitive: false), '')
        .trim();

    final comps = (place['addressComponents'] as List?)?.whereType<Map>().toList() ?? [];
    String getComp(String type) {
      for (final c in comps) {
        final types = (c['types'] as List?)?.map((t) => t.toString()).toList() ?? [];
        if (types.contains(type)) {
          return ((c['longText'] as String?) ?? (c['shortText'] as String?) ?? '').trim();
        }
      }
      return '';
    }

    var streetNumber = getComp('street_number');
    if (RegExp(r'^\d{5}$').hasMatch(streetNumber)) {
      streetNumber = '';
    }
    final subpremise = getComp('subpremise');
    final premise = getComp('premise');
    final landmark = getComp('landmark');
    final poi = getComp('point_of_interest').isNotEmpty
        ? getComp('point_of_interest')
        : getComp('establishment');
    final route = getComp('route');
    final subloc2 = getComp('sublocality_level_2');
    final subloc1 = getComp('sublocality_level_1').isNotEmpty
        ? getComp('sublocality_level_1')
        : (getComp('sublocality').isNotEmpty ? getComp('sublocality') : getComp('neighborhood'));
    var locality = getComp('locality').isNotEmpty
        ? getComp('locality')
        : getComp('administrative_area_level_2');

    // Apply GeoGuard check if coordinates are available
    if (userLat != null && userLng != null) {
      locality = enforceAuthoritativeCity(userLat, userLng, locality);
    } else {
      final locMap = place['location'] as Map?;
      final pLat = (locMap?['latitude'] as num?)?.toDouble() ?? (locMap?['lat'] as num?)?.toDouble();
      final pLng = (locMap?['longitude'] as num?)?.toDouble() ?? (locMap?['lng'] as num?)?.toDouble();
      if (pLat != null && pLng != null) {
        locality = enforceAuthoritativeCity(pLat, pLng, locality);
      }
    }

    // Filter out generic plus code from displayName
    final isNamePlusCode =
        RegExp(r'^[A-Za-z0-9]{4,8}\+[A-Za-z0-9]{2,5}$').hasMatch(displayName.trim());
    final effectiveName = (!isNamePlusCode &&
            displayName.trim().isNotEmpty &&
            displayName.trim().toLowerCase() != locality.toLowerCase() &&
            displayName.trim().toLowerCase() != subloc1.toLowerCase() &&
            (poi.isEmpty || !displayName.toLowerCase().contains(poi.toLowerCase())))
        ? displayName.trim()
        : '';

    final parts = <String>[];
    void addPart(String candidate, {bool isLocality = false}) {
      final clean = candidate.trim();
      if (clean.isEmpty) return;
      if (RegExp(r'^[A-Za-z0-9]{4,8}\+[A-Za-z0-9]{2,5}$').hasMatch(clean)) return;
      final lower = clean.toLowerCase();

      if (isLocality) {
        if (parts.isNotEmpty && parts.last.toLowerCase() == lower) return;
        parts.add(clean);
        return;
      }

      if (parts.any((existing) =>
          existing.toLowerCase() == lower || existing.toLowerCase().contains(lower))) {
        return;
      }
      for (int i = 0; i < parts.length; i++) {
        if (lower.contains(parts[i].toLowerCase())) {
          parts[i] = clean;
          return;
        }
      }
      parts.add(clean);
    }

    if (streetNumber.isNotEmpty) {
      final isPureNum = RegExp(r'^\d+[A-Za-z]?(-[A-Za-z0-9]+)?$').hasMatch(streetNumber);
      final hasPrefix = RegExp(
        r'^(plot|house|shop|flat|suite|unit|street|st|block|sector)\b',
        caseSensitive: false,
      ).hasMatch(streetNumber);
      addPart(isPureNum && !hasPrefix ? 'Plot $streetNumber' : streetNumber);
    }
    if (subpremise.isNotEmpty) {
      final isPureNum = RegExp(r'^\d+[A-Za-z]?$').hasMatch(subpremise);
      addPart(isPureNum ? 'Unit $subpremise' : subpremise);
    }
    if (premise.isNotEmpty) addPart(premise);
    if (poi.isNotEmpty) addPart(poi);
    if (effectiveName.isNotEmpty) addPart(effectiveName);
    if (landmark.isNotEmpty) addPart(landmark);
    String neighborhood = subloc1;
    if (subloc2.isNotEmpty) {
      if (neighborhood.isEmpty) {
        neighborhood = subloc2;
      } else if (!neighborhood.toLowerCase().contains(subloc2.toLowerCase())) {
        neighborhood = '$neighborhood $subloc2';
      }
    }

    if (route.isNotEmpty && route.toLowerCase() != 'block') {
      var cleanRoute = route;
      if (streetNumber.isNotEmpty || premise.isNotEmpty) {
        cleanRoute = cleanRoute.replaceFirst(RegExp(r'^\d+[A-Za-z]?(?:[/-]\d+[A-Za-z]?)?[\s,-]+'), '').trim();
      }
      if (cleanRoute.isNotEmpty) addPart(toTitleCase(cleanRoute));
    }
    if (neighborhood.isNotEmpty) addPart(toTitleCase(cleanSublocalityRepetitions(neighborhood)));
    if (locality.isNotEmpty) addPart(toTitleCase(locality), isLocality: true);

    if (parts.isNotEmpty &&
        (streetNumber.isNotEmpty ||
            subpremise.isNotEmpty ||
            premise.isNotEmpty ||
            effectiveName.isNotEmpty ||
            landmark.isNotEmpty ||
            poi.isNotEmpty ||
            route.isNotEmpty)) {
      return parts.join(', ');
    }

    if (rawFormatted.isNotEmpty && rawFormatted.toLowerCase() != locality.toLowerCase()) {
      return rawFormatted;
    }

    return parts.isNotEmpty ? parts.join(', ') : rawFormatted;
  }

  Future<String?> _fetchPlacesNearbyReverseGeocode(double lat, double lng) async {
    // Single low-latency 250m query with rankPreference: DISTANCE resolves nearest place in <500ms
    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 3);
      final url = Uri.parse('https://places.googleapis.com/v1/places:searchNearby');
      final req = await client.postUrl(url).timeout(const Duration(seconds: 3));
      final apiKey = googleMapsApiKey;
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

      final body = jsonEncode({
        'locationRestriction': {
          'circle': {
            'center': {'latitude': lat, 'longitude': lng},
            'radius': 250.0,
          },
        },
        'rankPreference': 'DISTANCE',
        'maxResultCount': 8,
      });
      req.write(body);
      final resp = await req.close().timeout(const Duration(seconds: 3));
      if (resp.statusCode == 200) {
        final respBody = await resp
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: 3));
        final data = jsonDecode(respBody) as Map<String, dynamic>;
        final places = data['places'] as List?;
        if (places != null && places.isNotEmpty) {
          String? candidate;
          for (final p in places) {
            if (p is Map) {
              final formatted = _buildPreciseAddressFromPlacesPlace(
                p,
                userLat: lat,
                userLng: lng,
              );
              if (formatted.isNotEmpty &&
                  !formatted.toLowerCase().startsWith('location (') &&
                  !formatted.toLowerCase().startsWith('pinned spot')) {
                // If this place is an exact plot, premise, or named establishment, return immediately!
                if (NativeMapService.isGranularAddress(formatted)) {
                  return formatted;
                }
                if (candidate == null && formatted.contains(',')) {
                  candidate = formatted;
                }
              }
            }
          }
          if (candidate != null) {
            return candidate;
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
      final apiKey = googleMapsApiKey;
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
            final builtAddr = _buildPreciseAddressFromPlacesPlace(
              first,
              userLat: resLat,
              userLng: resLng,
            );
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
      final apiKey = googleMapsApiKey;
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json?latlng=$lat,$lng&extra_computations=ADDRESS_DESCRIPTORS&key=$apiKey',
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
        final apiKey = googleMapsApiKey;
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

  /// Exposed for unit testing of Google Geocoding response parsing.
  String buildPrecisePropertyAddressForTest(List<dynamic> results) =>
      _buildPrecisePropertyAddress(results);

  /// Exposed for unit testing of Google Places API (New) response parsing.
  String buildPreciseAddressFromPlacesPlaceForTest(
    Map<dynamic, dynamic> place, {
    double? userLat,
    double? userLng,
  }) =>
      _buildPreciseAddressFromPlacesPlace(place, userLat: userLat, userLng: userLng);

  Future<String> reverseGeocode(double lat, double lng) async {
    // 5 decimal places (~1.1m precision) ensures adjacent plots/houses do not collide in cache
    final cacheKey = '${lat.toStringAsFixed(5)},${lng.toStringAsFixed(5)}';
    final cached = _reverseGeocodeCache[cacheKey];
    if (cached != null &&
        cached.isNotEmpty &&
        !cached.startsWith('Location (') &&
        !cached.startsWith('Pinned Spot')) {
      final sanitized = sanitizeAddressWithGeoGuard(lat, lng, cached);
      final isSingleBroadCity = !sanitized.contains(',') &&
          CoordinateParser.pakistanCities.containsKey(sanitized.toLowerCase().trim());
      if (!isSingleBroadCity) {
        return sanitized;
      }
    }

    String? broadFallback;

    // 1. On iOS & Android, NativeMapService runs the dedicated native geocoding pipeline
    // (Two-Layer Fusion: Google Places searchNearby + Geocoding REST + Roads API + GeoGuard)
    if (Platform.isIOS || Platform.isAndroid) {
      try {
        final detailed = await NativeMapService.instance
            .reverseGeocodeDetailed(lat, lng)
            .timeout(const Duration(milliseconds: 4000));
        if (detailed != null && detailed.formattedAddress.isNotEmpty) {
          final trimmed = detailed.formattedAddress.trim();
          if (detailed.isGranular || NativeMapService.isGranularAddress(trimmed)) {
            _cacheIfGranular(cacheKey, trimmed);
            return trimmed;
          }
          broadFallback = trimmed;
        } else {
          final nativeAddr = await NativeMapService.instance
              .reverseGeocode(lat, lng)
              .timeout(const Duration(milliseconds: 3000));
          if (nativeAddr != null &&
              nativeAddr.trim().isNotEmpty &&
              !nativeAddr.startsWith('Location (') &&
              !nativeAddr.startsWith('Pinned Spot')) {
            final trimmed = nativeAddr.trim();
            if (NativeMapService.isGranularAddress(trimmed)) {
              _cacheIfGranular(cacheKey, trimmed);
              return trimmed;
            }
            broadFallback = trimmed;
          }
        }
      } catch (e) {
        debugPrint('[MapService] Native geocoding error: $e');
      }
    }

    // 2. Direct Official Google Geocoding (Priority 1 for Rooftop Plot & Street Resolver)
    // Queries Geocoding API with extra_computations=ADDRESS_DESCRIPTORS
    try {
      final directGoogle = await _fetchGoogleReverseGeocode(lat, lng)
          .timeout(const Duration(milliseconds: 2500));
      if (directGoogle != null &&
          directGoogle.trim().isNotEmpty &&
          !directGoogle.startsWith('Location (') &&
          !directGoogle.startsWith('Pinned Spot')) {
        final trimmedGoogle = directGoogle.trim();
        // If Google Geocoding returned an exact plot/premise/house number, it takes absolute Priority 1!
        if (NativeMapService.isGranularAddress(trimmedGoogle) &&
            (trimmedGoogle.toLowerCase().contains('plot') ||
                trimmedGoogle.toLowerCase().contains('house') ||
                trimmedGoogle.toLowerCase().contains('unit') ||
                trimmedGoogle.toLowerCase().contains('flat'))) {
          _cacheIfGranular(cacheKey, trimmedGoogle);
          return trimmedGoogle;
        }
        if (NativeMapService.isGranularAddress(trimmedGoogle)) {
          broadFallback ??= trimmedGoogle;
        }
      }
    } catch (_) {}

    // 3. Google Places API (New) Nearby Search
    // Resolves micro-landmarks, named buildings, and geotagged places with progressive radii
    try {
      final nearby = await _fetchPlacesNearbyReverseGeocode(lat, lng)
          .timeout(const Duration(milliseconds: 3200));
      if (nearby != null &&
          nearby.trim().isNotEmpty &&
          !nearby.startsWith('Location (') &&
          !nearby.startsWith('Pinned Spot')) {
        final trimmedNearby = nearby.trim();
        if (NativeMapService.isGranularAddress(trimmedNearby) || trimmedNearby.contains(',')) {
          _cacheIfGranular(cacheKey, trimmedNearby);
          return trimmedNearby;
        }
        broadFallback = trimmedNearby;
      }
    } catch (e) {
      debugPrint('[MapService] Google Places nearby reverseGeocode error: $e');
    }

    // 3. Authenticated Firebase Cloud Functions (with server-side buildPrecisePropertyAddress)
    if (Firebase.apps.isNotEmpty) {
      try {
        final res = await FirebaseFunctions.instance
            .httpsCallable('reverseGeocode')
            .call(<String, dynamic>{
              'latitude': lat,
              'longitude': lng,
              'lat': lat,
              'lng': lng,
            })
            .timeout(const Duration(milliseconds: 3000));
        final address = (res.data['address'] as String?) ??
            (res.data['formattedAddress'] as String?);
        if (address != null &&
            address.trim().isNotEmpty &&
            !address.startsWith('Pinned Spot') &&
            !address.startsWith('Location (')) {
          final trimmed = address.trim();
          _cacheIfGranular(cacheKey, trimmed);
          return trimmed;
        }
      } catch (e) {
        debugPrint('[MapService] Firebase Functions reverseGeocode error: $e');
      }
    }

    // 4. Native OS Geocoder (Android Geocoder) as a fallback layer
    // (On Android, calls NativeLocationService.kt -> android.location.Geocoder)
    if (!Platform.isIOS) {
      try {
        final nativeAddr = await NativeMapService.instance
            .reverseGeocode(lat, lng)
            .timeout(const Duration(milliseconds: 2500));
        if (nativeAddr != null &&
            nativeAddr.trim().isNotEmpty &&
            !nativeAddr.startsWith('Location (') &&
            !nativeAddr.startsWith('Pinned Spot')) {
          final trimmedNative = nativeAddr.trim();
          if (NativeMapService.isGranularAddress(trimmedNative)) {
            _cacheIfGranular(cacheKey, trimmedNative);
            return trimmedNative;
          }
          broadFallback ??= trimmedNative;
        }
      } catch (_) {}
    }

    // 5. OpenStreetMap Nominatim reverse geocode with 3s timeout and bilingual English/Urdu tagging
    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 3);
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=$lat&lon=$lng&zoom=18&addressdetails=1&accept-language=en,ur',
      );
      final req = await client.getUrl(url).timeout(const Duration(seconds: 3));
      req.headers.set('User-Agent', 'SwiftRideApp/1.0 (RideHailing; aliasgharinnocent@yahoo.com)');
      final resp = await req.close().timeout(const Duration(seconds: 3));
      if (resp.statusCode == 200) {
        final body = await resp
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: 3));
        final data = jsonDecode(body) as Map<String, dynamic>;
        final addr = data['address'] as Map<String, dynamic>?;
        if (addr != null) {
          final houseNumber =
              (addr['house_number'] ?? addr['house_name'] ?? '') as String;
          final building =
              (addr['building'] ?? addr['amenity'] ?? addr['shop'] ?? '') as String;
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
              isPureNum ? 'Plot ${houseNumber.trim()}' : houseNumber.trim(),
            );
          }
          if (building.isNotEmpty && !parts.contains(building.trim())) {
            parts.add(building.trim());
          }
          if (road.isNotEmpty) parts.add(road);
          if (neighbourhood.isNotEmpty) parts.add(neighbourhood);
          if (city.isNotEmpty && !parts.contains(city)) parts.add(city);

          if (parts.isNotEmpty) {
            final formatted = parts.join(', ');
            _cacheIfGranular(cacheKey, formatted);
            return formatted;
          }
        }
        final displayName = data['display_name'] as String?;
        if (displayName != null && displayName.isNotEmpty) {
          final segments =
              displayName.split(',').map((s) => s.trim()).take(3).join(', ');
          if (segments.isNotEmpty) {
            _cacheIfGranular(cacheKey, segments);
            return segments;
          }
        }
      }
    } catch (e) {
      debugPrint('[MapService] Nominatim reverseGeocode fallback error: $e');
    } finally {
      client?.close();
    }

    if (broadFallback != null &&
        broadFallback.isNotEmpty &&
        !broadFallback.startsWith('Location (') &&
        !broadFallback.startsWith('Pinned Spot')) {
      if (!NativeMapService.isGranularAddress(broadFallback)) {
        final shortPlus = GeohashUtil.encodePlusCodeShort(lat, lng);
        final anchored = '$shortPlus, $broadFallback';
        _cacheIfGranular(cacheKey, anchored);
        return anchored;
      }
      _cacheIfGranular(cacheKey, broadFallback);
      return broadFallback;
    }

    // 6. ROBUST OFFLINE GEOTAG: High-accuracy locality and Plus Code
    // (Never return raw coordinates or "Location (x, y)")
    final robustOfflineGeotag = CoordinateParser.formatOfflineGeotag(lat, lng);
    return robustOfflineGeotag;
  }

  /// Performs structured reverse geocoding via native platforms.
  Future<NativeGeocodedAddress?> reverseGeocodeDetailed(double lat, double lng) async {
    if (Platform.isIOS || Platform.isAndroid) {
      try {
        final detailed = await NativeMapService.instance.reverseGeocodeDetailed(lat, lng);
        if (detailed != null && detailed.formattedAddress.isNotEmpty) {
          final sanitized = sanitizeAddressWithGeoGuard(lat, lng, detailed.formattedAddress);
          return NativeGeocodedAddress(
            formattedAddress: sanitized,
            title: detailed.title,
            subtitle: detailed.subtitle,
            plotNumber: detailed.plotNumber,
            street: detailed.street,
            neighborhood: detailed.neighborhood,
            city: enforceAuthoritativeCity(lat, lng, detailed.city),
            provider: detailed.provider,
            isGranular: detailed.isGranular,
            confidence: detailed.confidence,
            distanceMeters: detailed.distanceMeters,
            quarantinedCity: detailed.quarantinedCity,
          );
        }
      } catch (_) {}
    }
    final formatted = await reverseGeocode(lat, lng);
    return NativeGeocodedAddress(
      formattedAddress: formatted,
      title: formatted,
      city: enforceAuthoritativeCity(lat, lng, null),
      isGranular: NativeMapService.isGranularAddress(formatted),
    );
  }

  /// Snaps off-road/indoor pins to the nearest drivable road segment using Google Roads API.
  /// Resolves the approach street name via reverse geocoding placeId if available.
  Future<({double lat, double lng, String? roadName})?> snapToNearestRoad(
    double lat,
    double lng,
  ) async {
    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = const Duration(milliseconds: 2500);
      final apiKey = googleMapsApiKey;
      final url = Uri.parse(
        'https://roads.googleapis.com/v1/nearestRoads?points=$lat,$lng&key=$apiKey',
      );
      final req = await client.getUrl(url).timeout(const Duration(milliseconds: 2500));
      if (Platform.isIOS) {
        req.headers.set('X-Ios-Bundle-Identifier', 'com.dartnexuslab.swiftride');
      } else if (Platform.isAndroid) {
        req.headers.set('X-Android-Package', 'com.dartnexuslab.swiftride');
      }
      final resp = await req.close().timeout(const Duration(milliseconds: 2500));
      if (resp.statusCode == 200) {
        final body = await resp.transform(utf8.decoder).join();
        final data = jsonDecode(body) as Map<String, dynamic>;
        final points = data['snappedPoints'] as List?;
        if (points != null && points.isNotEmpty) {
          final first = points.first as Map<String, dynamic>;
          final loc = first['location'] as Map<String, dynamic>?;
          final sLat = (loc?['latitude'] as num?)?.toDouble() ?? lat;
          final sLng = (loc?['longitude'] as num?)?.toDouble() ?? lng;
          final placeId = first['placeId'] as String?;

          String? roadName;
          if (placeId != null && placeId.isNotEmpty) {
            roadName = await _fetchRoadNameFromPlaceId(placeId);
          }

          return (lat: sLat, lng: sLng, roadName: roadName);
        }
      }
    } catch (e) {
      debugPrint('[MapService] Roads API nearestRoads error: $e');
    } finally {
      client?.close();
    }
    return null;
  }

  Future<String?> _fetchRoadNameFromPlaceId(String placeId) async {
    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = const Duration(milliseconds: 2000);
      final apiKey = googleMapsApiKey;
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json?place_id=$placeId&key=$apiKey',
      );
      final req = await client.getUrl(url).timeout(const Duration(milliseconds: 2000));
      if (Platform.isIOS) {
        req.headers.set('X-Ios-Bundle-Identifier', 'com.dartnexuslab.swiftride');
      } else if (Platform.isAndroid) {
        req.headers.set('X-Android-Package', 'com.dartnexuslab.swiftride');
      }
      final resp = await req.close().timeout(const Duration(milliseconds: 2000));
      if (resp.statusCode == 200) {
        final body = await resp.transform(utf8.decoder).join();
        final data = jsonDecode(body) as Map<String, dynamic>;
        final results = data['results'] as List?;
        if (results != null && results.isNotEmpty) {
          final first = results.first as Map;
          final comps = (first['address_components'] as List?)?.whereType<Map>().toList() ?? [];
          for (final c in comps) {
            final types = (c['types'] as List?)?.map((t) => t.toString()).toList() ?? [];
            if (types.contains('route')) {
              final name = ((c['long_name'] as String?) ?? (c['short_name'] as String?) ?? '').trim();
              if (name.isNotEmpty) return name;
            }
          }
        }
      }
    } catch (_) {
    } finally {
      client?.close();
    }
    return null;
  }

  /// Snaps active vehicle breadcrumb GPS traces to the physical road network using Google Roads API.
  /// Automatically interpolates missing geometry and enforces the 100-point API limit.
  Future<List<LatLng>> snapBreadcrumbsToRoads(List<LatLng> rawPoints) async {
    if (rawPoints.length < 2) return rawPoints;

    // Google Roads API enforces a maximum of 100 points per request
    final cappedPoints = rawPoints.length > 100 ? rawPoints.sublist(rawPoints.length - 100) : rawPoints;
    final pathParam = cappedPoints.map((p) => '${p.latitude},${p.longitude}').join('|');

    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = const Duration(milliseconds: 3500);
      final apiKey = googleMapsApiKey;
      final url = Uri.parse(
        'https://roads.googleapis.com/v1/snapToRoads?path=$pathParam&interpolate=true&key=$apiKey',
      );
      final req = await client.getUrl(url).timeout(const Duration(milliseconds: 3500));
      if (Platform.isIOS) {
        req.headers.set('X-Ios-Bundle-Identifier', 'com.dartnexuslab.swiftride');
      } else if (Platform.isAndroid) {
        req.headers.set('X-Android-Package', 'com.dartnexuslab.swiftride');
      }
      final resp = await req.close().timeout(const Duration(milliseconds: 3500));
      if (resp.statusCode == 200) {
        final body = await resp.transform(utf8.decoder).join();
        final data = jsonDecode(body) as Map<String, dynamic>;
        final points = data['snappedPoints'] as List?;
        if (points != null && points.isNotEmpty) {
          final snapped = <LatLng>[];
          for (final p in points) {
            if (p is Map) {
              final loc = p['location'] as Map?;
              final pLat = (loc?['latitude'] as num?)?.toDouble();
              final pLng = (loc?['longitude'] as num?)?.toDouble();
              if (pLat != null && pLng != null) {
                snapped.add(LatLng(pLat, pLng));
              }
            }
          }
          if (snapped.isNotEmpty) {
            return snapped;
          }
        }
      }
    } catch (e) {
      debugPrint('[MapService] Roads API snapToRoads error: $e');
    } finally {
      client?.close();
    }
    return rawPoints;
  }

  /// Normalizes user-typed destination text using Google Address Validation API.
  /// Only adopts validated corrections if granularity is PREMISE/SUB_PREMISE and passes GeoGuard.
  /// Returns null for unsupported regions (e.g. PK) or low-confidence results as non-blocking pass-through.
  Future<ValidatedAddressResult?> validateAddress(
    String rawAddress, {
    String regionCode = 'PK',
    double? nearLat,
    double? nearLng,
  }) async {
    final clean = rawAddress.trim();
    if (clean.isEmpty) return null;

    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = const Duration(milliseconds: 2500);
      final apiKey = googleMapsApiKey;
      final url = Uri.parse(
        'https://addressvalidation.googleapis.com/v1:validateAddress?key=$apiKey',
      );
      final req = await client.postUrl(url).timeout(const Duration(milliseconds: 2500));
      req.headers.set('Content-Type', 'application/json');
      if (Platform.isIOS) {
        req.headers.set('X-Ios-Bundle-Identifier', 'com.dartnexuslab.swiftride');
      } else if (Platform.isAndroid) {
        req.headers.set('X-Android-Package', 'com.dartnexuslab.swiftride');
      }

      final body = jsonEncode({
        'address': {
          'regionCode': regionCode,
          'addressLines': [clean],
        },
      });
      req.write(body);

      final resp = await req.close().timeout(const Duration(milliseconds: 2500));
      if (resp.statusCode == 200) {
        final respBody = await resp.transform(utf8.decoder).join();
        final data = jsonDecode(respBody) as Map<String, dynamic>;
        final result = data['result'] as Map<String, dynamic>?;
        final verdict = result?['verdict'] as Map<String, dynamic>?;
        final granularity = (verdict?['validationGranularity'] as String?) ?? '';
        final isComplete = (verdict?['addressComplete'] as bool?) ?? false;

        // Only adopt if granularity is exact property-level (PREMISE or SUB_PREMISE)
        if (granularity == 'PREMISE' || granularity == 'SUB_PREMISE') {
          final addressObj = result?['address'] as Map<String, dynamic>?;
          final formatted = (addressObj?['formattedAddress'] as String?) ?? '';
          final geocode = result?['geocode'] as Map<String, dynamic>?;
          final location = geocode?['location'] as Map<String, dynamic>?;
          final vLat = (location?['latitude'] as num?)?.toDouble();
          final vLng = (location?['longitude'] as num?)?.toDouble();

          // GeoGuard distance gate: verify within 45km of user location
          if (nearLat != null && nearLng != null && vLat != null && vLng != null) {
            final distKm = DistanceCalculator.haversineDistance(nearLat, nearLng, vLat, vLng);
            if (distKm > 45.0) {
              debugPrint('[MapService][AddressValidation] Quarantined distant result ($distKm km away)');
              return null;
            }
          }

          if (formatted.isNotEmpty) {
            return ValidatedAddressResult(
              formattedAddress: formatted,
              granularity: granularity,
              isComplete: isComplete,
              coordinates: vLat != null && vLng != null ? LatLng(vLat, vLng) : null,
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[MapService] Address Validation API error: $e');
    } finally {
      client?.close();
    }
    // Non-blocking pass-through
    return null;
  }

  /// Map pan reverse geocoding with native cancellation of superseded tasks.
  Future<String> panReverseGeocode(double lat, double lng) async {
    if (Platform.isIOS) {
      try {
        final detailed = await NativeMapService.instance.panReverseGeocode(lat, lng);
        if (detailed != null && detailed.formattedAddress.isNotEmpty) {
          return detailed.formattedAddress;
        }
      } catch (_) {}
    }
    return reverseGeocode(lat, lng);
  }

  // List of known Pakistani cities to detect external city intent
  static const Set<String> _knownPakistaniCities = {
    'lahore',
    'faisalabad',
    'toba tek singh',
    'chiniot',
    'sargodha',
    'multan',
    'islamabad',
    'rawalpindi',
    'karachi',
    'peshawar',
    'quetta',
    'gujranwala',
    'sialkot',
    'bahawalpur',
    'sukkur',
    'hyderabad',
    'bhakkar',
    'mianwali',
    'khushab',
    'rajanpur',
    'okara',
    'sahiwal',
    'sheikhupura',
    'kasur',
    'jhelum',
    'attock',
    'chakwal',
    'mardan',
    'abbottabad',
    'murree',
    'gilgit',
    'skardu',
    'shorkot',
    'ahmadpur sial',
    'athara hazari',
    'jhang',
  };

  /// Builds a Google Maps-style proximity & intent scoped search query.
  /// 
  /// 1. Checks if the query explicitly mentions an external Pakistani city.
  ///    If yes: expands bias radius to 50,000m and does not lock to `currentCity`.
  /// 2. Detects house / plot / street number queries:
  ///    If no explicit area is mentioned in the query:
  ///      Appends `, <currentArea>, <currentCity>` and tightens radius to 2,500m.
  ///    If an area keyword is present in the query:
  ///      Appends `, <currentCity>` and uses 15,000m radius.
  /// 3. Otherwise (generic search within current city):
  ///    Appends `, <currentCity>` for text search / biases with 15,000m radius.
  static ScopedSearchQuery buildScopedSearchQuery(
    String query, {
    String? currentCity,
    String? currentArea,
  }) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return ScopedSearchQuery(
        rawQuery: query,
        scopedQuery: query,
        radiusMeters: 15000.0,
      );
    }

    final lower = trimmed.toLowerCase();
    final effectiveCity = (currentCity != null && currentCity.trim().isNotEmpty)
        ? currentCity.trim()
        : 'Jhang';
    final effectiveArea = (currentArea != null && currentArea.trim().isNotEmpty)
        ? currentArea.trim()
        : '';

    // Check if user explicitly mentioned a known city other than current city
    String? detectedExternalCity;
    for (final city in _knownPakistaniCities) {
      final cityPattern = RegExp(r'\b' + RegExp.escape(city) + r'\b', caseSensitive: false);
      if (cityPattern.hasMatch(lower)) {
        if (city.toLowerCase() != effectiveCity.toLowerCase()) {
          detectedExternalCity = city;
          break;
        }
      }
    }

    if (detectedExternalCity != null) {
      // User is explicitly searching outside current city (e.g. "Hospital Faisalabad")
      return ScopedSearchQuery(
        rawQuery: trimmed,
        scopedQuery: trimmed,
        radiusMeters: 50000.0,
        isCityLocked: false,
        isAreaLocked: false,
        targetCity: detectedExternalCity,
      );
    }

    // Check if query is a house / plot / unit / street pattern
    // Examples: "Plot 757 A", "House 12", "Street 4", "H# 15", "123 Main St", "14-B"
    final hasHousePlotPrefix = RegExp(
      r'\b(house|plot|flat|shop|office|street|st|gali|h|p|#)\s*[-#:]?\s*\d+[a-z0-9/-]*\b',
      caseSensitive: false,
    ).hasMatch(lower);
    final hasLeadingNumber = RegExp(
      r'^\d+[a-z/-]*\b',
      caseSensitive: false,
    ).hasMatch(lower);
    final isHouseOrPlotQuery = hasHousePlotPrefix || hasLeadingNumber;

    // Check if query mentions an area/neighborhood/sector keyword
    final hasAreaKeyword = RegExp(
      r'\b(town|block|sector|phase|colony|mohalla|mohallah|lines|sadar|saddar|bazar|bazaar|chowk|road|scheme|society|garden|abad|pura|nagar|cantt|city|market)\b',
      caseSensitive: false,
    ).hasMatch(lower);

    if (isHouseOrPlotQuery) {
      if (!hasAreaKeyword && effectiveArea.isNotEmpty) {
        // Tight neighborhood lock: House/Plot query without area -> append current neighborhood and city
        final scoped = '$trimmed, $effectiveArea, $effectiveCity';
        return ScopedSearchQuery(
          rawQuery: trimmed,
          scopedQuery: scoped,
          radiusMeters: 2500.0,
          isCityLocked: true,
          isAreaLocked: true,
          targetCity: effectiveCity,
          targetArea: effectiveArea,
        );
      } else {
        // Area is either already in query or not available -> append city
        final scoped = lower.contains(effectiveCity.toLowerCase())
            ? trimmed
            : '$trimmed, $effectiveCity';
        return ScopedSearchQuery(
          rawQuery: trimmed,
          scopedQuery: scoped,
          radiusMeters: 15000.0,
          isCityLocked: true,
          isAreaLocked: false,
          targetCity: effectiveCity,
        );
      }
    }

    // General query (e.g. "Civil Hospital", "Main Bazaar")
    final scoped = lower.contains(effectiveCity.toLowerCase())
        ? trimmed
        : '$trimmed, $effectiveCity';
    return ScopedSearchQuery(
      rawQuery: trimmed,
      scopedQuery: scoped,
      radiusMeters: 15000.0,
      isCityLocked: true,
      isAreaLocked: false,
      targetCity: effectiveCity,
    );
  }

  Future<List<PlaceSuggestion>> searchPlaces(
    String query, {
    LatLng? near,
    String? currentCity,
    String? currentArea,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final scoped = buildScopedSearchQuery(
      trimmed,
      currentCity: currentCity,
      currentArea: currentArea,
    );

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
          : (parsed.label ?? CoordinateParser.formatOfflineGeotag(parsed.latitude, parsed.longitude));
      final coords = exact?.coordinates ?? LatLng(parsed.latitude, parsed.longitude);

      final pinnedItem = PlaceSuggestion(
        placeId:
            'pinned:${coords.latitude},${coords.longitude}:$fullAddress',
        mainText: fullAddress,
        secondaryText:
            'Coordinates: ${coords.latitude.toStringAsFixed(5)}, ${coords.longitude.toStringAsFixed(5)}',
        coordinates: coords,
      );

      final remote = await _fetchAutocomplete(
        scoped,
        near,
        currentCity: currentCity,
        currentArea: currentArea,
      );
      return [pinnedItem, ...remote];
    }

    return await _fetchAutocomplete(
      scoped,
      near,
      currentCity: currentCity,
      currentArea: currentArea,
    );
  }

  Future<List<PlaceSuggestion>> _fetchAutocomplete(
    ScopedSearchQuery scoped,
    LatLng? near, {
    String? currentCity,
    String? currentArea,
  }) async {
    // 1. Google Places API (New) Autocomplete
    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = const Duration(milliseconds: 2500);
      final url = Uri.parse('https://places.googleapis.com/v1/places:autocomplete');
      final req = await client.postUrl(url).timeout(const Duration(milliseconds: 2500));
      final apiKey = googleMapsApiKey;
      req.headers.set('Content-Type', 'application/json');
      req.headers.set('X-Goog-Api-Key', apiKey);
      if (Platform.isIOS) {
        req.headers.set('X-Ios-Bundle-Identifier', 'com.dartnexuslab.swiftride');
      } else if (Platform.isAndroid) {
        req.headers.set('X-Android-Package', 'com.dartnexuslab.swiftride');
      }

      // Pass user's raw query into Autocomplete input so suggestions feel natural,
      // or scoped query if it includes neighborhood anchor.
      final reqData = <String, dynamic>{
        'input': scoped.isAreaLocked ? scoped.scopedQuery : scoped.rawQuery,
        'includedRegionCodes': ['pk'],
      };
      if (near != null) {
        reqData['locationBias'] = {
          'circle': {
            'center': {'latitude': near.latitude, 'longitude': near.longitude},
            'radius': scoped.radiusMeters,
          },
        };
      }
      req.write(jsonEncode(reqData));
      final resp = await req.close().timeout(const Duration(milliseconds: 2500));
      if (resp.statusCode == 200) {
        final respBody = await resp
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(milliseconds: 2500));
        final data = jsonDecode(respBody) as Map<String, dynamic>;
        final suggestions = data['suggestions'] as List?;
        if (suggestions != null && suggestions.isNotEmpty) {
          final list = <PlaceSuggestion>[];
          for (final s in suggestions) {
            if (s is Map && s['placePrediction'] is Map) {
              final pred = s['placePrediction'] as Map;
              final rawPlaceId = (pred['placeId'] as String?) ??
                  ((pred['place'] as String?)?.replaceFirst('places/', '')) ??
                  '';
              final sf = pred['structuredFormat'] as Map?;
              final mainText = (sf?['mainText']?['text'] as String?) ??
                  (pred['text']?['text'] as String?) ??
                  '';
              var secondaryText = (sf?['secondaryText']?['text'] as String?) ?? '';
              secondaryText = secondaryText
                  .replaceAll(RegExp(r',\s*Pakistan$', caseSensitive: false), '')
                  .trim();
              if (rawPlaceId.isNotEmpty && mainText.isNotEmpty) {
                list.add(
                  PlaceSuggestion(
                    placeId: rawPlaceId,
                    mainText: mainText,
                    secondaryText: secondaryText,
                  ),
                );
              }
            }
          }
          if (list.isNotEmpty) return list;
        }
      }
    } catch (e) {
      debugPrint('[MapService] Places API New autocomplete error: $e');
    } finally {
      client?.close();
    }

    // 2. Google Places API (New) Text Search fallback
    try {
      client = HttpClient();
      client.connectionTimeout = const Duration(milliseconds: 2500);
      final url = Uri.parse('https://places.googleapis.com/v1/places:searchText');
      final req = await client.postUrl(url).timeout(const Duration(milliseconds: 2500));
      final apiKey = googleMapsApiKey;
      req.headers.set('Content-Type', 'application/json');
      req.headers.set('X-Goog-Api-Key', apiKey);
      req.headers.set(
        'X-Goog-FieldMask',
        'places.id,places.displayName,places.formattedAddress,places.location',
      );
      if (Platform.isIOS) {
        req.headers.set('X-Ios-Bundle-Identifier', 'com.dartnexuslab.swiftride');
      } else if (Platform.isAndroid) {
        req.headers.set('X-Android-Package', 'com.dartnexuslab.swiftride');
      }
      final reqData = <String, dynamic>{'textQuery': scoped.scopedQuery};
      if (near != null) {
        reqData['locationBias'] = {
          'circle': {
            'center': {'latitude': near.latitude, 'longitude': near.longitude},
            'radius': scoped.radiusMeters,
          },
        };
      }
      req.write(jsonEncode(reqData));
      final resp = await req.close().timeout(const Duration(milliseconds: 2500));
      if (resp.statusCode == 200) {
        final respBody = await resp
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(milliseconds: 2500));
        final data = jsonDecode(respBody) as Map<String, dynamic>;
        final places = data['places'] as List?;
        if (places != null && places.isNotEmpty) {
          final list = <PlaceSuggestion>[];
          for (final p in places) {
            if (p is Map) {
              final id = (p['id'] as String?) ?? '';
              final name = (p['displayName']?['text'] as String?) ?? '';
              final formatted = ((p['formattedAddress'] as String?) ?? '')
                  .replaceAll(RegExp(r',\s*Pakistan$', caseSensitive: false), '')
                  .trim();
              final loc = p['location'] as Map?;
              final lat = (loc?['latitude'] as num?)?.toDouble();
              final lng = (loc?['longitude'] as num?)?.toDouble();
              if (name.isNotEmpty) {
                list.add(
                  PlaceSuggestion(
                    placeId: id.isNotEmpty
                        ? id
                        : (lat != null && lng != null ? 'pinned:$lat,$lng:$name' : ''),
                    mainText: name,
                    secondaryText: formatted
                        .replaceAll(name, '')
                        .replaceFirst(RegExp(r'^,\s*'), '')
                        .trim(),
                    coordinates: lat != null && lng != null ? LatLng(lat, lng) : null,
                  ),
                );
              }
            }
          }
          if (list.isNotEmpty) return list;
        }
      }
    } catch (e) {
      debugPrint('[MapService] Places API New searchText error: $e');
    } finally {
      client?.close();
    }

    // 3. Fallback: Firebase Functions
    try {
      if (Firebase.apps.isNotEmpty) {
        final res = await FirebaseFunctions.instance
            .httpsCallable('getAutocomplete')
            .call(<String, dynamic>{
              'query': scoped.rawQuery,
              'currentCity': currentCity,
              'currentArea': currentArea,
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

    // 2. Direct Google Places API (New) Place Details
    HttpClient? client;
    try {
      final cleanId = placeId.replaceFirst('places/', '');
      client = HttpClient();
      client.connectionTimeout = const Duration(milliseconds: 2500);
      final url = Uri.parse('https://places.googleapis.com/v1/places/$cleanId');
      final req = await client.getUrl(url).timeout(const Duration(milliseconds: 2500));
      final apiKey = googleMapsApiKey;
      req.headers.set('X-Goog-Api-Key', apiKey);
      req.headers.set('X-Goog-FieldMask', 'location');
      if (Platform.isIOS) {
        req.headers.set('X-Ios-Bundle-Identifier', 'com.dartnexuslab.swiftride');
      } else if (Platform.isAndroid) {
        req.headers.set('X-Android-Package', 'com.dartnexuslab.swiftride');
      }
      final resp = await req.close().timeout(const Duration(milliseconds: 2500));
      if (resp.statusCode == 200) {
        final body = await resp
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(milliseconds: 2500));
        final data = jsonDecode(body) as Map<String, dynamic>;
        final loc = data['location'] as Map?;
        final lat = (loc?['latitude'] as num?)?.toDouble();
        final lng = (loc?['longitude'] as num?)?.toDouble();
        if (lat != null && lng != null) {
          return LatLng(lat, lng);
        }
      }
    } catch (e) {
      debugPrint('[MapService] Direct Places API place details error: $e');
    } finally {
      client?.close();
    }

    // 3. Fallback: Resolve Google Place ID via Cloud Functions
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
    // 1. First try Cloud Function with responsive 3.5s timeout
    try {
      final plan = await _fetchRouteFromCloudFunction(origin, destination)
          .timeout(const Duration(milliseconds: 3500));
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

    // 2. High-precision OpenStreetMap / OSRM Road Router
    // Strictly adheres to drivable road networks, gives full road geometry without straight-line shortcuts
    try {
      debugPrint('[MapService] Querying open road network (OSRM) for road-following directions');
      final osrmPlan = await _fetchRouteFromOsrm(origin, destination)
          .timeout(const Duration(seconds: 4));
      if (osrmPlan != null && osrmPlan.routes.isNotEmpty) {
        return RoutePlan(
          routes: _enrichRoutes(osrmPlan.routes),
          defaultIndex: osrmPlan.defaultIndex,
        );
      }
    } catch (e) {
      debugPrint('[MapService] OSRM road router error/timeout: $e');
    }

    // 3. Direct Google Routes API v2 fallback with responsive 3.5s timeout
    try {
      debugPrint('[MapService] Querying direct Google Routes API v2 for detailed directions');
      final directPlan = await _fetchRouteDirect(origin, destination)
          .timeout(const Duration(milliseconds: 3500));
      if (directPlan != null && directPlan.routes.isNotEmpty) {
        return RoutePlan(
          routes: _enrichRoutes(directPlan.routes),
          defaultIndex: directPlan.defaultIndex,
        );
      }
    } catch (e) {
      debugPrint('[MapService] Direct Google Routes API v2 error/timeout: $e');
    }

    // 4. OFFLINE / POOR NETWORK FALLBACK: Return cardinal street-grid estimated route
    // so the app NEVER hangs, freezes, or draws diagonal cuts across buildings.
    return _generateOfflineFallbackRoute(origin, destination);
  }

  /// High-precision, zero-key road routing powered by OpenStreetMap / OSRM.
  /// Guarantees that every coordinate along the path follows actual drivable streets.
  Future<RoutePlan?> _fetchRouteFromOsrm(
    LatLng origin,
    LatLng destination,
  ) async {
    final endpoints = [
      'https://router.project-osrm.org/route/v1/driving/${origin.longitude},${origin.latitude};${destination.longitude},${destination.latitude}?overview=full&geometries=polyline&steps=true&alternatives=true',
      'https://routing.openstreetmap.de/routed-car/route/v1/driving/${origin.longitude},${origin.latitude};${destination.longitude},${destination.latitude}?overview=full&geometries=polyline&steps=true&alternatives=true',
    ];

    for (final endpoint in endpoints) {
      HttpClient? client;
      try {
        client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 3);
        final req = await client.getUrl(Uri.parse(endpoint)).timeout(const Duration(seconds: 3));
        req.headers.set('User-Agent', 'SwiftRideApp/1.0 (RideHailing; aliasgharinnocent@yahoo.com)');
        final resp = await req.close().timeout(const Duration(seconds: 3));
        if (resp.statusCode != 200) continue;

        final body = await resp
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: 3));
        final data = jsonDecode(body) as Map<String, dynamic>;
        if (data['code'] != 'Ok') continue;

        final rawRoutes = data['routes'] as List?;
        if (rawRoutes == null || rawRoutes.isEmpty) continue;

        final routes = <RouteOption>[];
        for (var i = 0; i < rawRoutes.length; i++) {
          final r = rawRoutes[i] as Map<String, dynamic>;
          final poly = (r['geometry'] as String?) ?? '';
          final points = poly.isNotEmpty ? decodePolyline(poly) : <LatLng>[];
          if (points.length < 2) continue;

          final distMeters = (r['distance'] as num?)?.toDouble() ?? 0.0;
          final distKm = (distMeters / 1000.0 * 10).round() / 10.0;
          final durSec = (r['duration'] as num?)?.toDouble() ?? 0.0;
          final durMin = (durSec / 60.0 * 10).round() / 10.0;

          // Standard 2% platform fee economics
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

          // Extract detailed step navigation along streets
          final steps = <RouteStep>[];
          final rawLegs = r['legs'] as List? ?? [];
          for (final leg in rawLegs) {
            final legSteps = leg['steps'] as List? ?? [];
            for (final s in legSteps) {
              if (s is Map) {
                final sDistMeters = (s['distance'] as num?)?.round() ?? 0;
                final sDistKm = (sDistMeters / 1000.0 * 10).round() / 10.0;
                final sDurSec = (s['duration'] as num?)?.toDouble() ?? 0.0;
                final sDurMin = (sDurSec / 60.0 * 10).round() / 10.0;
                final streetName = (s['name'] as String?)?.trim() ?? '';
                final mMap = s['maneuver'] as Map? ?? {};
                final mType = (mMap['type'] as String?)?.toLowerCase() ?? '';
                final mMod = (mMap['modifier'] as String?)?.toLowerCase() ?? '';

                String maneuverCode = 'STRAIGHT';
                if (mType == 'depart') {
                  maneuverCode = 'DEPART';
                } else if (mType == 'arrive') {
                  maneuverCode = 'ARRIVE';
                } else if (mMod.contains('left')) {
                  maneuverCode = mMod.contains('slight')
                      ? 'TURN_SLIGHT_LEFT'
                      : (mMod.contains('sharp') ? 'TURN_SHARP_LEFT' : 'TURN_LEFT');
                } else if (mMod.contains('right')) {
                  maneuverCode = mMod.contains('slight')
                      ? 'TURN_SLIGHT_RIGHT'
                      : (mMod.contains('sharp') ? 'TURN_SHARP_RIGHT' : 'TURN_RIGHT');
                } else if (mMod.contains('uturn')) {
                  maneuverCode = 'U_TURN';
                } else if (mType == 'roundabout') {
                  maneuverCode = 'ROUNDABOUT';
                }

                String instruction;
                if (mType == 'depart') {
                  instruction = streetName.isNotEmpty
                      ? 'Head out on $streetName'
                      : 'Proceed toward destination';
                } else if (mType == 'arrive') {
                  instruction = 'Arrive at destination';
                } else {
                  final action = maneuverCode.replaceAll('_', ' ').toLowerCase();
                  instruction = streetName.isNotEmpty
                      ? '$action onto $streetName'
                      : action;
                }

                LatLng? startLoc;
                final locList = mMap['location'] as List?;
                if (locList != null && locList.length >= 2) {
                  final lon = (locList[0] as num).toDouble();
                  final lat = (locList[1] as num).toDouble();
                  startLoc = LatLng(lat, lon);
                }

                steps.add(
                  RouteStep(
                    maneuver: maneuverCode,
                    instruction: instruction,
                    primaryInstruction: instruction,
                    secondaryInstruction: streetName.isNotEmpty ? streetName : null,
                    distanceKm: sDistKm,
                    distanceMeters: sDistMeters,
                    distanceText: sDistKm >= 1.0
                        ? '${sDistKm.toStringAsFixed(1)} km'
                        : '$sDistMeters m',
                    durationMin: sDurMin,
                    durationText: '${sDurMin.ceil()} mins',
                    roadName: streetName.isNotEmpty ? streetName : null,
                    startLocation: startLoc,
                    encodedPolyline: s['geometry'] as String?,
                  ),
                );
              }
            }
          }

          final summary = steps.isNotEmpty && steps.first.roadName != null
              ? 'Via ${steps.first.roadName}'
              : 'Via city road network';

          routes.add(
            RouteOption(
              id: 'osrm_route_$i',
              polylinePoints: points,
              distanceKm: distKm,
              durationMin: durMin,
              staticDurationMin: durMin,
              summary: summary,
              labels: i == 0 ? ['FASTEST', 'ROAD_NAV'] : ['ALTERNATIVE'],
              trafficLevel: 'NORMAL',
              trafficIntervals: const [],
              steps: steps,
              economics: economics,
            ),
          );
        }

        if (routes.isNotEmpty) {
          debugPrint('[MapService] Successfully retrieved ${routes.length} road-only routes from OSRM');
          return RoutePlan(routes: routes, defaultIndex: 0);
        }
      } catch (e) {
        debugPrint('[MapService] OSRM router query error for $endpoint: $e');
      } finally {
        client?.close();
      }
    }
    return null;
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

    // Multi-point cardinal street-grid interpolation (Manhattan alignment)
    // Avoids drawing diagonal straight cuts across buildings, fields, or water bodies
    final dLat = destination.latitude - origin.latitude;
    final dLng = destination.longitude - origin.longitude;
    final mid1 = LatLng(origin.latitude + dLat * 0.35, origin.longitude);
    final mid2 = LatLng(origin.latitude + dLat * 0.5, origin.longitude + dLng * 0.5);
    final mid3 = LatLng(origin.latitude + dLat * 0.65, destination.longitude);
    final gridPoints = <LatLng>[origin, mid1, mid2, mid3, destination];

    final route = RouteOption(
      id: 'offline_fallback_route',
      polylinePoints: gridPoints,
      distanceKm: distKm,
      durationMin: durMin,
      staticDurationMin: durMin,
      summary: 'Estimated street route',
      labels: ['ESTIMATED'],
      trafficLevel: 'NORMAL',
      trafficIntervals: const [],
      steps: [
        RouteStep(
          maneuver: 'STRAIGHT',
          instruction: 'Proceed toward destination along street network',
          primaryInstruction: 'Proceed toward destination along street network',
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

      final apiKey = googleMapsApiKey;
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
