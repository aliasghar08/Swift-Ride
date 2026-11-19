import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'polyline_service.dart';

/// Representation of geographical coordinates (latitude, longitude).
class LatLng {
  final double latitude;
  final double longitude;

  const LatLng(this.latitude, this.longitude);

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
      };

  factory LatLng.fromJson(Map<String, dynamic> json) => LatLng(
        (json['latitude'] as num).toDouble(),
        (json['longitude'] as num).toDouble(),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LatLng &&
          runtimeType == other.runtimeType &&
          (latitude - other.latitude).abs() < 1e-7 &&
          (longitude - other.longitude).abs() < 1e-7;

  @override
  int get hashCode => Object.hash(
        (latitude * 1e5).round(),
        (longitude * 1e5).round(),
      );

  @override
  String toString() => 'LatLng($latitude, $longitude)';
}

/// Bounding box defined by southwest and northeast [LatLng] coordinates.
class LatLngBounds {
  final LatLng southwest;
  final LatLng northeast;

  const LatLngBounds({required this.southwest, required this.northeast});

  bool contains(LatLng point) {
    return point.latitude >= southwest.latitude &&
        point.latitude <= northeast.latitude &&
        point.longitude >= southwest.longitude &&
        point.longitude <= northeast.longitude;
  }

  Map<String, dynamic> toJson() => {
        'southwest': southwest.toJson(),
        'northeast': northeast.toJson(),
      };
}

/// Represents the camera viewpoint over the native map.
class CameraPosition {
  final LatLng target;
  final double zoom;
  final double tilt;
  final double bearing;

  const CameraPosition({
    required this.target,
    this.zoom = 14.0,
    this.tilt = 0.0,
    this.bearing = 0.0,
  });

  Map<String, dynamic> toMap() => {
        'target': target.toJson(),
        'zoom': zoom,
        'tilt': tilt,
        'bearing': bearing,
      };

  @override
  String toString() =>
      'CameraPosition(target: $target, zoom: $zoom, tilt: $tilt, bearing: $bearing)';
}

/// Encapsulates instructions to update the native camera viewport.
class CameraUpdate {
  final Map<String, dynamic> _params;
  CameraUpdate._(this._params);

  static CameraUpdate newLatLng(LatLng latLng) => CameraUpdate._({
        'type': 'newLatLng',
        'target': latLng.toJson(),
      });

  static CameraUpdate newLatLngZoom(LatLng latLng, double zoom) =>
      CameraUpdate._({
        'type': 'newLatLngZoom',
        'target': latLng.toJson(),
        'zoom': zoom,
      });

  static CameraUpdate newLatLngBounds(LatLngBounds bounds, double padding) =>
      CameraUpdate._({
        'type': 'newLatLngBounds',
        'southwest': bounds.southwest.toJson(),
        'northeast': bounds.northeast.toJson(),
        'padding': padding,
      });

  static CameraUpdate newCameraPosition(CameraPosition position) =>
      CameraUpdate._({
        'type': 'newCameraPosition',
        'target': position.target.toJson(),
        'zoom': position.zoom,
        'tilt': position.tilt,
        'bearing': position.bearing,
      });

  static CameraUpdate zoomTo(double zoom) => CameraUpdate._({
        'type': 'zoomTo',
        'zoom': zoom,
      });

  Map<String, dynamic> toJson() => _params;
}

/// Identifier for map markers.
@immutable
class MarkerId {
  final String value;
  const MarkerId(this.value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MarkerId &&
          runtimeType == other.runtimeType &&
          value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'MarkerId($value)';
}

/// Description of marker icons (stock color hues, default pins, or custom bytes).
class BitmapDescriptor {
  final dynamic _data;
  const BitmapDescriptor._(this._data);

  static const double hueRed = 0.0;
  static const double hueOrange = 30.0;
  static const double hueYellow = 60.0;
  static const double hueGreen = 120.0;
  static const double hueCyan = 180.0;
  static const double hueAzure = 210.0;
  static const double hueBlue = 240.0;
  static const double hueViolet = 270.0;
  static const double hueMagenta = 300.0;
  static const double hueRose = 330.0;

