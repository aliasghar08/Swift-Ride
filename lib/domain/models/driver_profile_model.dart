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
  final String? gender;
  final bool isGenderVerified;
  final bool femalePassengersOnly;
  final String? captainInviteCode;
  final String? referredByDriverUid;
  final String? referredByCode;
  final int verifiedReferralsCount;
  final List<String> badges;
  final DateTime? feeWaiverUntil;
  final int weeklyCompletedRides;

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
    this.gender,
    this.isGenderVerified = false,
    this.femalePassengersOnly = false,
    this.captainInviteCode,
    this.referredByDriverUid,
    this.referredByCode,
    this.verifiedReferralsCount = 0,
    this.badges = const [],
    this.feeWaiverUntil,
    this.weeklyCompletedRides = 0,
  });

  /// True if driver has an active 0% fee waiver granted via promo or referrals.
  bool get isFeeWaiverActive =>
      feeWaiverUntil != null && feeWaiverUntil!.isAfter(DateTime.now());

  /// Shareable referral link for peer drivers on Firebase Hosting.
  String get captainReferralLink =>
      'https://swift-ride-5ab75.web.app/join?code=${captainInviteCode ?? "CAPT786"}';

  /// Effective platform fee rate: 0.0% if waiver is active, else standard 2.0% (0.02).
  double get effectivePlatformFeeRate => isFeeWaiverActive ? 0.0 : 0.02;

  /// True if captain unlocked the 5-Driver Referral Milestone badge.
  bool get isFoundingCaptain => badges.contains('FOUNDING_CAPTAIN');

  /// Days remaining in active fee waiver.
  int get waiverDaysRemaining {
    if (!isFeeWaiverActive) return 0;
    return feeWaiverUntil!.difference(DateTime.now()).inDays.clamp(0, 365);
  }

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
        gender: null,
        isGenderVerified: false,
        femalePassengersOnly: false,
        captainInviteCode: null,
        referredByDriverUid: null,
        referredByCode: null,
        verifiedReferralsCount: 0,
        badges: const [],
        feeWaiverUntil: null,
        weeklyCompletedRides: 0,
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
    String? gender,
    bool? isGenderVerified,
    bool? femalePassengersOnly,
    String? captainInviteCode,
    String? referredByDriverUid,
    String? referredByCode,
    int? verifiedReferralsCount,
    List<String>? badges,
    DateTime? feeWaiverUntil,
    int? weeklyCompletedRides,
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
      gender: gender ?? this.gender,
      isGenderVerified: isGenderVerified ?? this.isGenderVerified,
      femalePassengersOnly: femalePassengersOnly ?? this.femalePassengersOnly,
      captainInviteCode: captainInviteCode ?? this.captainInviteCode,
      referredByDriverUid: referredByDriverUid ?? this.referredByDriverUid,
      referredByCode: referredByCode ?? this.referredByCode,
      verifiedReferralsCount: verifiedReferralsCount ?? this.verifiedReferralsCount,
      badges: badges ?? this.badges,
      feeWaiverUntil: feeWaiverUntil ?? this.feeWaiverUntil,
      weeklyCompletedRides: weeklyCompletedRides ?? this.weeklyCompletedRides,
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
      if (gender != null) 'gender': gender,
      'isGenderVerified': isGenderVerified,
      'femalePassengersOnly': femalePassengersOnly,
      if (captainInviteCode != null) 'captainInviteCode': captainInviteCode,
      'captainReferralLink': captainReferralLink,
      if (referredByDriverUid != null) 'referredByDriverUid': referredByDriverUid,
      if (referredByCode != null) 'referredByCode': referredByCode,
      'verifiedReferralsCount': verifiedReferralsCount,
      'badges': badges,
      if (feeWaiverUntil != null) 'feeWaiverUntil': feeWaiverUntil!.toIso8601String(),
      'weeklyCompletedRides': weeklyCompletedRides,
    };
  }

  factory DriverProfile.fromMap(Map<String, dynamic> map, {String? docId}) {
    final loc = map['currentLocation'] as Map<String, dynamic>?;
    DateTime? parsedWaiver;
    if (map['feeWaiverUntil'] != null) {
      final raw = map['feeWaiverUntil'];
      if (raw is DateTime) {
        parsedWaiver = raw;
      } else if (raw is String) {
        parsedWaiver = DateTime.tryParse(raw);
      } else if (raw.runtimeType.toString().contains('Timestamp')) {
        try {
          parsedWaiver = (raw as dynamic).toDate();
        } catch (_) {}
      }
    }

    final rawBadges = map['badges'] as List<dynamic>?;
    final parsedBadges = rawBadges != null
        ? rawBadges.map((e) => e.toString()).toList()
        : const <String>[];

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
      latitude: (loc?['lat'] as num?)?.toDouble() ??
          (map['latitude'] as num?)?.toDouble() ??
          (map['lat'] as num?)?.toDouble() ??
          0.0,
      longitude: (loc?['lng'] as num?)?.toDouble() ??
          (map['longitude'] as num?)?.toDouble() ??
          (map['lng'] as num?)?.toDouble() ??
          0.0,
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      gender: map['gender'] as String?,
      isGenderVerified: map['isGenderVerified'] == true,
      femalePassengersOnly: map['femalePassengersOnly'] == true,
      captainInviteCode: map['captainInviteCode'] as String?,
      referredByDriverUid: map['referredByDriverUid'] as String?,
      referredByCode: map['referredByCode'] as String?,
      verifiedReferralsCount: (map['verifiedReferralsCount'] as num?)?.toInt() ?? 0,
      badges: parsedBadges,
      feeWaiverUntil: parsedWaiver,
      weeklyCompletedRides: (map['weeklyCompletedRides'] as num?)?.toInt() ?? 0,
    );
  }
}
