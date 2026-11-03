import 'dart:math';

/// Representation of a bounding box for a geohash.
class GeohashBounds {
  final double minLat;
  final double maxLat;
  final double minLng;
  final double maxLng;

  const GeohashBounds({
    required this.minLat,
    required this.maxLat,
    required this.minLng,
    required this.maxLng,
  });

  /// Checks whether a given [lat], [lng] coordinate pair lies inside this bounding box.
  bool contains(double lat, double lng) =>
      lat >= minLat && lat <= maxLat && lng >= minLng && lng <= maxLng;

  @override
  String toString() =>
      'GeohashBounds(lat: [$minLat, $maxLat], lng: [$minLng, $maxLng])';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GeohashBounds &&
          runtimeType == other.runtimeType &&
          minLat == other.minLat &&
          maxLat == other.maxLat &&
          minLng == other.minLng &&
          maxLng == other.maxLng;

  @override
  int get hashCode =>
      minLat.hashCode ^ maxLat.hashCode ^ minLng.hashCode ^ maxLng.hashCode;
}

/// Decoded center coordinate with bounding box error margins.
class GeohashCoordinates {
  final double latitude;
  final double longitude;
  final double latError;
  final double lngError;

  const GeohashCoordinates({
    required this.latitude,
    required this.longitude,
    required this.latError,
    required this.lngError,
  });

  @override
  String toString() =>
      'GeohashCoordinates(lat: $latitude, lng: $longitude, error: [±$latError, ±$lngError])';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GeohashCoordinates &&
          runtimeType == other.runtimeType &&
          latitude == other.latitude &&
          longitude == other.longitude &&
          latError == other.latError &&
          lngError == other.lngError;

  @override
  int get hashCode =>
      latitude.hashCode ^
      longitude.hashCode ^
      latError.hashCode ^
      lngError.hashCode;
}

/// A range of geohashes for Firestore range queries: `start <= geohash <= end`.
class GeohashRange {
  final String start;
  final String end;

  const GeohashRange(this.start, this.end);

  @override
  String toString() => 'GeohashRange($start, $end)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GeohashRange &&
          runtimeType == other.runtimeType &&
          start == other.start &&
          end == other.end;

  @override
  int get hashCode => start.hashCode ^ end.hashCode;
}

/// Comprehensive utility for Geohash encoding, decoding, spatial bounding box
/// queries, 8-directional neighbor indexing, distance, and bearing computations.
///
/// Fully compatible with standard GeoFire / GeoFlutterFire query bounds.
class GeohashUtil {
  static const String _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';

  // GeoFire geodesy constants
  static const double _earthMeriCircumference = 40007860.0;
  static const double _metersPerDegreeLatitude = 110574.0;
  static const int _bitsPerChar = 5;
  static const int _maximumBitsPrecision = 22 * _bitsPerChar;
  static const double _earthEqRadius = 6378137.0;
  static const double _e2 = 0.00669447819799;
  static const double _epsilon = 1e-12;

  /// Returns true if [geohash] is non-null, non-empty, and only contains valid base32 characters.
  static bool isValid(String? geohash) {
    if (geohash == null || geohash.isEmpty) return false;
    final lower = geohash.toLowerCase();
    for (int i = 0; i < lower.length; i++) {
      if (!_base32.contains(lower[i])) return false;
    }
    return true;
  }

  /// Encodes latitude and longitude into a geohash string of given precision.
  static String encode(double latitude, double longitude, [int precision = 7]) {
    if (precision < 1 || precision > 12) {
      throw ArgumentError.value(precision, 'precision', 'Precision must be between 1 and 12.');
    }

    double minLat = -90.0;
    double maxLat = 90.0;
    double minLng = -180.0;
    double maxLng = 180.0;

    final StringBuffer geohash = StringBuffer();
    bool isEven = true;
    int bit = 0;
    int ch = 0;

    while (geohash.length < precision) {
      if (isEven) {
        final mid = (minLng + maxLng) / 2;
        if (longitude >= mid) {
          ch |= (1 << (4 - bit));
          minLng = mid;
        } else {
          maxLng = mid;
        }
      } else {
        final mid = (minLat + maxLat) / 2;
        if (latitude >= mid) {
          ch |= (1 << (4 - bit));
          minLat = mid;
        } else {
          maxLat = mid;
        }
      }

      isEven = !isEven;
      if (bit < 4) {
        bit++;
      } else {
        geohash.write(_base32[ch]);
        bit = 0;
        ch = 0;
      }
    }

    return geohash.toString();
  }

