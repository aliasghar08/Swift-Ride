import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'map_marker_icons.dart';

/// Helper methods for producing consistent markers across Rider & Driver screens.
///
/// Uses the custom vector glyphs from [MapMarkerIcons] when they have been
/// rendered, and falls back to the stock Google pins otherwise so a rendering
/// failure degrades rather than blanking the map.
class MapMarkers {
  /// Pickup: green disc with a white ring.
  ///
  /// [id] lets a screen draw more than one pickup (for example the address
  /// search preview *and* the confirmed trip) without the two colliding on a
  /// shared `MarkerId`.
  static Marker pickup(LatLng pos, {String id = 'pickup'}) => Marker(
        markerId: MarkerId(id),
        position: pos,
        icon: MapMarkerIcons.pickup ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        anchor: const Offset(0.5, 0.5),
        infoWindow: const InfoWindow(title: 'Pickup'),
      );

  /// Dropoff: dark rounded square with a white ring.
  static Marker dropoff(LatLng pos, {String id = 'dropoff'}) => Marker(
        markerId: MarkerId(id),
        position: pos,
        icon: MapMarkerIcons.dropoff ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        anchor: const Offset(0.5, 0.5),
        infoWindow: const InfoWindow(title: 'Destination'),
      );

  /// Driver vehicle, rotated to its heading.
  ///
  /// [flat] keeps the glyph pinned to the map plane so rotating it reads as the
  /// car turning, rather than a billboard spinning in place.
  static Marker driver({
    required String driverId,
    required LatLng pos,
    required double heading,
    BitmapDescriptor? customIcon,
  }) =>
      Marker(
        markerId: MarkerId('driver_$driverId'),
        position: pos,
        rotation: heading,
        flat: true,
        anchor: const Offset(0.5, 0.5),
        zIndexInt: 2,
        icon: customIcon ??
            MapMarkerIcons.car ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: const InfoWindow(title: 'Your driver'),
      );

  /// Rider's own position with a heading cone, replacing the stock blue dot so
  /// the direction of travel is visible.
  static Marker locationPuck({
    required LatLng pos,
    required double heading,
    String id = 'location_puck',
  }) =>
      Marker(
        markerId: MarkerId(id),
        position: pos,
        rotation: heading,
        flat: true,
        anchor: const Offset(0.5, 0.5),
        zIndexInt: 3,
        icon: MapMarkerIcons.puck ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        infoWindow: const InfoWindow(title: 'You are here'),
      );
}
