import 'ride_status.dart';
import 'location_point_model.dart';

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
  final double commissionAmount; // $0 in year 1
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
        if (driverLocation != null) 'driverLocation': driverLocation!.toMap(),
      };

  factory RideModel.fromMap(Map<String, dynamic> map, {String? docId}) {
    return RideModel(
      id: docId ?? map['id'] ?? '',
      riderId: map['riderId'] ?? '',
      driverId: map['driverId'],
      status: RideStatus.fromString(map['status']),
      pickup: LocationPoint.fromMap(map['pickup'] as Map<String, dynamic>? ?? {}),
      dropoff: LocationPoint.fromMap(map['dropoff'] as Map<String, dynamic>? ?? {}),
      offeredFare: (map['offeredFare'] as num?)?.toDouble() ?? 0.0,
      acceptedFare: (map['acceptedFare'] as num?)?.toDouble(),
      suggestedFare: (map['suggestedFare'] as num?)?.toDouble() ?? 0.0,
      distanceKm: (map['distanceKm'] as num?)?.toDouble() ?? 0.0,
      durationMin: (map['durationMin'] as num?)?.toDouble() ?? 0.0,
      commissionAmount: (map['commissionAmount'] as num?)?.toDouble() ?? 0.0,
      paymentIntentId: map['paymentIntentId'],
      paymentStatus: map['paymentStatus'] ?? 'pending',
      paymentMethod: map['paymentMethod'] as String?,
      safetyFlags: (map['safetyFlags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      shareToken: map['shareToken'],
      pin: map['pin'] ?? '1234',
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      completedAt: map['completedAt'] != null
          ? DateTime.tryParse(map['completedAt'].toString())
          : null,
      driverLocation: DriverTelemetry.fromMap(
        map['driverLocation'] as Map<String, dynamic>?,
      ),
    );
  }
}
