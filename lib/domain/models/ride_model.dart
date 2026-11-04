import 'ride_status.dart';
import 'location_point_model.dart';
import 'vehicle_type.dart';

/// Live position of the driver assigned to a ride, mirrored onto the ride
/// document by the `updateDriverLocation` Cloud Function.
///
/// This is the ONLY legitimate source for a rider's driver marker. It is never
/// fabricated from the rider's own GPS.
class DriverTelemetry {
  final double latitude;
  final double longitude;
  final double heading;
  final double speed;
  final DateTime updatedAt;

  const DriverTelemetry({
    required this.latitude,
    required this.longitude,
    this.heading = 0.0,
    this.speed = 0.0,
    required this.updatedAt,
  });

  /// A fix older than this must not be rendered as "where your driver is".
  static const Duration staleAfter = Duration(seconds: 45);

  bool get isStale => DateTime.now().difference(updatedAt) > staleAfter;

  static DriverTelemetry? fromMap(Map<String, dynamic>? map) {
    if (map == null) return null;
    final lat = (map['lat'] as num?)?.toDouble();
    final lng = (map['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;

    final rawUpdated = map['updatedAt'];
    final updatedAt = rawUpdated is num
        ? DateTime.fromMillisecondsSinceEpoch(rawUpdated.toInt())
        : DateTime.tryParse(rawUpdated?.toString() ?? '') ?? DateTime.now();

    return DriverTelemetry(
      latitude: lat,
      longitude: lng,
      heading: (map['heading'] as num?)?.toDouble() ?? 0.0,
      speed: (map['speed'] as num?)?.toDouble() ?? 0.0,
      updatedAt: updatedAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'lat': latitude,
        'lng': longitude,
        'heading': heading,
        'speed': speed,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
      };
}

class RideModel {
  final String id;
  final String riderId;
  final String? driverId;
  final RideStatus status;
  final LocationPoint pickup;
  final LocationPoint dropoff;
  final double offeredFare;
  final double? acceptedFare;
  final double suggestedFare;
  final double distanceKm;
  final double durationMin;
  final double commissionAmount; // 2% always
  final String? paymentIntentId;
  final String paymentStatus;

  /// Identifier of the rail the rider chose (see [PaymentRail.id]). Null until
  /// the rider picks one; the server defaults to cash.
  final String? paymentMethod;
  final List<String> safetyFlags;
  final String? shareToken;
  final String pin;
  final DateTime createdAt;
  final DateTime? completedAt;
  final DriverTelemetry? driverLocation;
  final String vehicleType;
  final int bookedSeats;
  final String? seatPreference;
  final double? maxAutoAcceptFare;
  final bool isAutoNegotiateEnabled;
  final double? cashReceived;
  final double? changeDue;

  int get totalSeats => VehicleTypeX.fromString(vehicleType).seats;
  int get emptySeats => (totalSeats - bookedSeats).clamp(0, totalSeats);
  bool get hasEmptySeats => emptySeats > 0 || bookedSeats < totalSeats;

  const RideModel({
    required this.id,
    required this.riderId,
    this.driverId,
    this.status = RideStatus.requested,
    required this.pickup,
    required this.dropoff,
    required this.offeredFare,
    this.acceptedFare,
    required this.suggestedFare,
    required this.distanceKm,
    required this.durationMin,
    this.commissionAmount = 0.0,
    this.paymentIntentId,
    this.paymentStatus = 'pending',
    this.paymentMethod,
    this.safetyFlags = const [],
    this.shareToken,
    required this.pin,
    required this.createdAt,
    this.completedAt,
    this.driverLocation,
    this.vehicleType = 'car',
    this.bookedSeats = 1,
    this.seatPreference,
    this.maxAutoAcceptFare,
    this.isAutoNegotiateEnabled = false,
    this.cashReceived,
    this.changeDue,
  });

  RideModel copyWith({
    String? id,
    String? riderId,
    String? driverId,
    RideStatus? status,
    LocationPoint? pickup,
    LocationPoint? dropoff,
    double? offeredFare,
    double? acceptedFare,
    double? suggestedFare,
    double? distanceKm,
    double? durationMin,
    double? commissionAmount,
    String? paymentIntentId,
    String? paymentStatus,
    String? paymentMethod,
    List<String>? safetyFlags,
    String? shareToken,
    String? pin,
    DateTime? createdAt,
    DateTime? completedAt,
    DriverTelemetry? driverLocation,
    String? vehicleType,
    int? bookedSeats,
    String? seatPreference,
    double? maxAutoAcceptFare,
    bool? isAutoNegotiateEnabled,
    double? cashReceived,
    double? changeDue,
  }) {
    return RideModel(
      id: id ?? this.id,
      riderId: riderId ?? this.riderId,
      driverId: driverId ?? this.driverId,
      status: status ?? this.status,
      pickup: pickup ?? this.pickup,
      dropoff: dropoff ?? this.dropoff,
      offeredFare: offeredFare ?? this.offeredFare,
      acceptedFare: acceptedFare ?? this.acceptedFare,
      suggestedFare: suggestedFare ?? this.suggestedFare,
      distanceKm: distanceKm ?? this.distanceKm,
      durationMin: durationMin ?? this.durationMin,
      commissionAmount: commissionAmount ?? this.commissionAmount,
      paymentIntentId: paymentIntentId ?? this.paymentIntentId,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      safetyFlags: safetyFlags ?? this.safetyFlags,
      shareToken: shareToken ?? this.shareToken,
      pin: pin ?? this.pin,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
      driverLocation: driverLocation ?? this.driverLocation,
      vehicleType: vehicleType ?? this.vehicleType,
      bookedSeats: bookedSeats ?? this.bookedSeats,
      seatPreference: seatPreference ?? this.seatPreference,
      maxAutoAcceptFare: maxAutoAcceptFare ?? this.maxAutoAcceptFare,
      isAutoNegotiateEnabled: isAutoNegotiateEnabled ?? this.isAutoNegotiateEnabled,
      cashReceived: cashReceived ?? this.cashReceived,
      changeDue: changeDue ?? this.changeDue,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'riderId': riderId,
        'driverId': driverId,
        'status': status.toDbString(),
        'pickup': pickup.toMap(),
        'dropoff': dropoff.toMap(),
        'offeredFare': offeredFare,
        'acceptedFare': acceptedFare,
        'suggestedFare': suggestedFare,
        'distanceKm': distanceKm,
        'durationMin': durationMin,
        'commissionAmount': commissionAmount,
        'paymentIntentId': paymentIntentId,
        'paymentStatus': paymentStatus,
        'paymentMethod': paymentMethod,
        'safetyFlags': safetyFlags,
        'shareToken': shareToken,
        'pin': pin,
        'createdAt': createdAt.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'vehicleType': vehicleType,
        'bookedSeats': bookedSeats,
        if (seatPreference != null) 'seatPreference': seatPreference,
        if (maxAutoAcceptFare != null) 'maxAutoAcceptFare': maxAutoAcceptFare,
        'isAutoNegotiateEnabled': isAutoNegotiateEnabled,
        if (cashReceived != null) 'cashReceived': cashReceived,
        if (changeDue != null) 'changeDue': changeDue,
        if (driverLocation != null) 'driverLocation': driverLocation!.toMap(),
      };

  static double _parseDouble(dynamic val, [double fallback = 0.0]) {
    if (val == null) return fallback;
    if (val is num) return val.toDouble();
    if (val is String) {
      return double.tryParse(val) ?? fallback;
    }
    return fallback;
  }

  static double? _parseNullableDouble(dynamic val) {
    if (val == null) return null;
    if (val is num) return val.toDouble();
    if (val is String) {
      return double.tryParse(val);
    }
    return null;
  }

  static int _parseInt(dynamic val, [int fallback = 0]) {
    if (val == null) return fallback;
    if (val is num) return val.toInt();
    if (val is String) {
      return int.tryParse(val) ?? (double.tryParse(val)?.toInt() ?? fallback);
    }
    return fallback;
  }

  static DateTime? _parseNullableDateTime(dynamic val) {
    if (val == null) return null;
    if (val is DateTime) return val;
    try {
      final dt = (val as dynamic).toDate();
      if (dt is DateTime) return dt;
    } catch (_) {}
    if (val is num) {
      return DateTime.fromMillisecondsSinceEpoch(val.toInt());
    }
    return DateTime.tryParse(val.toString());
  }

  static DateTime _parseDateTime(dynamic val) {
    return _parseNullableDateTime(val) ?? DateTime.now();
  }

  factory RideModel.fromMap(Map<String, dynamic> map, {String? docId}) {
    return RideModel(
      id: docId ?? map['id']?.toString() ?? '',
      riderId: map['riderId']?.toString() ?? '',
      driverId: map['driverId']?.toString(),
      status: RideStatus.fromString(map['status']),
      pickup: () {
        try {
          if (map['pickup'] is Map) {
            return LocationPoint.fromMap(Map<String, dynamic>.from(map['pickup'] as Map));
          }
        } catch (_) {}
        return const LocationPoint(latitude: 0.0, longitude: 0.0, address: '');
      }(),
      dropoff: () {
        try {
          if (map['dropoff'] is Map) {
            return LocationPoint.fromMap(Map<String, dynamic>.from(map['dropoff'] as Map));
          }
        } catch (_) {}
        return const LocationPoint(latitude: 0.0, longitude: 0.0, address: '');
      }(),
      offeredFare: _parseDouble(map['offeredFare']),
      acceptedFare: _parseNullableDouble(map['acceptedFare']),
      suggestedFare: _parseDouble(map['suggestedFare']),
      distanceKm: _parseDouble(map['distanceKm']),
      durationMin: _parseDouble(map['durationMin']),
      commissionAmount: _parseDouble(map['commissionAmount']),
      paymentIntentId: map['paymentIntentId']?.toString(),
      paymentStatus: map['paymentStatus']?.toString() ?? 'pending',
      paymentMethod: map['paymentMethod']?.toString(),
      safetyFlags: (map['safetyFlags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      shareToken: map['shareToken']?.toString(),
      pin: map['pin']?.toString() ?? '1234',
      createdAt: _parseDateTime(map['createdAt']),
      completedAt: _parseNullableDateTime(map['completedAt']),
      driverLocation: DriverTelemetry.fromMap(
        map['driverLocation'] is Map
            ? Map<String, dynamic>.from(map['driverLocation'] as Map)
            : null,
      ),
      vehicleType: map['vehicleType']?.toString() ?? 'car',
      bookedSeats: _parseInt(map['bookedSeats'], 1),
      seatPreference: map['seatPreference'] as String?,
      maxAutoAcceptFare: _parseNullableDouble(map['maxAutoAcceptFare']),
      isAutoNegotiateEnabled: map['isAutoNegotiateEnabled'] == true,
      cashReceived: _parseNullableDouble(map['cashReceived']),
      changeDue: _parseNullableDouble(map['changeDue']),
    );
  }
}
