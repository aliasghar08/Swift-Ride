/// Defines MethodChannel identifiers used across Android, iOS, and Flutter.
class NativeChannelConstants {
  static const String locationChannel = 'com.swiftride.app/location';
  static const String paymentChannel = 'com.swiftride.app/payment';
  static const String safetyChannel = 'com.swiftride.app/safety';
  static const String deviceChannel = 'com.swiftride.app/device';
  static const String storageChannel = 'com.swiftride.app/storage';
  static const String notificationChannel = 'com.swiftride.app/notifications';
  static const String launcherChannel = 'com.swiftride.app/launcher';
  static const String connectivityChannel = 'com.swiftride.app/connectivity';
  static const String audioChannel = 'com.swiftride.app/audio';
  static const String mapChannel = 'com.swiftride.app/map';

  // Location methods
  static const String methodGetCurrentLocation = 'getCurrentLocation';
  static const String methodCheckLocationPermissions = 'checkLocationPermissions';
  static const String methodRequestLocationPermissions = 'requestLocationPermissions';
  static const String methodStartLocationUpdates = 'startLocationUpdates';
  static const String methodStopLocationUpdates = 'stopLocationUpdates';
  static const String methodReverseGeocode = 'reverseGeocode';

  // Payment methods
  static const String methodProcessPayment = 'processPayment';
  static const String methodCheckNativePaySupport = 'checkNativePaySupport';

  // Safety methods
  static const String methodSendEmergencySms = 'sendEmergencySms';
  static const String methodTriggerEmergencyHaptics = 'triggerEmergencyHaptics';

  // Device methods
  static const String methodHapticFeedback = 'hapticFeedback';
  static const String methodSetKeepScreenOn = 'setKeepScreenOn';
  static const String methodGetBatteryInfo = 'getBatteryInfo';
  static const String methodGetDeviceInfo = 'getDeviceInfo';
  static const String methodGetAppVersion = 'getAppVersion';

  // Storage methods (replaces shared_preferences)
  static const String methodStorageGetString = 'getString';
  static const String methodStorageSetString = 'setString';
  static const String methodStorageGetBool = 'getBool';
  static const String methodStorageSetBool = 'setBool';
  static const String methodStorageGetInt = 'getInt';
  static const String methodStorageSetInt = 'setInt';
  static const String methodStorageGetDouble = 'getDouble';
  static const String methodStorageSetDouble = 'setDouble';
  static const String methodStorageRemove = 'remove';
  static const String methodStorageClear = 'clear';

  // Notification methods (replaces flutter_local_notifications)
  static const String methodShowNotification = 'showNotification';
  static const String methodCancelNotification = 'cancelNotification';
  static const String methodCancelAllNotifications = 'cancelAllNotifications';
  static const String methodRequestNotificationPermissions = 'requestNotificationPermissions';

  // Launcher methods (replaces url_launcher)
  static const String methodLaunchDialer = 'launchDialer';
  static const String methodLaunchSms = 'launchSms';
  static const String methodLaunchUrl = 'launchUrl';
  static const String methodLaunchMapsDirections = 'launchMapsDirections';

  // Connectivity methods (replaces connectivity_plus)
  static const String methodGetConnectivityStatus = 'getConnectivityStatus';

  // Audio / Speech methods (replaces audioplayers & flutter_tts)
  static const String methodPlayAlertTone = 'playAlertTone';
  static const String methodSpeakText = 'speakText';
  static const String methodStopAudio = 'stopAudio';

  // Native Map methods (complements / replaces google_maps_flutter)
  static const String methodMapAnimateCamera = 'animateCamera';
  static const String methodMapAddMarker = 'addMarker';
  static const String methodMapClearMarkers = 'clearMarkers';
  static const String methodMapSetPolyline = 'setPolyline';
  static const String methodMapCalculateDistance = 'calculateDistance';
}
