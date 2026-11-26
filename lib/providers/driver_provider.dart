import 'dart:async';
import 'package:flutter/foundation.dart';
import '../domain/models/driver_profile_model.dart';
import '../core/constants/app_constants.dart';
import '../domain/models/driver_document_model.dart';
import '../domain/models/vehicle_info_model.dart';
import '../services/driver_service.dart';
import '../services/firebase_storage_service.dart';
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

  /// True if driver has an active 0% platform fee waiver.
  bool get isFeeWaiverActive => _driverProfile.isFeeWaiverActive;

  /// Active platform fee rate (0.0% if waiver is active, else standard 0.02).
  double get effectivePlatformFeeRate => _driverProfile.effectivePlatformFeeRate;

  /// True if captain unlocked the 5-Driver Referral Milestone badge.
  bool get isFoundingCaptain => _driverProfile.isFoundingCaptain;

  /// Redeems a launch promo code (e.g. `JHANG0`) or peer Captain Invite Code (`CAPT-482`).
  Future<Map<String, dynamic>> applyPromoCode(String code) async {
    final result = await _firestoreService.applyDriverPromoCode(code);
    if (result['success'] == true) {
      if (_driverProfile.userId.isNotEmpty) {
        await loadForUser(_driverProfile.userId);
      } else {
        notifyListeners();
      }
    }
    return result;
  }
  DriverProfile get driver => _driverProfile;
  bool get isOnline => _driverProfile.isOnline;
  double get totalEarnings => _driverProfile.totalEarnings;
  int get totalRides => _driverProfile.totalRides;
  bool get femalePassengersOnly => _driverProfile.femalePassengersOnly;
  bool get acceptsStandardCarRides => _driverProfile.acceptsStandardCarRides;
  bool get isGenderVerified => _driverProfile.isGenderVerified;
  String? get gender => _driverProfile.gender;

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
      femalePassengersOnly: _driverProfile.femalePassengersOnly,
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

  /// Toggles female passengers only preference for verified female drivers.
  Future<String?> toggleFemalePassengersOnly(bool enabled) async {
    if (enabled) {
      final isFemale = _driverProfile.gender?.toLowerCase() == 'female';
      final isVerified = _driverProfile.isVerified || hasPassedAiVerification;
      if (!isFemale) {
        return 'Women Passengers Only mode is exclusively available for female drivers.';
      }
      if (!isVerified || !_driverProfile.isGenderVerified) {
        return 'Please complete CNIC / document verification to unlock Women Passengers Only mode.';
      }
    }

    final success = await _firestoreService.updateFemalePassengersOnly(
      _driverProfile.userId,
      enabled,
    );
    if (!success) {
      return 'Failed to update preference. Please check your network.';
    }

    _driverProfile = _driverProfile.copyWith(femalePassengersOnly: enabled);
    notifyListeners();
    return null;
  }

  /// Toggles preference to also accept standard 4-seat car ride requests for 7-seater drivers.
  Future<bool> setAcceptsStandardCarRides(bool accepts) async {
    final uid = _driverProfile.userId;
    if (uid.isNotEmpty) {
      await _firestoreService.updateAcceptsStandardCarRides(uid, accepts);
    }
    _driverProfile = _driverProfile.copyWith(acceptsStandardCarRides: accepts);
    notifyListeners();
    return true;
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

  /// Whether the driver's CNIC, Driving License, and Vehicle Registration are verified.
  bool get hasPassedAiVerification {
    final hasCnic = _documents.any(
      (d) => (d.type == DriverDocumentType.cnicFront || d.type == DriverDocumentType.cnicBack) && d.isVerified,
    );
    final hasLicense = _documents.any(
      (d) => d.type == DriverDocumentType.drivingLicense && d.isVerified,
    );
    final hasReg = _documents.any(
      (d) => d.type == DriverDocumentType.vehicleRegistration && d.isVerified,
    );
    return (hasCnic && hasLicense && hasReg) || _driverProfile.isVerified;
  }

  /// Whether the driver has entered complete legal & visual vehicle information
  /// and passed official verification (if required) to safely receive ride requests.
  bool get canActAsDriver {
    return _driverProfile.vehicle.isConfigured &&
        (!AppConstants.kRequireDriverVerification ||
            _driverProfile.isVerified ||
            hasPassedAiVerification);
  }

  /// Updates driver's vehicle legal and visual details and persists to Firestore.
  Future<bool> updateVehicleInfo(
    VehicleInfo vehicle, {
    String? licenseNumber,
  }) async {
    _driverProfile = _driverProfile.copyWith(
      vehicle: vehicle,
      licenseNumber: licenseNumber ?? _driverProfile.licenseNumber,
    );
    notifyListeners();

    final uid = _driverProfile.userId;
    if (uid.isNotEmpty) {
      await _firestoreService.saveDriverProfile(_driverProfile);
    }
    return true;
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
    Uint8List? rawBytes,
    String? downloadUrl,
    String mimeType = 'image/jpeg',
    Map<String, String>? expectedData,
  }) async {
    final uid = _driverProfile.userId;
    if (uid.isEmpty) return null;

    _isUploadingDoc = true;
    _docError = null;
    notifyListeners();

    try {
      String? resolvedUrl = downloadUrl;
      // If rawBytes provided and downloadUrl not yet resolved, upload to Firebase Storage
      if (resolvedUrl == null && rawBytes != null) {
        try {
          final storage = FirebaseStorageService();
          if (type == DriverDocumentType.vehicleFront) {
            resolvedUrl = await storage.uploadVehiclePhoto(
              driverId: uid,
              photoType: 'front',
              bytes: rawBytes,
              mimeType: mimeType,
            );
          } else if (type == DriverDocumentType.vehicleInterior) {
            resolvedUrl = await storage.uploadVehiclePhoto(
              driverId: uid,
              photoType: 'interior',
              bytes: rawBytes,
              mimeType: mimeType,
            );
          } else {
            resolvedUrl = await storage.uploadDriverDocument(
              driverId: uid,
              type: type,
              bytes: rawBytes,
              mimeType: mimeType,
            );
          }
        } catch (storageErr) {
          debugPrint('[DriverProvider] Firebase Storage upload notice: $storageErr');
        }
      }

      final doc = await _firestoreService.submitAndVerifyDocument(
        driverId: uid,
        type: type,
        imageBase64: imageBase64,
        downloadUrl: resolvedUrl,
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

      // If this was a vehicle photo, also update local vehicle state
      if (resolvedUrl != null) {
        if (type == DriverDocumentType.vehicleFront) {
          _driverProfile = _driverProfile.copyWith(
            vehicle: _driverProfile.vehicle.copyWith(frontPhotoUrl: resolvedUrl),
          );
        } else if (type == DriverDocumentType.vehicleInterior) {
          _driverProfile = _driverProfile.copyWith(
            vehicle: _driverProfile.vehicle.copyWith(interiorPhotoUrl: resolvedUrl),
          );
        }
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
