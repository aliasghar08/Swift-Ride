import 'dart:async';
import 'package:flutter/foundation.dart';
import '../domain/models/driver_profile_model.dart';
import '../domain/models/driver_document_model.dart';
import '../services/driver_service.dart';
import '../services/firestore/firestore_driver_service.dart';

/// Zero-dependency Driver Provider managing driver state, online availability,
/// and earnings from rides (with 98% driver pass-through after 2% platform commission).
class DriverProvider extends ChangeNotifier {
  final DriverService _driverService;
  final FirestoreDriverService _firestoreService;
  DriverProfile _driverProfile;

  DriverProvider({
    DriverService? driverService,
    FirestoreDriverService? firestoreService,
    DriverProfile? initialProfile,
  })  : _driverService = driverService ?? DriverService(),
        _firestoreService = firestoreService ?? FirestoreDriverService(),
        // Starts empty. This used to be seeded with a fabricated driver
        // ("driver_marcus_202", plate 7XYZ890, 318 rides, PKR 4,250 earned), so
        // the cockpit displayed invented earnings a driver could try to withdraw.
        _driverProfile = initialProfile ?? DriverProfile.empty();

  /// Real earnings and payout balance reported by the backend.
  DriverEarnings? _earnings;
  bool _isLoadingProfile = false;
  String? _profileError;

  DriverEarnings? get earnings => _earnings;
  bool get isLoadingProfile => _isLoadingProfile;
  String? get profileError => _profileError;

  /// Authoritative withdrawable balance. Falls back to the locally-known figure
  /// only until the server responds.
  double get availablePayoutBalance =>
      _earnings?.availablePayoutBalance ?? _driverProfile.totalEarnings;

  /// Loads this driver's real profile and earnings.
  ///
  /// Returns false when the profile could not be loaded, so the cockpit can say
  /// so rather than showing an empty dashboard as if it were the truth.
  Future<bool> loadForUser(String userId) async {
    if (userId.isEmpty) return false;

    _isLoadingProfile = true;
    _profileError = null;
    notifyListeners();

    try {
      final loaded = await _firestoreService.getDriverProfile(userId);
      if (loaded != null) {
        _driverProfile = loaded;
      } else {
        // No driver record yet: keep the real identity but claim nothing else.
        _driverProfile = DriverProfile.empty(userId: userId);
      }

      _earnings = await _firestoreService.fetchEarnings();
      return true;
    } catch (e) {
      debugPrint('[DriverProvider] loadForUser failed: $e');
      _profileError = 'We could not load your driver profile. Pull to retry.';
      return false;
    } finally {
      _isLoadingProfile = false;
      notifyListeners();
    }
  }

  DriverProfile get driverProfile => _driverProfile;
  DriverProfile get driver => _driverProfile;
  bool get isOnline => _driverProfile.isOnline;
  double get totalEarnings => _driverProfile.totalEarnings;
  int get totalRides => _driverProfile.totalRides;

  /// Changes availability, server-side.
  ///
  /// Returns null on success, or a message explaining the refusal. Local state
  /// is only updated once the backend confirms, so the switch cannot show
  /// "online" when dispatch still considers the driver unavailable.
  Future<String?> toggleOnline(
    bool online, {
    double? latitude,
    double? longitude,
  }) async {
    final error = await _firestoreService.setOnline(
      isOnline: online,
      latitude: latitude,
      longitude: longitude,
    );

    if (error == null) {
      _driverProfile = _driverService.setOnlineStatus(_driverProfile, online);
      _availabilityError = null;
    } else {
      _availabilityError = error;
    }
    notifyListeners();
    return error;
  }

  String? _availabilityError;
  String? get availabilityError => _availabilityError;

  void creditTripEarnings(double fare) {
    _driverProfile = _driverService.creditTripEarnings(_driverProfile, fare);
    notifyListeners();
  }

  // Payouts are requested through `DriverViewModel.requestPayout`, which calls
  // the backend ledger. There is no local equivalent on purpose.

  void updateProfile(DriverProfile profile) {
    _driverProfile = profile;
    notifyListeners();
  }

  // Document Verification Support
  List<DriverDocumentModel> _documents = [];
  StreamSubscription<List<DriverDocumentModel>>? _documentsSub;
  bool _isUploadingDoc = false;
  String? _docError;

  List<DriverDocumentModel> get documents => _documents;
  bool get isUploadingDoc => _isUploadingDoc;
  String? get docError => _docError;

  /// Whether the driver's CNIC and Driving License are AI-verified.
  bool get hasPassedAiVerification {
    final hasCnic = _documents.any(
      (d) => (d.type == DriverDocumentType.cnicFront || d.type == DriverDocumentType.cnicBack) && d.isVerified,
    );
    final hasLicense = _documents.any(
      (d) => d.type == DriverDocumentType.drivingLicense && d.isVerified,
    );
    return (hasCnic && hasLicense) || _driverProfile.isVerified;
  }

  void watchDocuments(String driverId) {
    if (driverId.isEmpty) return;
    _documentsSub?.cancel();
    _documentsSub = _firestoreService.streamDriverDocuments(driverId).listen((docs) {
      _documents = docs;
      // If AI or admin verified documents, update local driver profile state
      if (docs.any((d) => d.isVerified) && !_driverProfile.isVerified) {
        if (hasPassedAiVerification) {
          _driverProfile = _driverProfile.copyWith(isVerified: true);
        }
      }
      notifyListeners();
    });
  }

  Future<DriverDocumentModel?> uploadAndVerifyDocument({
    required DriverDocumentType type,
    required String imageBase64,
    String mimeType = 'image/jpeg',
    Map<String, String>? expectedData,
  }) async {
    final uid = _driverProfile.userId;
    if (uid.isEmpty) return null;

    _isUploadingDoc = true;
    _docError = null;
    notifyListeners();

    try {
      final doc = await _firestoreService.submitAndVerifyDocument(
        driverId: uid,
        type: type,
        imageBase64: imageBase64,
        mimeType: mimeType,
        expectedData: expectedData,
      );

      final idx = _documents.indexWhere((d) => d.type == type);
      if (idx >= 0) {
        _documents[idx] = doc;
      } else {
        _documents.add(doc);
      }

      if (hasPassedAiVerification) {
        _driverProfile = _driverProfile.copyWith(isVerified: true);
      }

      return doc;
    } catch (e) {
      _docError = 'Document verification failed: $e';
      return null;
    } finally {
      _isUploadingDoc = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _documentsSub?.cancel();
    super.dispose();
  }

  @visibleForTesting
  void setDocumentsForTesting(List<DriverDocumentModel> docs) {
    _documents = docs;
    notifyListeners();
  }

  @visibleForTesting
  void setDriverProfileForTesting(DriverProfile profile) {
    _driverProfile = profile;
    notifyListeners();
  }
}
