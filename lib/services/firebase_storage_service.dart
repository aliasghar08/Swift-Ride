import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import '../domain/models/driver_document_model.dart';

/// Production service managing Cloud Storage uploads for documents, photos, and media.
///
/// Handles KYC verification documents, vehicle inspection photos, user profile avatars,
/// active ride chat attachments (images/videos/audio), and safety/emergency SOS evidence.
/// Provides safe fallback simulation when Firebase is offline or uninitialized in tests.
class FirebaseStorageService {
  static final FirebaseStorageService _instance = FirebaseStorageService._internal();
  factory FirebaseStorageService({FirebaseStorage? storage}) {
    if (storage != null) return FirebaseStorageService._custom(storage);
    return _instance;
  }
  FirebaseStorageService._internal() : _customStorage = null;
  FirebaseStorageService._custom(this._customStorage);

  final FirebaseStorage? _customStorage;

  // In-memory simulation store for testing & offline mode
  final Map<String, String> _memoryUrls = {};

  FirebaseStorage? get _storage {
    if (_customStorage != null) return _customStorage;
    try {
      if (Firebase.apps.isNotEmpty) {
        return FirebaseStorage.instance;
      }
    } catch (_) {}
    return null;
  }

  /// Uploads a raw byte buffer to [storagePath] with [mimeType] and returns its public download URL.
  Future<String> uploadBytes({
    required String storagePath,
    required Uint8List bytes,
    required String mimeType,
    Map<String, String>? customMetadata,
  }) async {
    final fs = _storage;
    if (fs == null) {
      final simUrl = 'https://firebasestorage.googleapis.com/v0/b/swift-ride-5ab75.appspot.com/o/${Uri.encodeComponent(storagePath)}?alt=media';
      _memoryUrls[storagePath] = simUrl;
      return simUrl;
    }

    final ref = fs.ref().child(storagePath);
    final metadata = SettableMetadata(
      contentType: mimeType,
      customMetadata: customMetadata,
    );

    final task = await ref.putData(bytes, metadata);
    final downloadUrl = await task.ref.getDownloadURL();
    _memoryUrls[storagePath] = downloadUrl;
    return downloadUrl;
  }

  /// Uploads a sensitive driver verification document (CNIC, Driving License, Registration).
  ///
  /// Stored at: `drivers/{driverId}/documents/{documentType}.{ext}`
  Future<String> uploadDriverDocument({
    required String driverId,
    required DriverDocumentType type,
    required Uint8List bytes,
    String mimeType = 'image/jpeg',
  }) async {
    final ext = _extensionForMime(mimeType);
    final path = 'drivers/$driverId/documents/${type.code}.$ext';
    return uploadBytes(
      storagePath: path,
      bytes: bytes,
      mimeType: mimeType,
      customMetadata: {
        'driverId': driverId,
        'documentType': type.code,
        'uploadedAt': DateTime.now().toIso8601String(),
      },
    );
  }

  /// Uploads a vehicle inspection photo (e.g., front with plate, interior cabin).
  ///
  /// Stored at: `drivers/{driverId}/vehicle/{photoType}.{ext}`
  Future<String> uploadVehiclePhoto({
    required String driverId,
    required String photoType, // 'front' | 'interior'
    required Uint8List bytes,
    String mimeType = 'image/jpeg',
  }) async {
    final ext = _extensionForMime(mimeType);
    final path = 'drivers/$driverId/vehicle/$photoType.$ext';
    return uploadBytes(
      storagePath: path,
      bytes: bytes,
      mimeType: mimeType,
      customMetadata: {
        'driverId': driverId,
        'photoType': photoType,
        'uploadedAt': DateTime.now().toIso8601String(),
      },
    );
  }

  /// Uploads a user (rider or driver) profile picture / avatar.
  ///
  /// Stored at: `users/{userId}/avatar.{ext}`
  Future<String> uploadUserProfilePhoto({
    required String userId,
    required Uint8List bytes,
    String mimeType = 'image/jpeg',
  }) async {
    final ext = _extensionForMime(mimeType);
    final path = 'users/$userId/avatar.$ext';
    return uploadBytes(
      storagePath: path,
      bytes: bytes,
      mimeType: mimeType,
      customMetadata: {
        'userId': userId,
        'uploadedAt': DateTime.now().toIso8601String(),
      },
    );
  }

  /// Uploads media for an active ride in-app chat message (photos, voice notes, video clips).
  ///
  /// Stored at: `rides/{rideId}/chat/{timestamp}_{fileName}`
  Future<String> uploadChatMedia({
    required String rideId,
    required String senderId,
    required Uint8List bytes,
    required String fileName,
    String mimeType = 'image/jpeg',
  }) async {
    final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path = 'rides/$rideId/chat/${timestamp}_$safeName';
    return uploadBytes(
      storagePath: path,
      bytes: bytes,
      mimeType: mimeType,
      customMetadata: {
        'rideId': rideId,
        'senderId': senderId,
        'uploadedAt': DateTime.now().toIso8601String(),
      },
    );
  }

  /// Uploads safety/emergency SOS evidence (photos, audio recordings, dashcam videos).
  ///
  /// Stored at: `safety_events/{eventId}/{timestamp}_{fileName}`
  Future<String> uploadSafetyEvidence({
    required String eventId,
    required Uint8List bytes,
    required String fileName,
    String mimeType = 'image/jpeg',
  }) async {
    final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path = 'safety_events/$eventId/${timestamp}_$safeName';
    return uploadBytes(
      storagePath: path,
      bytes: bytes,
      mimeType: mimeType,
      customMetadata: {
        'eventId': eventId,
        'uploadedAt': DateTime.now().toIso8601String(),
      },
    );
  }

  /// Deletes a file from Firebase Storage given its storage path.
  Future<void> deleteFile(String storagePath) async {
    _memoryUrls.remove(storagePath);
    final fs = _storage;
    if (fs == null) return;
    try {
      await fs.ref().child(storagePath).delete();
    } catch (e) {
      debugPrint('[FirebaseStorageService] deleteFile failed for $storagePath: $e');
    }
  }

  static String _extensionForMime(String mimeType) {
    switch (mimeType.toLowerCase()) {
      case 'image/png':
        return 'png';
      case 'image/webp':
        return 'webp';
      case 'image/heic':
        return 'heic';
      case 'application/pdf':
        return 'pdf';
      case 'video/mp4':
        return 'mp4';
      case 'video/quicktime':
        return 'mov';
      case 'audio/mp4':
      case 'audio/m4a':
        return 'm4a';
      case 'audio/mpeg':
        return 'mp3';
      case 'audio/aac':
        return 'aac';
      case 'image/jpeg':
      default:
        return 'jpg';
    }
  }

  @visibleForTesting
  Map<String, String> get memoryUrls => Map.unmodifiable(_memoryUrls);
}
