import Flutter
import UIKit
import CoreLocation
import PassKit
import UserNotifications
import GoogleMaps
import AVFoundation
import Network

@main
@objc class AppDelegate: FlutterAppDelegate, CLLocationManagerDelegate {
  private let speechSynthesizer = AVSpeechSynthesizer()
  private let networkMonitor = NWPathMonitor()
  private var currentNetworkStatus: String = "wifi"

  // MARK: - Location state
  private let locationManager = CLLocationManager()
  private let geocoder = CLGeocoder()
  private var lastKnownLocation: CLLocation?

  /// In-flight `getCurrentLocation` calls that are waiting for a fresh GPS fix.
  /// Each gets a UUID so we can time it out individually and never call a
  /// FlutterResult twice (which crashes the engine).
  private var pendingLocationRequests: [(id: UUID, result: FlutterResult)] = []

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let apiKey = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String, !apiKey.isEmpty {
      NSLog("[SwiftRide] Google Maps API Key initialized: %@...", String(apiKey.prefix(12)))
      GMSServices.provideAPIKey(apiKey)
    } else {
      NSLog("[SwiftRide] WARNING: GMSApiKey is missing or empty in Info.plist!")
    }

    GeneratedPluginRegistrant.register(with: self)

    locationManager.delegate = self
    locationManager.desiredAccuracy = kCLLocationAccuracyBest
    locationManager.distanceFilter = 5.0
    locationManager.pausesLocationUpdatesAutomatically = false
    locationManager.allowsBackgroundLocationUpdates = false

    if let registrar = self.registrar(forPlugin: "SwiftRideApp") {
      setupMethodChannels(binaryMessenger: registrar.messenger())
    }

    let queue = DispatchQueue(label: "com.swiftride.networkMonitor")
    networkMonitor.pathUpdateHandler = { [weak self] path in
      if path.status == .satisfied {
        if path.usesInterfaceType(.wifi) {
          self?.currentNetworkStatus = "wifi"
        } else if path.usesInterfaceType(.cellular) {
          self?.currentNetworkStatus = "cellular"
        } else if path.usesInterfaceType(.wiredEthernet) {
          self?.currentNetworkStatus = "ethernet"
        } else {
          self?.currentNetworkStatus = "wifi"
        }
      } else {
        self?.currentNetworkStatus = "none"
      }
    }
    networkMonitor.start(queue: queue)

    UNUserNotificationCenter.current().delegate = self
    application.registerForRemoteNotifications()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  // MARK: - CLLocationManagerDelegate

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let loc = locations.last else { return }
    // Reject stale / wildly inaccurate fixes.
    guard loc.horizontalAccuracy >= 0, loc.horizontalAccuracy < 200 else { return }
    lastKnownLocation = loc
    NSLog("[SwiftRide] fix: %.5f, %.5f (±%.1fm)",
          loc.coordinate.latitude, loc.coordinate.longitude, loc.horizontalAccuracy)
    resolvePendingLocationRequests(with: loc)
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    // kCLError codes:
    //   0 = locationUnknown    → transient, GPS warming up. Ignore and keep waiting.
    //   1 = denied             → permission revoked mid-flight. Fail fast.
    //   2 = network            → no route to location services.
    //   3 = headingFailure     → heading unavailable, ignore.
    let nsError = error as NSError
    let code = nsError.code

    NSLog("[SwiftRide] location error: %@ (code=%ld)", error.localizedDescription, code)

    if nsError.domain == kCLErrorDomain {
      switch code {
      case 0, 3:
        // Transient. Do NOT fail pending requests — the fresh fix will arrive
        // shortly (or the 12s timeout will fire and fail them cleanly).
        return
      default:
        break
      }
    }

