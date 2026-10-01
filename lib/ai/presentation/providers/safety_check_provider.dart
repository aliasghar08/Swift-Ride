import 'package:flutter/foundation.dart';

class SafetyCheckProvider extends ChangeNotifier {
  bool _isSafetyActive = false;
  String? _rideId;
  String? _flagType;
  String? _message;
  bool _sosTriggered = false;

  bool get isSafetyActive => _isSafetyActive;
  String? get rideId => _rideId;
  String? get flagType => _flagType;
  String? get message => _message;
  bool get sosTriggered => _sosTriggered;

  void triggerSafetyCheck({
    required String rideId,
    required String flagType,
    required String message,
  }) {
    _rideId = rideId;
    _flagType = flagType;
    _message = message;
    _isSafetyActive = true;
    _sosTriggered = false;
    notifyListeners();
  }

  void dismissCheck() {
    _isSafetyActive = false;
    notifyListeners();
  }

  void triggerEmergencySos() {
    _sosTriggered = true;
    _isSafetyActive = false;
    notifyListeners();
  }

  void reset() {
    _isSafetyActive = false;
    _rideId = null;
    _flagType = null;
    _message = null;
    _sosTriggered = false;
    notifyListeners();
  }
}
