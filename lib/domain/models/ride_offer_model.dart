class RideOffer {
  final String id;
  final String rideId;
  final String driverId;
  final String driverName;
  final double counterFare;
  final int etaMinutes;
  final String vehicleSummary;
  final double driverRating;
  final String status; // PENDING, ACCEPTED, REJECTED, EXPIRED
  final DateTime createdAt;

  const RideOffer({
    required this.id,
    required this.rideId,
    required this.driverId,
    required this.driverName,
    required this.counterFare,
    required this.etaMinutes,
    required this.vehicleSummary,
    this.driverRating = 4.9,
    this.status = 'PENDING',
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'rideId': rideId,
        'driverId': driverId,
        'driverName': driverName,
        'counterFare': counterFare,
        'etaMinutes': etaMinutes,
        'vehicleSummary': vehicleSummary,
        'driverRating': driverRating,
        'status': status,
        'createdAt': createdAt.toIso8601String(),
      };

  factory RideOffer.fromMap(Map<String, dynamic> map, {String? docId}) {
    final vInfo = map['vehicleInfo'] as Map<String, dynamic>?;
    final summary = vInfo != null
        ? '${vInfo['color'] ?? ''} ${vInfo['make'] ?? ''} ${vInfo['model'] ?? ''} (${vInfo['plate'] ?? ''})'
        : map['vehicleSummary'] ?? 'Toyota Camry (Silver)';

    return RideOffer(
      id: docId ?? map['id'] ?? '',
      rideId: map['rideId'] ?? '',
      driverId: map['driverId'] ?? '',
      driverName: map['driverName'] ?? 'Driver Partner',
      counterFare: (map['counterFare'] as num?)?.toDouble() ?? 10.0,
      etaMinutes: (map['etaMinutes'] as num?)?.toInt() ?? 5,
      vehicleSummary: summary,
      driverRating: (map['driverRating'] as num?)?.toDouble() ?? 4.9,
      status: map['status'] ?? 'PENDING',
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
