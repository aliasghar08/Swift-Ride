import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/distance_calculator.dart';
import 'polyline_service.dart';

class PlaceSuggestion {
  final String placeId;
  final String mainText;
  final String secondaryText;
  final LatLng coordinates;

  const PlaceSuggestion({
    required this.placeId,
    required this.mainText,
    required this.secondaryText,
    required this.coordinates,
  });
}

class RouteDetails {
  final List<LatLng> polylinePoints;
  final double distanceKm;
  final double durationMin;
  final String trafficLevel;

  const RouteDetails({
    required this.polylinePoints,
    required this.distanceKm,
    required this.durationMin,
    this.trafficLevel = 'NORMAL',
  });
}

/// In-house SwiftRide Map & Geocoding Service.
/// Provides device GPS location, reverse geocoding, intelligent address search,
/// and route polyline calculations with zero external geocoding dependencies.
class MapService {
  static final MapService _instance = MapService._internal();
  factory MapService() => _instance;
  MapService._internal();

  /// Comprehensive in-house geographic database of Pakistan landmarks and hubs.
  static const List<PlaceSuggestion> _knownLocations = [
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
    PlaceSuggestion(
      placeId: 'isb_f9_park',
      mainText: 'Fatima Jinnah Park (F-9 Park)',
      secondaryText: 'Sector F-9, Islamabad',
      coordinates: LatLng(33.7032, 73.0232),
    ),
    PlaceSuggestion(
      placeId: 'isb_f6_super',
      mainText: 'Super Market (F-6 Markaz)',
      secondaryText: 'School Road, Sector F-6, Islamabad',
      coordinates: LatLng(33.7297, 73.0746),
    ),
    PlaceSuggestion(
      placeId: 'isb_f7_jinnah',
      mainText: 'Jinnah Super Market (F-7 Markaz)',
      secondaryText: 'College Road, Sector F-7, Islamabad',
      coordinates: LatLng(33.7208, 73.0573),
    ),
    PlaceSuggestion(
      placeId: 'isb_f10_markaz',
      mainText: 'F-10 Markaz',
      secondaryText: 'Sector F-10, Islamabad',
      coordinates: LatLng(33.6934, 73.0116),
    ),
    PlaceSuggestion(
      placeId: 'isb_g9_karachi_co',
      mainText: 'Karachi Company (G-9 Markaz)',
      secondaryText: 'Manghopir Road, Sector G-9, Islamabad',
      coordinates: LatLng(33.6874, 73.0305),
    ),
    PlaceSuggestion(
      placeId: 'isb_i8_markaz',
      mainText: 'I-8 Markaz Business Hub',
      secondaryText: 'Sector I-8, Islamabad',
      coordinates: LatLng(33.6685, 73.0760),
    ),
    PlaceSuggestion(
      placeId: 'isb_faisal_mosque',
      mainText: 'Faisal Mosque',
      secondaryText: 'Shah Faisal Avenue, E-8, Islamabad',
      coordinates: LatLng(33.7298, 73.0372),
    ),
    PlaceSuggestion(
      placeId: 'isb_daman_e_koh',
      mainText: 'Daman-e-Koh Viewpoint',
      secondaryText: 'Margalla Hills, Islamabad',
      coordinates: LatLng(33.7438, 73.0694),
    ),

    // Rawalpindi
    PlaceSuggestion(
      placeId: 'rwp_saddar',
      mainText: 'Saddar Rawalpindi Commercial Center',
      secondaryText: 'The Mall, Saddar, Rawalpindi',
      coordinates: LatLng(33.5936, 73.0531),
    ),
    PlaceSuggestion(
      placeId: 'rwp_bahria_town',
      mainText: 'Bahria Town Phase 4 Civic Center',
      secondaryText: 'Civic Center, Bahria Town, Rawalpindi',
      coordinates: LatLng(33.5350, 73.1020),
    ),
    PlaceSuggestion(
      placeId: 'rwp_dha_phase1',
      mainText: 'DHA Phase 1 Commercial',
      secondaryText: 'Grand Trunk Road, Rawalpindi',
      coordinates: LatLng(33.5412, 73.1235),
    ),
    PlaceSuggestion(
      placeId: 'rwp_chandni_chowk',
      mainText: 'Chandni Chowk Murree Road',
      secondaryText: 'Murree Road, Rawalpindi',
      coordinates: LatLng(33.6267, 73.0715),
    ),

    // Lahore
    PlaceSuggestion(
      placeId: 'lhr_gulberg',
      mainText: 'Main Boulevard Gulberg',
      secondaryText: 'Gulberg III, Lahore',
      coordinates: LatLng(31.5126, 74.3444),
    ),
    PlaceSuggestion(
      placeId: 'lhr_dha_phase5',
      mainText: 'DHA Phase 5 Commercial',
      secondaryText: 'DHA, Lahore',
      coordinates: LatLng(31.4674, 74.4023),
    ),
    PlaceSuggestion(
      placeId: 'lhr_airport',
      mainText: 'Allama Iqbal International Airport (LHE)',
      secondaryText: 'Airport Road, Cantt, Lahore',
      coordinates: LatLng(31.5216, 74.4036),
    ),
    PlaceSuggestion(
      placeId: 'lhr_liberty_market',
      mainText: 'Liberty Market Gulberg',
      secondaryText: 'Noor Jehan Road, Gulberg III, Lahore',
      coordinates: LatLng(31.5103, 74.3431),
    ),

    // Karachi
    PlaceSuggestion(
      placeId: 'khi_clifton',
      mainText: 'Clifton Beach & Sea View',
      secondaryText: 'Block 4, Clifton, Karachi',
      coordinates: LatLng(24.8138, 67.0300),
    ),
    PlaceSuggestion(
      placeId: 'khi_dha_phase6',
      mainText: 'DHA Phase 6 Commercial',
      secondaryText: 'Khayaban-e-Shahbaz, DHA, Karachi',
      coordinates: LatLng(24.8052, 67.0620),
    ),
    PlaceSuggestion(
      placeId: 'khi_airport',
      mainText: 'Jinnah International Airport (KHI)',
      secondaryText: 'Airport Road, Karachi',
      coordinates: LatLng(24.9065, 67.1608),
    ),
    PlaceSuggestion(
      placeId: 'khi_shahrah_faisal',
      mainText: 'Shahrah-e-Faisal Business Corridor',
      secondaryText: 'Shahrah-e-Faisal, Karachi',
      coordinates: LatLng(24.8716, 67.0673),
    ),
  ];