  static BitmapDescriptor defaultMarkerWithHue(double hue) =>
      BitmapDescriptor._({'type': 'hue', 'hue': hue});

  static const BitmapDescriptor defaultMarker =
      BitmapDescriptor._({'type': 'default'});

  static BitmapDescriptor bytes(Uint8List bytes) =>
      BitmapDescriptor._({'type': 'bytes', 'bytes': bytes});

  dynamic get rawData => _data;
}

/// Info window displayed when tapping a native marker.
class InfoWindow {
  final String? title;
  final String? snippet;
  final VoidCallback? onTap;

  const InfoWindow({this.title, this.snippet, this.onTap});

  static const InfoWindow noText = InfoWindow();
}

/// Represents an interactive marker on the native map view.
class Marker {
  final MarkerId markerId;
  final LatLng position;
  final BitmapDescriptor icon;
  final Offset anchor;
  final double rotation;
  final bool flat;
  final InfoWindow infoWindow;
  final int zIndex;
  final int zIndexInt;
  final VoidCallback? onTap;

  const Marker({
    required this.markerId,
    required this.position,
    this.icon = BitmapDescriptor.defaultMarker,
    this.anchor = const Offset(0.5, 1.0),
    this.rotation = 0.0,
    this.flat = false,
    this.infoWindow = InfoWindow.noText,
    this.zIndex = 0,
    int? zIndexInt,
    this.onTap,
  }) : zIndexInt = zIndexInt ?? zIndex;

  Map<String, dynamic> toJson() => {
        'id': markerId.value,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'title': infoWindow.title ?? '',
        'snippet': infoWindow.snippet ?? '',
        'rotation': rotation,
        'anchorX': anchor.dx,
        'anchorY': anchor.dy,
        'zIndex': zIndexInt,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Marker &&
          runtimeType == other.runtimeType &&
          markerId == other.markerId &&
          position == other.position &&
          rotation == other.rotation &&
          infoWindow.title == other.infoWindow.title;

  @override
  int get hashCode => Object.hash(markerId, position, rotation, infoWindow.title);
}

/// Identifier for map polylines.
@immutable
class PolylineId {
  final String value;
  const PolylineId(this.value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PolylineId &&
          runtimeType == other.runtimeType &&
          value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'PolylineId($value)';
}

/// Pattern item for dashed/dotted native lines.
class PatternItem {
  final String type;
  final double length;
  const PatternItem.dash(this.length) : type = 'dash';
  const PatternItem.gap(this.length) : type = 'gap';
  const PatternItem.dot()
      : type = 'dot',
        length = 0.0;
}

/// Cap style for native line endpoints.
class Cap {
  static const roundCap = Cap._('round');
  static const squareCap = Cap._('square');
  static const buttCap = Cap._('butt');
  final String type;
  const Cap._(this.type);
}

/// Joint type for line corners.
class JointType {
  static const round = JointType._('round');
  static const bevel = JointType._('bevel');
  static const miter = JointType._('miter');
  final String type;
  const JointType._(this.type);
}

/// Represents a route polyline on the native map view.
class Polyline {
  final PolylineId polylineId;
  final List<LatLng> points;
  final Color color;
  final int width;
  final int zIndex;
  final int zIndexInt;
  final bool geodesic;
  final List<PatternItem>? patterns;
  final Cap? startCap;
  final Cap? endCap;
  final JointType? jointType;

  const Polyline({
    required this.polylineId,
    required this.points,
    this.color = const Color(0xFF000000),
    this.width = 5,
    this.zIndex = 0,
    int? zIndexInt,
    this.geodesic = false,
    this.patterns,
    this.startCap,
    this.endCap,
    this.jointType,
  }) : zIndexInt = zIndexInt ?? zIndex;

