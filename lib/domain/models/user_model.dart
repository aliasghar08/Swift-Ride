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
  final String? photoUrl;
  final String? authProvider;

  /// Active linked authentication providers (e.g. ['phone', 'google', 'apple']).
  final List<String> linkedProviders;

  /// User's gender ('female' | 'male' | null).
  final String? gender;

  /// Whether user's gender has been verified via CNIC or official document.
  final bool isGenderVerified;

  const AppUser({
    required this.id,
    this.phone = '',
    this.email,
    required this.fullName,
    required this.role,
    this.rating = 5.0,
    this.totalRides = 0,
    this.fcmTokens = const [],
    this.trustedContacts = const [],
    required this.createdAt,
    this.photoUrl,
    this.authProvider,
    this.linkedProviders = const [],
    this.gender,
    this.isGenderVerified = false,
  });

  /// An empty signed-out user.
  ///
  /// Replaces a fabricated default ("Alex Morgan", +92 300 1234567, 42 rides)
  /// that the app displayed as the signed-in account before authentication.
  factory AppUser.guest() => AppUser(
        id: '',
        phone: '',
        fullName: '',
        role: UserRole.passenger,
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
    String? photoUrl,
    String? authProvider,
    List<String>? linkedProviders,
    String? gender,
    bool? isGenderVerified,
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
      photoUrl: photoUrl ?? this.photoUrl,
      authProvider: authProvider ?? this.authProvider,
      linkedProviders: linkedProviders ?? this.linkedProviders,
      gender: gender ?? this.gender,
      isGenderVerified: isGenderVerified ?? this.isGenderVerified,
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
      if (photoUrl != null) 'photoUrl': photoUrl,
      if (authProvider != null) 'authProvider': authProvider,
      if (linkedProviders.isNotEmpty) 'linkedProviders': linkedProviders,
      if (gender != null) 'gender': gender,
      'isGenderVerified': isGenderVerified,
    };
  }

  factory AppUser.fromMap(Map<String, dynamic> map, {String? docId}) {
    final rawLinked = map['linkedProviders'];
    final List<String> resolvedLinked = rawLinked is List
        ? rawLinked.map((e) => e.toString()).toList()
        : (map['authProvider'] != null ? [map['authProvider'].toString()] : []);

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
      photoUrl: map['photoUrl'] as String?,
      authProvider: map['authProvider'] as String?,
      linkedProviders: resolvedLinked,
      gender: map['gender'] as String?,
      isGenderVerified: map['isGenderVerified'] == true,
    );
  }
}
