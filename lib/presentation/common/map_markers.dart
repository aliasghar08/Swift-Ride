import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Helper methods for producing consistent Google Maps markers across Rider & Driver screens.
class MapMarkers {
  /// Pickup marker (green pin).
  static Marker pickup(LatLng pos) => Marker(
    markerId: const MarkerId('pickup'),
    position: pos,
    icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
    anchor: const Offset(0.5, 1.0),
    infoWindow: const InfoWindow(title: 'Pickup Location'),
  );

  /// Dropoff marker (red pin).
  static Marker dropoff(LatLng pos) => Marker(
    markerId: const MarkerId('dropoff'),
    position: pos,
    icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
    anchor: const Offset(0.5, 1.0),
    infoWindow: const InfoWindow(title: 'Dropoff Destination'),
  );

  /// Driver marker with rotation from heading.
  static Marker driver({
    required String driverId,
    required LatLng pos,
    required double heading,
    BitmapDescriptor? customIcon,
  }) => Marker(
    markerId: MarkerId('driver_$driverId'),
    position: pos,
    rotation: heading,
    flat: true,
    anchor: const Offset(0.5, 0.5),
    icon: customIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
    infoWindow: InfoWindow(title: 'Driver $driverId'),
  );
}