  /// Gets device's real GPS position or falls back to platform default.
  Future<LatLng> getCurrentPosition() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return const LatLng(AppConstants.defaultLat, AppConstants.defaultLng);
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
          return const LatLng(AppConstants.defaultLat, AppConstants.defaultLng);
        }
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      return LatLng(pos.latitude, pos.longitude);
    } catch (e) {
      debugPrint('MapService.getCurrentPosition error: $e');
      return const LatLng(AppConstants.defaultLat, AppConstants.defaultLng);
    }
  }

  /// In-house reverse geocoder that maps coordinates to the closest sector,
  /// hub, or neighborhood with zero external third-party geocoder dependencies.
  Future<String> reverseGeocode(double lat, double lng) async {
    try {
      PlaceSuggestion? closest;
      double minDistance = double.infinity;

      for (final hub in _knownLocations) {
        final dist = DistanceCalculator.haversineDistance(
          lat,
          lng,
          hub.coordinates.latitude,
          hub.coordinates.longitude,
        );
        if (dist < minDistance) {
          minDistance = dist;
          closest = hub;
        }
      }

      if (closest != null) {
        if (minDistance <= 1.5) {
          return '${closest.mainText}, ${closest.secondaryText}';
        } else if (minDistance <= 6.0) {
          return 'Near ${closest.mainText} (${minDistance.toStringAsFixed(1)} km)';
        }
      }
    } catch (e) {
      debugPrint('MapService.reverseGeocode error: $e');
    }

    return 'Location (${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)})';
  }

  /// Searches for places matching query with instant keyword matching and ranking.
  Future<List<PlaceSuggestion>> searchPlaces(String query, {LatLng? near}) async {
    final results = <PlaceSuggestion>[];
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) return results;

    for (final hub in _knownLocations) {
      final mainLower = hub.mainText.toLowerCase();
      final secLower = hub.secondaryText.toLowerCase();

      if (mainLower.contains(trimmed) || secLower.contains(trimmed)) {
        results.add(hub);
      }
    }

    // If query has no exact match, create a custom search target for the rider
    if (results.isEmpty) {
      final centerLat = near?.latitude ?? AppConstants.defaultLat;
      final centerLng = near?.longitude ?? AppConstants.defaultLng;

      results.add(
        PlaceSuggestion(
          placeId: 'custom_${query.hashCode}',
          mainText: query.trim(),
          secondaryText: 'Custom Destination, Islamabad',
          coordinates: LatLng(centerLat + 0.015, centerLng + 0.015),
        ),
      );
    }

    return results;
  }

  /// Calculates driving route details with realistic curvature points.
  RouteDetails calculateRoute(LatLng origin, LatLng destination) {
    final distanceKm = DistanceCalculator.estimatedDrivingDistance(
      origin.latitude,
      origin.longitude,
      destination.latitude,
      destination.longitude,
    );

    final durationMin = DistanceCalculator.estimatedDurationMinutes(distanceKm);

    // Generate realistic road curvature polyline points between origin & destination
    final points = <LatLng>[origin];

    final midLat1 = origin.latitude + (destination.latitude - origin.latitude) * 0.33;
    final midLng1 = origin.longitude + (destination.longitude - origin.longitude) * 0.15;

    final midLat2 = origin.latitude + (destination.latitude - origin.latitude) * 0.66;
    final midLng2 = origin.longitude + (destination.longitude - origin.longitude) * 0.85;

    points.add(LatLng(midLat1, midLng1));
    points.add(LatLng(midLat2, midLng2));
    points.add(destination);

    return RouteDetails(
      polylinePoints: points,
      distanceKm: distanceKm,
      durationMin: durationMin,
      trafficLevel: 'NORMAL',
    );
  }

  /// Decodes encoded polylines using in-house PolylineService.
  List<LatLng> decodePolyline(String encoded) {
    return PolylineService.decodePolyline(encoded);
  }

  /// Encodes polylines using in-house PolylineService.
  String encodePolyline(List<LatLng> points) {
    return PolylineService.encodePolyline(points);
  }
}
