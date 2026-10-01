/// Defines MethodChannel identifiers used across Android, iOS, and Flutter.
class NativeChannelConstants {
  static const String locationChannel = 'com.swiftride.app/location';
  static const String paymentChannel = 'com.swiftride.app/payment';
  static const String safetyChannel = 'com.swiftride.app/safety';
  static const String deviceChannel = 'com.swiftride.app/device';

  // Location methods
  static const String methodGetCurrentLocation = 'getCurrentLocation';
  static const String methodCheckLocationPermissions = 'checkLocationPermissions';
  static const String methodRequestLocationPermissions = 'requestLocationPermissions';
  static const String methodStartLocationUpdates = 'startLocationUpdates';
  static const String methodStopLocationUpdates = 'stopLocationUpdates';

  // Payment methods
  static const String methodProcessPayment = 'processPayment';
  static const String methodCheckNativePaySupport = 'checkNativePaySupport';

  // Safety methods
  static const String methodTriggerEmergencyAlert = 'triggerEmergencyAlert';
  static const String methodSendEmergencySms = 'sendEmergencySms';
  static const String methodTriggerEmergencyHaptics = 'triggerEmergencyHaptics';

  // Device methods
  static const String methodHapticFeedback = 'hapticFeedback';
  static const String methodSetKeepScreenOn = 'setKeepScreenOn';
  static const String methodGetBatteryInfo = 'getBatteryInfo';
}
