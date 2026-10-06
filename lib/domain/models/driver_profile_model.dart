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
    // 0 means "position unknown" — a real fix is written by the location
    // channel. This used to default to Islamabad city centre, so an
    // unlocated driver appeared to be sitting in the capital.
    this.latitude = 0,
    this.longitude = 0,
    required this.createdAt,
  });

  /// A profile that claims nothing: real identity, zeroed figures.
  ///
  /// Used instead of a fabricated placeholder driver. Callers should hydrate it
  /// from Firestore via `DriverProvider.loadForUser`.
  factory DriverProfile.empty({String userId = ''}) => DriverProfile(
        userId: userId,
        licenseNumber: '',
        vehicle: const VehicleInfo(
          make: '',
          model: '',
          year: 0,
          plate: '',
          color: '',
        ),
        isVerified: false,
        isOnline: false,
        subscriptionExpiresAt: DateTime.fromMillisecondsSinceEpoch(0),
        rating: 0,
        totalRides: 0,
        totalEarnings: 0,
        createdAt: DateTime.now(),
      );

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
      latitude: (loc?['lat'] as num?)?.toDouble() ?? 33.6844,
      longitude: (loc?['lng'] as num?)?.toDouble() ?? 73.0479,
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