  /// Calculates coarse prefix (5 characters ~4.9km x 4.9km) for high-level clustering.
  static String coarsePrefix(double latitude, double longitude) {
    return encode(latitude, longitude, 5);
  }

  /// Decodes a geohash into its center coordinates and error margins.
  static GeohashCoordinates decode(String geohash) {
    final b = bounds(geohash);
    final lat = (b.minLat + b.maxLat) / 2.0;
    final lng = (b.minLng + b.maxLng) / 2.0;
    final latErr = (b.maxLat - b.minLat) / 2.0;
    final lngErr = (b.maxLng - b.minLng) / 2.0;

    return GeohashCoordinates(
      latitude: lat,
      longitude: lng,
      latError: latErr,
      lngError: lngErr,
    );
  }

  /// Calculates the bounding box for a given geohash.
  static GeohashBounds bounds(String geohash) {
    if (!isValid(geohash)) {
      throw FormatException('Invalid geohash string: "$geohash"');
    }

    final lower = geohash.toLowerCase();
    double minLat = -90.0;
    double maxLat = 90.0;
    double minLng = -180.0;
    double maxLng = 180.0;
    bool isEven = true;

    for (int i = 0; i < lower.length; i++) {
      final cd = _base32.indexOf(lower[i]);
      for (int bit = 4; bit >= 0; bit--) {
        final bitVal = (cd >> bit) & 1;
        if (isEven) {
          final mid = (minLng + maxLng) / 2.0;
          if (bitVal == 1) {
            minLng = mid;
          } else {
            maxLng = mid;
          }
        } else {
          final mid = (minLat + maxLat) / 2.0;
          if (bitVal == 1) {
            minLat = mid;
          } else {
            maxLat = mid;
          }
        }
        isEven = !isEven;
      }
    }

    return GeohashBounds(
      minLat: minLat,
      maxLat: maxLat,
      minLng: minLng,
      maxLng: maxLng,
    );
  }

  /// Calculates the adjacent neighbor geohash in [direction] ('n', 's', 'e', 'w', 'ne', 'nw', 'se', 'sw').
  static String neighbor(String geohash, String direction) {
    final b = bounds(geohash);
    final latDelta = b.maxLat - b.minLat;
    final lngDelta = b.maxLng - b.minLng;
    final centerLat = (b.minLat + b.maxLat) / 2.0;
    final centerLng = (b.minLng + b.maxLng) / 2.0;

    double targetLat = centerLat;
    double targetLng = centerLng;

    switch (direction.toLowerCase().trim()) {
      case 'n':
      case 'north':
        targetLat += latDelta;
        break;
      case 's':
      case 'south':
        targetLat -= latDelta;
        break;
      case 'e':
      case 'east':
        targetLng += lngDelta;
        break;
      case 'w':
      case 'west':
        targetLng -= lngDelta;
        break;
      case 'ne':
      case 'northeast':
        targetLat += latDelta;
        targetLng += lngDelta;
        break;
      case 'nw':
      case 'northwest':
        targetLat += latDelta;
        targetLng -= lngDelta;
        break;
      case 'se':
      case 'southeast':
        targetLat -= latDelta;
        targetLng += lngDelta;
        break;
      case 'sw':
      case 'southwest':
        targetLat -= latDelta;
        targetLng -= lngDelta;
        break;
      default:
        throw ArgumentError.value(
          direction,
          'direction',
          'Direction must be one of: n, s, e, w, ne, nw, se, sw.',
        );
    }

    targetLat = targetLat.clamp(-90.0, 90.0);
    targetLng = _wrapLongitude(targetLng);

    return encode(targetLat, targetLng, geohash.length);
  }