  Map<String, dynamic> toJson() => {
        'id': polylineId.value,
        'color': color.toARGB32(),
        'width': width.toDouble(),
        'points': points
            .map((p) => {
                  'latitude': p.latitude,
                  'longitude': p.longitude,
                })
            .toList(),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Polyline &&
          runtimeType == other.runtimeType &&
          polylineId == other.polylineId &&
          listEquals(points, other.points) &&
          color == other.color &&
          width == other.width;

  @override
  int get hashCode => Object.hash(polylineId, points.length, color, width);
}

/// Identifier for map circles.
@immutable
class CircleId {
  final String value;
  const CircleId(this.value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CircleId &&
          runtimeType == other.runtimeType &&
          value == other.value;

  @override
  int get hashCode => value.hashCode;
}

/// Represents a circular radius overlay on the native map view.
class Circle {
  final CircleId circleId;
  final LatLng center;
  final double radius;
  final Color fillColor;
  final Color strokeColor;
  final int strokeWidth;

  const Circle({
    required this.circleId,
    required this.center,
    required this.radius,
    this.fillColor = const Color(0x00000000),
    this.strokeColor = const Color(0xFF000000),
    this.strokeWidth = 1,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Circle &&
          runtimeType == other.runtimeType &&
          circleId == other.circleId;

  @override
  int get hashCode => circleId.hashCode;
}

enum MapType { none, normal, satellite, terrain, hybrid }

/// Controller communicating with an active native platform map view instance.
class NativeMapController {
  final int viewId;
  final MethodChannel _channel;

  NativeMapController(this.viewId)
      : _channel = MethodChannel('com.swiftride.app/native_map_view_$viewId');

  Future<bool> animateCamera(dynamic update, {double? zoom}) async {
    try {
      if (update is LatLng) {
        final args = <String, dynamic>{
          'latitude': update.latitude,
          'longitude': update.longitude,
        };
        if (zoom != null) args['zoom'] = zoom;
        final res = await _channel.invokeMethod<bool>('animateCamera', args);
        return res ?? false;
      } else if (update is CameraPosition) {
        final res = await _channel.invokeMethod<bool>('animateCamera', {
          'latitude': update.target.latitude,
          'longitude': update.target.longitude,
          'zoom': update.zoom,
          'tilt': update.tilt,
          'bearing': update.bearing,
        });
        return res ?? false;
      } else if (update is CameraUpdate) {
        final params = update.toJson();
        final type = params['type'] as String?;
        if (type == 'newLatLng' || type == 'newLatLngZoom') {
          final target = params['target'] as Map<String, dynamic>;
          final args = <String, dynamic>{
            'latitude': target['latitude'],
            'longitude': target['longitude'],
          };
          if (params['zoom'] != null) args['zoom'] = params['zoom'];
          final res = await _channel.invokeMethod<bool>('animateCamera', args);
          return res ?? false;
        } else if (type == 'newCameraPosition') {
          final target = params['target'] as Map<String, dynamic>;
          final args = <String, dynamic>{
            'latitude': target['latitude'],
            'longitude': target['longitude'],
            if (params['zoom'] != null) 'zoom': params['zoom'],
            if (params['tilt'] != null) 'tilt': params['tilt'],
            if (params['bearing'] != null) 'bearing': params['bearing'],
          };
          final res = await _channel.invokeMethod<bool>('animateCamera', args);
          return res ?? false;
        } else if (type == 'newLatLngBounds') {
          final sw = params['southwest'] as Map<String, dynamic>;
          final ne = params['northeast'] as Map<String, dynamic>;
          final centerLat = ((sw['latitude'] as num) + (ne['latitude'] as num)) / 2;
          final centerLng =
              ((sw['longitude'] as num) + (ne['longitude'] as num)) / 2;
          final res = await _channel.invokeMethod<bool>('animateCamera', {
            'latitude': centerLat,
            'longitude': centerLng,
            'zoom': 14.5,
          });
          return res ?? false;
        } else if (type == 'zoomTo') {
          final res = await _channel.invokeMethod<bool>('animateCamera', {
            'zoom': params['zoom'],
          });
          return res ?? false;
        }
      }
      return false;
    } catch (e) {
      debugPrint('[NativeMapController] animateCamera failed: $e');
      return false;
    }
  }

  /// 3D navigation perspective follow camera.
  Future<bool> followNavigation({
    required LatLng target,
    required double bearing,
    double zoom = 17.5,
    double tilt = 48.0,
  }) {
    return animateCamera(CameraPosition(
      target: target,
      zoom: zoom,
      bearing: bearing,
      tilt: tilt,
    ));
  }

  Future<void> moveCamera(dynamic update) => animateCamera(update);

  Future<void> setMarkers(Set<Marker> markers) async {
    try {
      final list = markers.map((m) {
        return {
          'id': m.markerId.value,
          'latitude': m.position.latitude,
          'longitude': m.position.longitude,
          'title': m.infoWindow.title ?? '',
          'rotation': m.rotation,
          'hue': _markerHue(m),
        };
      }).toList();

      await _channel.invokeMethod('setMarkers', {'markers': list});
    } catch (e) {
      debugPrint('[NativeMapController] setMarkers failed: $e');
    }
  }

  double _markerHue(Marker m) {
    final id = m.markerId.value.toLowerCase();
    if (id.contains('pickup')) return 120.0; // Green
    if (id.contains('dropoff')) return 0.0; // Red
    if (id.contains('driver')) return 195.0; // Cyan
    return 210.0; // Blue default
  }

  Future<void> setPolylines(Set<Polyline> polylines) async {
    try {
      final list = polylines.map((p) => p.toJson()).toList();
      await _channel.invokeMethod('setPolylines', {'polylines': list});
    } catch (e) {
      debugPrint('[NativeMapController] setPolylines failed: $e');
    }
  }

  Future<void> setMyLocationEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod('setMyLocationEnabled', {'enabled': enabled});
    } catch (e) {
      debugPrint('[NativeMapController] setMyLocationEnabled failed: $e');
    }
  }

