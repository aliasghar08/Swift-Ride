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

  /// Phone numbers notified when this user raises an SOS.
  ///
  /// The `triggerSos` Cloud Function resolves these to SwiftRide accounts and
  /// pushes to their devices. Contacts without an account are reported back as
  /// unreachable rather than silently counted as notified.
  final List<String> trustedContacts;
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
    this.trustedContacts = const [],
    required this.createdAt,
  });

  /// An empty signed-out user.
  ///
  /// Replaces a fabricated default ("Alex Morgan", +92 300 1234567, 42 rides)
  /// that the app displayed as the signed-in account before authentication.
  factory AppUser.guest() => AppUser(
        id: '',
        phone: '',
        fullName: '',
        role: UserRole.rider,
        rating: 0,
        totalRides: 0,
        createdAt: DateTime.now(),
      );

  /// Normalises a phone number to digits with an optional leading '+'.
  ///
  /// Returns null when the input cannot be a phone number, so callers can reject
  /// it instead of storing something useless for emergency dispatch.
  static String? normalizePhone(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final hasPlus = trimmed.startsWith('+');
    final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 9 || digits.length > 15) return null;

    return hasPlus ? '+$digits' : digits;
  }

  AppUser copyWith({
    String? id,
    String? phone,
    String? email,
    String? fullName,
    UserRole? role,
    double? rating,
    int? totalRides,
    List<String>? fcmTokens,
    List<String>? trustedContacts,
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
      trustedContacts: trustedContacts ?? this.trustedContacts,
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
      'trustedContacts': trustedContacts,
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
      trustedContacts:
          (map['trustedContacts'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