  /// Computes all 8 adjacent neighbor geohashes surrounding [geohash].
  static Map<String, String> neighbors(String geohash) {
    return {
      'north': neighbor(geohash, 'n'),
      'south': neighbor(geohash, 's'),
      'east': neighbor(geohash, 'e'),
      'west': neighbor(geohash, 'w'),
      'northEast': neighbor(geohash, 'ne'),
      'northWest': neighbor(geohash, 'nw'),
      'southEast': neighbor(geohash, 'se'),
      'southWest': neighbor(geohash, 'sw'),
    };
  }

  /// Calculates a set of geohash query bounds [GeohashRange] for Firestore
  /// range queries (`where('geohash', '>=', start).where('geohash', '<=', end)`).
  ///
  /// Completely matches GeoFire standard geohash query logic.
  /// [radiusKm] is radius in kilometers (or pass [radiusMeters] via [queryBoundsMeters]).
  static List<GeohashRange> queryBounds(
    double centerLat,
    double centerLng,
    double radiusKm,
  ) {
    return queryBoundsMeters(centerLat, centerLng, radiusKm * 1000.0);
  }

  /// Calculates geohash query bounds for a center and radius in meters.
  static List<GeohashRange> queryBoundsMeters(
    double centerLat,
    double centerLng,
    double radiusMeters,
  ) {
    final queryBits = max(1, _boundingBoxBits(centerLat, centerLng, radiusMeters));
    final geohashPrecision = (queryBits / _bitsPerChar).ceil();
    final coordinates = _boundingBoxCoordinates(centerLat, centerLng, radiusMeters);

    final queries = coordinates.map((coord) {
      final hash = encode(coord[0], coord[1], geohashPrecision);
      return _geohashQuery(hash, queryBits);
    }).toList();

    // Deduplicate ranges preserving order
    final List<GeohashRange> unique = [];
    for (final q in queries) {
      if (!unique.any((existing) => existing.start == q.start && existing.end == q.end)) {
        unique.add(q);
      }
    }
    return unique;
  }

  /// Great-circle Haversine distance in kilometers between two coordinates.
  static double distanceKm(double lat1, double lng1, double lat2, double lng2) {
    const double radius = 6371.0;
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLng = _degreesToRadians(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) *
            cos(_degreesToRadians(lat2)) *
            sin(dLng / 2) *
            sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return radius * c;
  }

  /// Great-circle Haversine distance in meters between two coordinates.
  static double distanceMeters(double lat1, double lng1, double lat2, double lng2) {
    return distanceKm(lat1, lng1, lat2, lng2) * 1000.0;
  }

  /// Computes compass bearing (initial forward azimuth) in degrees [0, 360) from (lat1, lng1) to (lat2, lng2).
  static double bearing(double lat1, double lng1, double lat2, double lng2) {
    final phi1 = _degreesToRadians(lat1);
    final phi2 = _degreesToRadians(lat2);
    final deltaLambda = _degreesToRadians(lng2 - lng1);

    final y = sin(deltaLambda) * cos(phi2);
    final x = cos(phi1) * sin(phi2) - sin(phi1) * cos(phi2) * cos(deltaLambda);
    final theta = atan2(y, x);
    return (_radiansToDegrees(theta) + 360.0) % 360.0;
  }

  // --- Private GeoFire Math Helpers ---

  static double _degreesToRadians(double degrees) => degrees * (pi / 180.0);
  static double _radiansToDegrees(double radians) => radians * (180.0 / pi);
  static double _log2(double x) => log(x) / ln2;