  Future<void> setTrafficEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod('setTrafficEnabled', {'enabled': enabled});
    } catch (e) {
      debugPrint('[NativeMapController] setTrafficEnabled failed: $e');
    }
  }

  Future<void> setMapStyle(String? jsonStyle) async {
    if (jsonStyle == null) return;
    try {
      await _channel.invokeMethod('setMapStyle', {'style': jsonStyle});
    } catch (e) {
      debugPrint('[NativeMapController] setMapStyle failed: $e');
    }
  }

  void dispose() {}
}

/// Backwards compatibility alias
typedef GoogleMapController = NativeMapController;

/// Service interacting with native platform MethodChannels for
/// Map utilities, location telemetry, and reverse geocoding.
class NativeMapService {
  NativeMapService._();
  static final NativeMapService instance = NativeMapService._();

  static const MethodChannel _mapChannel =
      MethodChannel('com.dartnexuslab.swiftride/map');
  static const MethodChannel _altMapChannel =
      MethodChannel('com.swiftride.app/map');

  static const MethodChannel _locationChannel =
      MethodChannel('com.dartnexuslab.swiftride/location');
  static const MethodChannel _altLocationChannel =
      MethodChannel('com.swiftride.app/location');

  static Future<T?> _invokeWithFallback<T>(
    MethodChannel primary,
    MethodChannel fallback,
    String method, [
    dynamic arguments,
  ]) async {
    try {
      return await primary.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      try {
        return await fallback.invokeMethod<T>(method, arguments);
      } catch (_) {
        return null;
      }
    } catch (e) {
      try {
        return await fallback.invokeMethod<T>(method, arguments);
      } catch (_) {
        return null;
      }
    }
  }

  /// Checks if location permission is granted by the native OS.
  Future<bool> checkLocationPermissions() async {
    final res = await _invokeWithFallback<bool>(
      _locationChannel,
      _altLocationChannel,
      'checkLocationPermissions',
    );
    return res ?? false;
  }

  /// Requests location permissions asynchronously from the native OS.
  Future<bool> requestLocationPermissions() async {
    final res = await _invokeWithFallback<bool>(
      _locationChannel,
      _altLocationChannel,
      'requestLocationPermissions',
    );
    return res ?? false;
  }

