import 'ride_status.dart';
import 'location_point_model.dart';

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
  final List<String> safetyFlags;
  final String? shareToken;
  final String pin;
  final DateTime createdAt;
  final DateTime? completedAt;

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
    this.safetyFlags = const [],
    this.shareToken,
    required this.pin,
    required this.createdAt,
    this.completedAt,
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
    List<String>? safetyFlags,
    String? shareToken,
    String? pin,
    DateTime? createdAt,
    DateTime? completedAt,
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
      safetyFlags: safetyFlags ?? this.safetyFlags,
      shareToken: shareToken ?? this.shareToken,
      pin: pin ?? this.pin,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
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
        'safetyFlags': safetyFlags,
        'shareToken': shareToken,
        'pin': pin,
        'createdAt': createdAt.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
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
      safetyFlags: (map['safetyFlags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      shareToken: map['shareToken'],
      pin: map['pin'] ?? '1234',
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      completedAt: map['completedAt'] != null
          ? DateTime.tryParse(map['completedAt'].toString())
          : null,
    );
  }
}