  static double _wrapLongitude(double longitude) {
    if (longitude <= 180.0 && longitude >= -180.0) return longitude;
    final adjusted = longitude + 180.0;
    if (adjusted > 0) {
      return (adjusted % 360.0) - 180.0;
    } else {
      return 180.0 - ((-adjusted) % 360.0);
    }
  }

  static double _metersToLongitudeDegrees(double distanceMeters, double latitude) {
    final radians = _degreesToRadians(latitude);
    final num = cos(radians) * _earthEqRadius * pi / 180.0;
    final denom = 1.0 / sqrt(1.0 - _e2 * sin(radians) * sin(radians));
    final deltaDeg = num * denom;
    if (deltaDeg < _epsilon) {
      return distanceMeters > 0 ? 360.0 : 0.0;
    } else {
      return min(360.0, distanceMeters / deltaDeg);
    }
  }

  static double _longitudeBitsForResolution(double resolution, double latitude) {
    final degs = _metersToLongitudeDegrees(resolution, latitude);
    return (degs.abs() > 0.000001) ? max(1.0, _log2(360.0 / degs)) : 1.0;
  }

  static double _latitudeBitsForResolution(double resolution) {
    return min(_log2(_earthMeriCircumference / 2.0 / resolution), _maximumBitsPrecision.toDouble());
  }

  static int _boundingBoxBits(double lat, double lng, double sizeMeters) {
    final latDeltaDegrees = sizeMeters / _metersPerDegreeLatitude;
    final latitudeNorth = min(90.0, lat + latDeltaDegrees);
    final latitudeSouth = max(-90.0, lat - latDeltaDegrees);
    final bitsLat = (_latitudeBitsForResolution(sizeMeters).floor()) * 2;
    final bitsLongNorth = (_longitudeBitsForResolution(sizeMeters, latitudeNorth).floor()) * 2 - 1;
    final bitsLongSouth = (_longitudeBitsForResolution(sizeMeters, latitudeSouth).floor()) * 2 - 1;
    return min(min(bitsLat, bitsLongNorth), min(bitsLongSouth, _maximumBitsPrecision));
  }

  static List<List<double>> _boundingBoxCoordinates(double lat, double lng, double radiusMeters) {
    final latDegrees = radiusMeters / _metersPerDegreeLatitude;
    final latitudeNorth = min(90.0, lat + latDegrees);
    final latitudeSouth = max(-90.0, lat - latDegrees);
    final longDegsNorth = _metersToLongitudeDegrees(radiusMeters, latitudeNorth);
    final longDegsSouth = _metersToLongitudeDegrees(radiusMeters, latitudeSouth);
    final longDegs = max(longDegsNorth, longDegsSouth);

    return [
      [lat, lng],
      [lat, _wrapLongitude(lng - longDegs)],
      [lat, _wrapLongitude(lng + longDegs)],
      [latitudeNorth, lng],
      [latitudeNorth, _wrapLongitude(lng - longDegs)],
      [latitudeNorth, _wrapLongitude(lng + longDegs)],
      [latitudeSouth, lng],
      [latitudeSouth, _wrapLongitude(lng - longDegs)],
      [latitudeSouth, _wrapLongitude(lng + longDegs)],
    ];
  }

  static GeohashRange _geohashQuery(String hash, int bits) {
    final precision = (bits / _bitsPerChar).ceil();
    if (hash.length < precision) {
      return GeohashRange(hash, '$hash~');
    }
    final truncated = hash.substring(0, precision);
    final base = truncated.substring(0, truncated.length - 1);
    final lastChar = truncated[truncated.length - 1];
    final lastValue = _base32.indexOf(lastChar);
    final significantBits = bits - (base.length * _bitsPerChar);
    final unusedBits = _bitsPerChar - significantBits;
    final startValue = (lastValue >> unusedBits) << unusedBits;
    final endValue = startValue + (1 << unusedBits);
    if (endValue > 31) {
      return GeohashRange('$base${_base32[startValue]}', '$base~');
    } else {
      return GeohashRange('$base${_base32[startValue]}', '$base${_base32[endValue]}');
    }
  }
}
