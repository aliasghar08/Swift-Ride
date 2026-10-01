import 'user_role.dart';

class AppUser {
  final String id;
  final String phone;
  final String? email;
  final String fullName;
  final UserRole role;
  final double rating;
  final int totalRides;
  final List<String> fcmTokens;
  final DateTime createdAt;

  const AppUser({
    required this.id,
    required this.phone,
    this.email,
    required this.fullName,
    required this.role,
    this.rating = 5.0,
    this.totalRides = 0,
    this.fcmTokens = const [],
    required this.createdAt,
  });

  AppUser copyWith({
    String? id,
    String? phone,
    String? email,
    String? fullName,
    UserRole? role,
    double? rating,
    int? totalRides,
    List<String>? fcmTokens,
    DateTime? createdAt,
  }) {
    return AppUser(
      id: id ?? this.id,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      fullName: fullName ?? this.fullName,
      role: role ?? this.role,
      rating: rating ?? this.rating,
      totalRides: totalRides ?? this.totalRides,
      fcmTokens: fcmTokens ?? this.fcmTokens,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'phone': phone,
      'email': email,
      'fullName': fullName,
      'role': role.toDbString(),
      'rating': rating,
      'totalRides': totalRides,
      'fcmTokens': fcmTokens,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory AppUser.fromMap(Map<String, dynamic> map, {String? docId}) {
    return AppUser(
      id: docId ?? map['id'] ?? '',
      phone: map['phone'] ?? '',
      email: map['email'],
      fullName: map['fullName'] ?? 'SwiftRide User',
      role: UserRole.fromString(map['role']),
      rating: (map['rating'] as num?)?.toDouble() ?? 5.0,
      totalRides: (map['totalRides'] as num?)?.toInt() ?? 0,
      fcmTokens: (map['fcmTokens'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