  /// Fetches the latest genuine GPS position from native location services.
  Future<LatLng?> getCurrentLocation() async {
    final map = await _invokeWithFallback<Map<dynamic, dynamic>>(
      _locationChannel,
      _altLocationChannel,
      'getCurrentLocation',
    );
    if (map != null && map.containsKey('latitude') && map.containsKey('longitude')) {
      final lat = (map['latitude'] as num).toDouble();
      final lng = (map['longitude'] as num).toDouble();
      return LatLng(lat, lng);
    }
    return null;
  }

  /// Performs reverse geocoding via native Geocoder (Android) or CLGeocoder (iOS).
  Future<String?> reverseGeocode(double latitude, double longitude) async {
    final res = await _invokeWithFallback<String>(
      _locationChannel,
      _altLocationChannel,
      'reverseGeocode',
      {'latitude': latitude, 'longitude': longitude},
    );
    return res;
  }

  /// Checks whether [address] contains granular plot, house, street, or premise
  /// details rather than just a broad neighborhood or city name.
  static bool isGranularAddress(String? address) {
    if (address == null) return false;
    final trimmed = address.trim();
    if (trimmed.isEmpty ||
        trimmed.startsWith('Location (') ||
        trimmed.startsWith('Pinned Spot') ||
        trimmed == 'Pinned Location' ||
        trimmed.startsWith('Coordinates:')) {
      return false;
    }

    // Raw Plus Code at the start does not count as a resolved plot/premise name
    final withoutPlusCode = trimmed.replaceAll(
      RegExp(r'\b[A-Za-z0-9]{4,8}\+[A-Za-z0-9]{2,5}\b'),
      '',
    );

    final granularKeywords = RegExp(
      r'\b(plot|house|shop|flat|apt|apartment|suite|floor|unit|plaza|tower|center|centre|complex|arcade|heights|residency|villa|manzil|cottage|chambers|hospital|clinic|pharmacy|university|college|school|academy|institute|masjid|mosque|church|temple|market|bazaar|mall|mart|store|bank|hotel|restaurant|cafe|bakery|station|terminal|stop|park|stadium|club|gym|court|office|street|st|road|rd|avenue|ave|lane|ln|boulevard|blvd|chowk|bazar|gali|kucha|mohalla|mohallah|block|sector|phase|scheme|police|lines|cantonment|cantt|sadar|saddar|hall|markaz|branch|gate|pul|bridge|stand|adda|basti|kot|deh|chak|mouza|moza|deri|dhok|tehsil|headworks|patrolling|barracks)\b',
      caseSensitive: false,
    );
    if (granularKeywords.hasMatch(withoutPlusCode)) {
      return true;
    }

    // Check for explicit plot/street/house number tokens (e.g., "145-B", "42", "#12")
    if (RegExp(r'(?:^|[,\s#/-])\d+[A-Za-z]?(?:\b|$)').hasMatch(withoutPlusCode)) {
      return true;
    }

    // If the address has 3+ comma-separated segments and the first segment is not a city/country,
    // it likely starts with a named premise/landmark (e.g. "Al-Fatah, Gulberg III, Lahore").
    final segments = withoutPlusCode
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (segments.length >= 3) {
      return true;
    }

    return false;
  }

  /// Calculates geodesic distance in kilometers between two coordinates natively.
  Future<double> calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) async {
    final res = await _invokeWithFallback<double>(
      _mapChannel,
      _altMapChannel,
      'calculateDistance',
      {
        'lat1': lat1,
        'lon1': lon1,
        'lat2': lat2,
        'lon2': lon2,
      },
    );
    if (res != null) return res;

    // Fallback haversine formula in Dart
    const double earthRadiusKm = 6371.0;
    final dLat = (lat2 - lat1) * math.pi / 180.0;
    final dLon = (lon2 - lon1) * math.pi / 180.0;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180.0) *
            math.cos(lat2 * math.pi / 180.0) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  /// Decodes Google-encoded polyline string to a list of [LatLng].
  List<LatLng> decodePolyline(String encoded) {
    return PolylineService.decodePolyline(encoded);
  }

  /// Encodes a list of [LatLng] into a Google-encoded polyline string.
  String encodePolyline(List<LatLng> points) {
    return PolylineService.encodePolyline(points);
  }
}
