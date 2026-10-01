import 'vehicle_info_model.dart';
import 'subscription_model.dart';

class DriverProfile {
  final String userId;
  String get id => userId;
  final String licenseNumber;
  final VehicleInfo vehicle;
  final bool isVerified;
  final bool isOnline;
  final SubscriptionStatus subscriptionStatus;
  final DateTime subscriptionExpiresAt;
  final String? stripeAccountId;
  final String payoutStatus;
  final double rating;
  final int totalRides;
  final double totalEarnings;
  final double latitude;
  final double longitude;
  final DateTime createdAt;

  const DriverProfile({
    required this.userId,
    required this.licenseNumber,
    required this.vehicle,
    this.isVerified = false,
    this.isOnline = false,
    this.subscriptionStatus = SubscriptionStatus.trial,
    required this.subscriptionExpiresAt,
    this.stripeAccountId,
    this.payoutStatus = 'pending',
    this.rating = 4.9,
    this.totalRides = 0,
    this.totalEarnings = 0.0,
    this.latitude = 37.7749,
    this.longitude = -122.4194,
    required this.createdAt,
  });

  DriverProfile copyWith({
    String? userId,
    String? licenseNumber,
    VehicleInfo? vehicle,
    bool? isVerified,
    bool? isOnline,
    SubscriptionStatus? subscriptionStatus,
    DateTime? subscriptionExpiresAt,
    String? stripeAccountId,
    String? payoutStatus,
    double? rating,
    int? totalRides,
    double? totalEarnings,
    double? latitude,
    double? longitude,
    DateTime? createdAt,
  }) {
    return DriverProfile(
      userId: userId ?? this.userId,
      licenseNumber: licenseNumber ?? this.licenseNumber,
      vehicle: vehicle ?? this.vehicle,
      isVerified: isVerified ?? this.isVerified,
      isOnline: isOnline ?? this.isOnline,
      subscriptionStatus: subscriptionStatus ?? this.subscriptionStatus,
      subscriptionExpiresAt: subscriptionExpiresAt ?? this.subscriptionExpiresAt,
      stripeAccountId: stripeAccountId ?? this.stripeAccountId,
      payoutStatus: payoutStatus ?? this.payoutStatus,
      rating: rating ?? this.rating,
      totalRides: totalRides ?? this.totalRides,
      totalEarnings: totalEarnings ?? this.totalEarnings,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'licenseNumber': licenseNumber,
      ...vehicle.toMap(),
      'isVerified': isVerified,
      'isOnline': isOnline,
      'subscriptionStatus': subscriptionStatus.toDbString(),
      'subscriptionExpiresAt': subscriptionExpiresAt.toIso8601String(),
      'stripeAccountId': stripeAccountId,
      'payoutStatus': payoutStatus,
      'rating': rating,
      'totalRides': totalRides,
      'totalEarnings': totalEarnings,
      'currentLocation': {
        'lat': latitude,
        'lng': longitude,
      },
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory DriverProfile.fromMap(Map<String, dynamic> map, {String? docId}) {
    final loc = map['currentLocation'] as Map<String, dynamic>?;
    return DriverProfile(
      userId: docId ?? map['userId'] ?? '',
      licenseNumber: map['licenseNumber'] ?? '',
      vehicle: VehicleInfo.fromMap(map),
      isVerified: map['isVerified'] ?? false,
      isOnline: map['isOnline'] ?? false,
      subscriptionStatus: SubscriptionStatus.fromString(map['subscriptionStatus']),
      subscriptionExpiresAt: map['subscriptionExpiresAt'] != null
          ? DateTime.tryParse(map['subscriptionExpiresAt'].toString()) ?? DateTime.now()
          : DateTime.now().add(const Duration(days: 365)),
      stripeAccountId: map['stripeAccountId'],
      payoutStatus: map['payoutStatus'] ?? 'pending',
      rating: (map['rating'] as num?)?.toDouble() ?? 4.9,
      totalRides: (map['totalRides'] as num?)?.toInt() ?? 0,
      totalEarnings: (map['totalEarnings'] as num?)?.toDouble() ?? 0.0,
      latitude: (loc?['lat'] as num?)?.toDouble() ?? 37.7749,
      longitude: (loc?['lng'] as num?)?.toDouble() ?? -122.4194,
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
