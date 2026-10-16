import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import '../../services/native_map_service.dart';

import 'map_marker_icons.dart';

/// Helper methods for producing consistent markers across Rider & Driver screens.
///
/// Uses the custom vector glyphs from [MapMarkerIcons] when they have been
/// rendered, and falls back to the stock Google pins otherwise so a rendering
/// failure degrades rather than blanking the map.
class MapMarkers {
  static BitmapDescriptor? customOriginDot;

  /// Ensures custom origin dot glyph is generated.
  static Future<void> ensureOriginDot() async {
    if (customOriginDot != null) return;
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      const size = 56.0;
      const c = Offset(size / 2, size / 2);
      // Soft shadow
      canvas.drawCircle(c, 24.0, Paint()..color = const Color(0x33000000));
      // Outer crisp white ring
      canvas.drawCircle(c, 22.0, Paint()..color = Colors.white);
      // Inner bold dark navy disc
      canvas.drawCircle(c, 16.0, Paint()..color = const Color(0xFF0F172A));
      // Center solid core
      canvas.drawCircle(c, 7.0, Paint()..color = Colors.white);
      final picture = recorder.endRecording();
      final img = await picture.toImage(size.toInt(), size.toInt());
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        customOriginDot = BitmapDescriptor.bytes(byteData.buffer.asUint8List());
      }
    } catch (_) {}
  }

  /// Origin: Google-style prominent start circle.
  static Marker originDot(LatLng pos, {String id = 'route_origin'}) => Marker(
        markerId: MarkerId(id),
        position: pos,
        icon: customOriginDot ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan),
        anchor: const Offset(0.5, 0.5),
        zIndexInt: 4,
        infoWindow: const InfoWindow(title: 'Pickup'),
      );

  /// Pickup: green disc with a white ring.
  static Marker pickup(LatLng pos, {String id = 'pickup'}) => Marker(
        markerId: MarkerId(id),
        position: pos,
        icon: MapMarkerIcons.pickup ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        anchor: const Offset(0.5, 0.5),
        infoWindow: const InfoWindow(title: 'Pickup'),
      );

  /// Dropoff: classic Google Maps red teardrop pin.
  static Marker dropoff(LatLng pos, {String id = 'dropoff'}) => Marker(
        markerId: MarkerId(id),
        position: pos,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        anchor: const Offset(0.5, 1.0),
        zIndexInt: 5,
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