    // Real failure: denied, network, etc. Fail everything waiting.
    failAllPendingLocationRequests(
      code: "LOCATION_ERROR",
      message: error.localizedDescription
    )
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    let status = manager.authorizationStatus
    NSLog("[SwiftRide] authorization status changed: %ld", status.rawValue)
    switch status {
    case .authorizedWhenInUse, .authorizedAlways:
      manager.startUpdatingLocation()
    case .denied, .restricted:
      failAllPendingLocationRequests(
        code: "PERMISSION_DENIED",
        message: "Location permission was denied."
      )
    default:
      break
    }
  }

  private func resolvePendingLocationRequests(with loc: CLLocation) {
    guard !pendingLocationRequests.isEmpty else { return }
    let payload = Self.serialize(loc)
    let pending = pendingLocationRequests
    pendingLocationRequests.removeAll()
    for req in pending { req.result(payload) }
  }

  private func failAllPendingLocationRequests(code: String, message: String) {
    guard !pendingLocationRequests.isEmpty else { return }
    let pending = pendingLocationRequests
    pendingLocationRequests.removeAll()
    for req in pending {
      req.result(FlutterError(code: code, message: message, details: nil))
    }
  }

  private static func serialize(_ loc: CLLocation) -> [String: Any] {
    return [
      "latitude": loc.coordinate.latitude,
      "longitude": loc.coordinate.longitude,
      "heading": loc.course >= 0 ? loc.course : 0.0,
      "speed": loc.speed >= 0 ? loc.speed : 0.0,
      "altitude": loc.altitude,
      "accuracy": loc.horizontalAccuracy,
      "timestamp": loc.timestamp.timeIntervalSince1970 * 1000.0,
      "isMock": false,
    ]
  }

  // MARK: - Method Channels

  private func setupMethodChannels(binaryMessenger: FlutterBinaryMessenger) {
    let locationChannel = FlutterMethodChannel(name: "com.swiftride.app/location", binaryMessenger: binaryMessenger)
    let paymentChannel = FlutterMethodChannel(name: "com.swiftride.app/payment", binaryMessenger: binaryMessenger)
    let safetyChannel = FlutterMethodChannel(name: "com.swiftride.app/safety", binaryMessenger: binaryMessenger)
    let deviceChannel = FlutterMethodChannel(name: "com.swiftride.app/device", binaryMessenger: binaryMessenger)
    let storageChannel = FlutterMethodChannel(name: "com.swiftride.app/storage", binaryMessenger: binaryMessenger)
    let notificationChannel = FlutterMethodChannel(name: "com.swiftride.app/notifications", binaryMessenger: binaryMessenger)
    let launcherChannel = FlutterMethodChannel(name: "com.swiftride.app/launcher", binaryMessenger: binaryMessenger)
    let connectivityChannel = FlutterMethodChannel(name: "com.swiftride.app/connectivity", binaryMessenger: binaryMessenger)
    let audioChannel = FlutterMethodChannel(name: "com.swiftride.app/audio", binaryMessenger: binaryMessenger)
    let mapChannel = FlutterMethodChannel(name: "com.swiftride.app/map", binaryMessenger: binaryMessenger)

    // 1. Native Location & Geocoding
    locationChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      guard let self = self else {
        result(FlutterError(code: "NO_APPDELEGATE", message: "AppDelegate deallocated", details: nil))
        return
      }
      switch call.method {

      case "checkLocationPermissions":
        let status = self.locationManager.authorizationStatus
        let ok = (status == .authorizedWhenInUse || status == .authorizedAlways)
        result(ok)

      case "requestLocationPermissions":
        let status = self.locationManager.authorizationStatus
        if status == .notDetermined {
          self.locationManager.requestWhenInUseAuthorization()
          result(false)
        } else {
          result(status == .authorizedWhenInUse || status == .authorizedAlways)
        }

      case "getCurrentLocation":
        let status = self.locationManager.authorizationStatus
        if status == .denied || status == .restricted {
          result(FlutterError(code: "PERMISSION_DENIED",
                              message: "Location permission not granted.",
                              details: nil))
          return
        }

        // If we already have a recent fix, return it immediately.
        if let loc = self.lastKnownLocation,
           loc.timestamp.timeIntervalSinceNow > -60,
           loc.horizontalAccuracy >= 0,
           loc.horizontalAccuracy < 100 {
          result(Self.serialize(loc))
          return
        }

        // Otherwise request a fresh fix and hold this FlutterResult until it
        // arrives (or times out).
        let id = UUID()
        self.pendingLocationRequests.append((id: id, result: result))

        if status == .notDetermined {
          self.locationManager.requestWhenInUseAuthorization()
        }
        self.locationManager.startUpdatingLocation()

        DispatchQueue.main.asyncAfter(deadline: .now() + 12.0) { [weak self] in
          guard let self = self else { return }
          if let idx = self.pendingLocationRequests.firstIndex(where: { $0.id == id }) {
            let req = self.pendingLocationRequests.remove(at: idx)
            req.result(FlutterError(code: "LOCATION_TIMEOUT",
                                    message: "No GPS fix within 12s.",
                                    details: nil))
          }
        }

      case "startLocationUpdates":
        self.locationManager.startUpdatingLocation()
        result(true)

      case "stopLocationUpdates":
        self.locationManager.stopUpdatingLocation()
        result(true)

      case "reverseGeocode":
        if let args = call.arguments as? [String: Any],
           let lat = args["latitude"] as? Double,
           let lng = args["longitude"] as? Double {
          let loc = CLLocation(latitude: lat, longitude: lng)
          self.geocoder.reverseGeocodeLocation(loc) { placemarks, _ in
            if let p = placemarks?.first {
              var parts: [String] = []
              if let name = p.name, !name.isEmpty { parts.append(name) }
              if let subLoc = p.subLocality, !subLoc.isEmpty { parts.append(subLoc) }
              if let city = p.locality, !city.isEmpty { parts.append(city) }
              result(parts.joined(separator: ", "))
            } else {
              result(String(format: "Location (%.4f, %.4f)", lat, lng))
            }
          }
        } else {
          result("Selected Location")
        }

      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // 2. Payment Channel
    paymentChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "checkNativePaySupport":
        let canMakePayments = PKPaymentAuthorizationViewController.canMakePayments()
        result(["applePay": canMakePayments, "googlePay": false])
      case "processPayment":
        let args = call.arguments as? [String: Any]
        let amount = args?["amount"] as? Double ?? 0.0
        result([
          "success": true,
          "transactionId": "txn_applepay_" + UUID().uuidString.prefix(8),
          "amount": amount,
        ])
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // 3. Safety Channel
    safetyChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "triggerEmergencyAlert", "sendEmergencySms":
        result(true)
      case "triggerEmergencyHaptics":
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // 4. Device Channel
    deviceChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "setKeepScreenOn":
        let args = call.arguments as? [String: Any]
        let keepOn = args?["keepOn"] as? Bool ?? true
        UIApplication.shared.isIdleTimerDisabled = keepOn
        result(true)
      case "hapticFeedback":
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        result(true)
      case "getBatteryInfo":
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        result(level >= 0 ? Int(level * 100) : 92)
      case "getDeviceInfo":
        result([
          "manufacturer": "Apple",
          "model": UIDevice.current.model,
          "systemName": UIDevice.current.systemName,
          "systemVersion": UIDevice.current.systemVersion,
        ])
      case "getAppVersion":
        result(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // 5. Storage Channel
    storageChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
      let defaults = UserDefaults.standard
      guard let args = call.arguments as? [String: Any],
            let key = args["key"] as? String else {
        if call.method == "clear" {
          if let bundleID = Bundle.main.bundleIdentifier {
            defaults.removePersistentDomain(forName: bundleID)
          }
          result(true)
        } else {
          result(FlutterError(code: "INVALID_ARGS", message: "Key required", details: nil))
        }
        return
      }
      switch call.method {
      case "getString": result(defaults.string(forKey: key))
      case "setString": defaults.set(args["value"] as? String, forKey: key); result(true)
      case "getBool":   result(defaults.object(forKey: key) != nil ? defaults.bool(forKey: key) : nil)
      case "setBool":   defaults.set(args["value"] as? Bool, forKey: key); result(true)
      case "getInt":    result(defaults.object(forKey: key) != nil ? defaults.integer(forKey: key) : nil)
      case "setInt":    defaults.set(args["value"] as? Int, forKey: key); result(true)
      case "getDouble": result(defaults.object(forKey: key) != nil ? defaults.double(forKey: key) : nil)
      case "setDouble": defaults.set(args["value"] as? Double, forKey: key); result(true)
      case "remove":    defaults.removeObject(forKey: key); result(true)
      default:          result(FlutterMethodNotImplemented)
      }
    }

    // 6. Notifications
    notificationChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "requestNotificationPermissions":
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
          result(granted)
        }
      case "showNotification":
        guard let args = call.arguments as? [String: Any] else { result(false); return }
        let id = args["id"] as? Int ?? 1
        let title = args["title"] as? String ?? "SwiftRide"
        let body = args["body"] as? String ?? ""
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let req = UNNotificationRequest(identifier: "swiftride_notif_\(id)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req) { err in result(err == nil) }
      case "cancelNotification":
        if let args = call.arguments as? [String: Any], let id = args["id"] as? Int {
          UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["swiftride_notif_\(id)"])
          UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["swiftride_notif_\(id)"])
        }
        result(true)
      case "cancelAllNotifications":
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // 7. Launcher
    launcherChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "launchDialer":
        if let args = call.arguments as? [String: Any],
           let phone = args["phone"] as? String,
           let url = URL(string: "tel://\(phone.replacingOccurrences(of: " ", with: ""))") {
          UIApplication.shared.open(url, options: [:]) { result($0) }
        } else { result(false) }
      case "launchSms":
        if let args = call.arguments as? [String: Any],
           let phone = args["phone"] as? String,
           let url = URL(string: "sms:\(phone.replacingOccurrences(of: " ", with: ""))") {
          UIApplication.shared.open(url, options: [:]) { result($0) }
        } else { result(false) }
      case "launchUrl":
        if let args = call.arguments as? [String: Any],
           let urlStr = args["url"] as? String,
           let url = URL(string: urlStr) {
          UIApplication.shared.open(url, options: [:]) { result($0) }
        } else { result(false) }
      case "launchMapsDirections":
        if let args = call.arguments as? [String: Any],
           let lat = args["latitude"] as? Double,
           let lng = args["longitude"] as? Double,
           let url = URL(string: "http://maps.apple.com/?daddr=\(lat),\(lng)&dirflg=d"),
           UIApplication.shared.canOpenURL(url) {
          UIApplication.shared.open(url, options: [:]) { result($0) }
        } else { result(false) }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // 8. Connectivity
    connectivityChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "getConnectivityStatus": result(self?.currentNetworkStatus ?? "wifi")
      default: result(FlutterMethodNotImplemented)
      }
    }

    // 9. Audio
    audioChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      guard let self = self else { return }
      switch call.method {
      case "speakText":
        let args = call.arguments as? [String: Any]
        let text = args?["text"] as? String ?? ""
        if !text.isEmpty {
          let u = AVSpeechUtterance(string: text)
          u.voice = AVSpeechSynthesisVoice(language: "en-US")
          self.speechSynthesizer.speak(u)
        }
        result(true)
      case "playAlertTone":
        AudioServicesPlaySystemSound(1005)
        result(true)
      case "stopAudio":
        self.speechSynthesizer.stopSpeaking(at: .immediate)
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // 10. Map utility
    mapChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "calculateDistance":
        let args = call.arguments as? [String: Any]
        let lat1 = args?["lat1"] as? Double ?? 0.0
        let lon1 = args?["lon1"] as? Double ?? 0.0
        let lat2 = args?["lat2"] as? Double ?? 0.0
        let lon2 = args?["lon2"] as? Double ?? 0.0
        let meters = CLLocation(latitude: lat1, longitude: lon1)
          .distance(from: CLLocation(latitude: lat2, longitude: lon2))
        result(meters / 1000.0)
      case "animateCamera", "addMarker", "clearMarkers", "setPolyline":
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}