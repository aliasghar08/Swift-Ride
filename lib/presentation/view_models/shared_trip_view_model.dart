import 'dart:math' as math;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../services/native/native_device_service.dart';

/// A single coordinate parsed from a shared-trip response.
class SharedTripPoint {
  final double latitude;
  final double longitude;
  final String address;

  const SharedTripPoint({
    required this.latitude,
    required this.longitude,
    this.address = '',
  });

  /// Parses the `{geopoint: {latitude, longitude}, address}` shape written by
  /// the `requestRide` Cloud Function. Returns null when coordinates are
  /// absent — never a hardcoded fallback location.
  static SharedTripPoint? fromMap(dynamic raw) {
    if (raw is! Map) return null;
    final geo = raw['geopoint'];
    final lat = (geo is Map ? geo['latitude'] : raw['latitude']) as num?;
    final lng = (geo is Map ? geo['longitude'] : raw['longitude']) as num?;
    if (lat == null || lng == null) return null;
    return SharedTripPoint(
      latitude: lat.toDouble(),
      longitude: lng.toDouble(),
      address: (raw['address'] as String?) ?? '',
    );
  }
}

/// Live details of a trip tracked through a public share link.
///
/// Everything here comes from the `getSharedTrip` Cloud Function. Nothing is
/// invented: the previous implementation rendered a hardcoded rider and driver
/// ("Alex Morgan", "Marcus Vance", "7XYZ890") and derived its markers from the
/// *viewer's* own GPS rather than the shared trip.
class SharedTripInfo {
  final String status;
  final SharedTripPoint? pickup;
  final SharedTripPoint? dropoff;
  final double? driverLatitude;
  final double? driverLongitude;
  final double driverHeading;
  final String? vehicleLabel;
  final double? driverRating;

  const SharedTripInfo({
    required this.status,
    this.pickup,
    this.dropoff,
    this.driverLatitude,
    this.driverLongitude,
    this.driverHeading = 0,
    this.vehicleLabel,
    this.driverRating,
  });

  bool get hasDriverFix => driverLatitude != null && driverLongitude != null;

  static SharedTripInfo? fromResponse(Map<String, dynamic> data) {
    final driverInfo = data['driverInfo'];
    final tracking = data['liveTracking'];

    String? vehicleLabel;
    double? rating;
    if (driverInfo is Map) {
      final parts = [
        driverInfo['vehicleColor'],
        driverInfo['vehicleMake'],
        driverInfo['vehicleModel'],
      ].whereType<String>().where((p) => p.trim().isNotEmpty).toList();
      vehicleLabel = parts.isEmpty ? null : parts.join(' ');
      final plate = driverInfo['vehiclePlate'];
      if (plate is String && plate.trim().isNotEmpty) {
        vehicleLabel = vehicleLabel == null ? plate : '$vehicleLabel • $plate';
      }
      rating = (driverInfo['rating'] as num?)?.toDouble();
    }

    double? lat;
    double? lng;
    double heading = 0;
    if (tracking is Map) {
      lat = (tracking['lat'] as num?)?.toDouble();
      lng = (tracking['lng'] as num?)?.toDouble();
      heading = (tracking['heading'] as num?)?.toDouble() ?? 0;
    }

    return SharedTripInfo(
      status: (data['status'] as String?) ?? 'UNKNOWN',
      pickup: SharedTripPoint.fromMap(data['pickup']),
      dropoff: SharedTripPoint.fromMap(data['dropoff']),
      driverLatitude: lat,
      driverLongitude: lng,
      driverHeading: heading,
      vehicleLabel: vehicleLabel,
      driverRating: rating,
    );
  }
}

/// ViewModel managing Shared Trip public tracking display and ETA metrics.
class SharedTripViewModel extends ChangeNotifier {
  final NativeDeviceService _deviceService;
  final String? token;

  SharedTripInfo? _info;
  String? _error;
  bool _isLoading = false;
  bool _isCopied = false;

  SharedTripViewModel({
    this.token,
    NativeDeviceService? deviceService,
  }) : _deviceService = deviceService ?? NativeDeviceService();

  SharedTripInfo? get info => _info;
  String? get error => _error;
  bool get isLoading => _isLoading;
  bool get isCopied => _isCopied;
  bool get hasToken => token != null && token!.isNotEmpty;

  String get shareUrl => 'https://swiftride.app/track?token=${token ?? ''}';

  /// Loads the shared trip. Surfaces an honest error when the link is missing,
  /// invalid or expired.
  Future<void> load() async {
    if (!hasToken) {
      _error = 'This tracking link is missing its token and cannot be opened.';
      notifyListeners();
      return;
    }
    if (Firebase.apps.isEmpty) {
      _error = 'Tracking needs an internet connection.';
      notifyListeners();
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('getSharedTrip')
          .call(<String, dynamic>{'shareToken': token});

      _info = SharedTripInfo.fromResponse(res.data as Map<String, dynamic>);
    } on FirebaseFunctionsException catch (e) {
      _error = switch (e.code) {
        'not-found' => 'This tracking link is invalid or has expired.',
        'invalid-argument' => 'This tracking link is malformed.',
        _ => 'We could not load this trip right now. Please try again.',
      };
    } catch (e) {
      debugPrint('[SharedTripViewModel] load failed: $e');
      _error = 'We could not load this trip right now. Please try again.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> copyShareLink() async {
    if (!hasToken) return;
    await Clipboard.setData(ClipboardData(text: shareUrl));
    _isCopied = true;
    await _deviceService.triggerHaptic('selection');
    notifyListeners();

    await Future.delayed(const Duration(seconds: 3));
    _isCopied = false;
    notifyListeners();
  }

  /// Remaining minutes derived from the driver's live position.
  ///
  /// Returns null when there is nothing real to base an estimate on, so the UI
  /// omits the ETA instead of showing an invented number.
  int? estimateRemainingMinutes() {
    final info = _info;
    if (info == null || !info.hasDriverFix) return null;

    final dest = (info.status == 'ACCEPTED' || info.status == 'DRIVER_ARRIVED')
        ? info.pickup
        : info.dropoff;
    if (dest == null) return null;

    // Equirectangular approximation, ample for a city-scale ETA.
    const metresPerDegLat = 111320.0;
    final dLat = (dest.latitude - info.driverLatitude!) * metresPerDegLat;
    final dLng = (dest.longitude - info.driverLongitude!) *
        metresPerDegLat *
        math.cos(info.driverLatitude! * math.pi / 180);
    final distanceKm = math.sqrt(dLat * dLat + dLng * dLng) / 1000.0;

    // Urban average ~24 km/h -> 2.5 min per km.
    return (distanceKm * 2.5).ceil().clamp(1, 240);
  }
}
