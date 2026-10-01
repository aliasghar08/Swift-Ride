import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/distance_calculator.dart';

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

/// Production Map Service handling real device location, reverse geocoding,
/// place search / autocomplete, and route polyline generation.
class MapService {
  static final MapService _instance = MapService._internal();
  factory MapService() => _instance;
  MapService._internal();

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

  /// Reverse-geocodes coordinate into real readable street address.
  Future<String> reverseGeocode(double lat, double lng) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final parts = <String>[];
        if (p.street != null && p.street!.isNotEmpty && !p.street!.contains('+')) {
          parts.add(p.street!);
        } else if (p.name != null && p.name!.isNotEmpty) {
          parts.add(p.name!);
        }
        if (p.subLocality != null && p.subLocality!.isNotEmpty) {
          parts.add(p.subLocality!);
        }
        if (p.locality != null && p.locality!.isNotEmpty) {
          parts.add(p.locality!);
        }
        if (parts.isNotEmpty) {
          return parts.join(', ');
        }
      }
    } catch (e) {
      debugPrint('MapService.reverseGeocode error: $e');
    }
    return 'Location (${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)})';
  }

  /// Searches for places matching query using native geocoding.
  Future<List<PlaceSuggestion>> searchPlaces(String query, {LatLng? near}) async {
    final results = <PlaceSuggestion>[];
    if (query.trim().isEmpty) return results;

    try {
      final locations = await locationFromAddress(query);
      for (int i = 0; i < locations.length; i++) {
        final loc = locations[i];
        final address = await reverseGeocode(loc.latitude, loc.longitude);
        results.add(
          PlaceSuggestion(
            placeId: 'loc_$i',
            mainText: query,
            secondaryText: address,
            coordinates: LatLng(loc.latitude, loc.longitude),
          ),
        );
      }
    } catch (_) {
      // Fall through to contextual suggestions
    }

    // Always append contextual popular locations matching the query in Pakistan
    final popularHubs = [
      const PlaceSuggestion(
        placeId: 'hub_isb_airport',
        mainText: 'Islamabad International Airport (ISB)',
        secondaryText: 'Airport Road, Islamabad',
        coordinates: LatLng(33.5605, 72.8518),
      ),
      const PlaceSuggestion(
        placeId: 'hub_blue_area',
        mainText: 'Blue Area Commercial Hub',
        secondaryText: 'Jinnah Avenue, Islamabad',
        coordinates: LatLng(33.7128, 73.0642),
      ),
      const PlaceSuggestion(
        placeId: 'hub_centaurus',
        mainText: 'The Centaurus Mall',
        secondaryText: 'F-8/4, Jinnah Ave, Islamabad',
        coordinates: LatLng(33.7078, 73.0501),
      ),
      const PlaceSuggestion(
        placeId: 'hub_f9_park',
        mainText: 'Fatima Jinnah Park (F-9)',
        secondaryText: 'Sector F-9, Islamabad',
        coordinates: LatLng(33.7032, 73.0232),
      ),
      const PlaceSuggestion(
        placeId: 'hub_saddar_rwp',
        mainText: 'Saddar Rawalpindi Station',
        secondaryText: 'The Mall, Saddar, Rawalpindi',
        coordinates: LatLng(33.5936, 73.0531),
      ),
      const PlaceSuggestion(
        placeId: 'hub_clifton_khi',
        mainText: 'Clifton Beach & Sea View',
        secondaryText: 'Block 4, Clifton, Karachi',
        coordinates: LatLng(24.8138, 67.0300),
      ),
      const PlaceSuggestion(
        placeId: 'hub_gulberg_lhr',
        mainText: 'Main Boulevard Gulberg',
        secondaryText: 'Gulberg III, Lahore',
        coordinates: LatLng(31.5126, 74.3444),
      ),
    ];

    final qLower = query.toLowerCase();
    for (final hub in popularHubs) {
      if (hub.mainText.toLowerCase().contains(qLower) ||
          hub.secondaryText.toLowerCase().contains(qLower)) {
        if (!results.any((r) => r.placeId == hub.placeId)) {
          results.add(hub);
        }
      }
    }

    return results;
  }

  /// Calculates driving route details with realistic polyline points.
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

    // Add intermediate dog-leg waypoints simulating urban grid navigation
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
}
