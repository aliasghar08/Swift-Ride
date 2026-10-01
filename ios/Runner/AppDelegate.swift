import Flutter
import UIKit
import CoreLocation
import PassKit
import UserNotifications
import GoogleMaps
import AVFoundation
import Network

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let speechSynthesizer = AVSpeechSynthesizer()
  private let networkMonitor = NWPathMonitor()
  private var currentNetworkStatus: String = "wifi"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Google Maps API key — read from Info.plist (GMSApiKey)
    if let apiKey = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String, !apiKey.isEmpty {
      NSLog("[SwiftRide] Google Maps API Key initialized: %@...", String(apiKey.prefix(12)))
      GMSServices.provideAPIKey(apiKey)
    } else {
      NSLog("[SwiftRide] WARNING: GMSApiKey is missing or empty in Info.plist!")
    }

    GeneratedPluginRegistrant.register(with: self)

    if let registrar = self.registrar(forPlugin: "SwiftRideApp") {
      setupMethodChannels(binaryMessenger: registrar.messenger())
    }

    // Start background network monitor
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

  private let locationManager = CLLocationManager()
  private let geocoder = CLGeocoder()

  private func setupMethodChannels(binaryMessenger: FlutterBinaryMessenger) {
    locationManager.desiredAccuracy = kCLLocationAccuracyBest
    locationManager.distanceFilter = 10.0

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

    // 1. Native Location & Geocoding Channel
    locationChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      guard let self = self else { return }
      switch call.method {
      case "checkLocationPermissions":
        var isAuthorized = false
        if #available(iOS 14.0, *) {
          let status = self.locationManager.authorizationStatus
          isAuthorized = (status == .authorizedWhenInUse || status == .authorizedAlways)
        } else {
          let status = CLLocationManager.authorizationStatus()
          isAuthorized = (status == .authorizedWhenInUse || status == .authorizedAlways)
        }
        result(isAuthorized)

      case "requestLocationPermissions":
        self.locationManager.requestWhenInUseAuthorization()
        result(true)

      case "getCurrentLocation":
        self.locationManager.startUpdatingLocation()
        if let loc = self.locationManager.location {
          let locationData: [String: Any] = [
            "latitude": loc.coordinate.latitude,
            "longitude": loc.coordinate.longitude,
            "heading": loc.course >= 0 ? loc.course : 0.0,
            "speed": loc.speed >= 0 ? loc.speed : 0.0,
            "altitude": loc.altitude,
            "isMock": false
          ]
          result(locationData)
        } else {
          // Pakistan default fallback if GPS warming up
          let fallback: [String: Any] = [
            "latitude": 33.6844,
            "longitude": 73.0479,
            "heading": 0.0,
            "speed": 0.0,
            "altitude": 500.0,
            "isMock": true
          ]
          result(fallback)
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
          self.geocoder.reverseGeocodeLocation(loc) { placemarks, error in
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

    // 2. Payment Channel (PassKit / Apple Pay)
    paymentChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "checkNativePaySupport":
        let canMakePayments = PKPaymentAuthorizationViewController.canMakePayments()
        result(["applePay": canMakePayments, "googlePay": false])
      case "processPayment":
        let args = call.arguments as? [String: Any]
        let amount = args?["amount"] as? Double ?? 0.0
        let res: [String: Any] = [
          "success": true,
          "transactionId": "txn_applepay_" + UUID().uuidString.prefix(8),
          "amount": amount
        ]
        result(res)
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
        let feedback = UINotificationFeedbackGenerator()
        feedback.notificationOccurred(.error)
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // 4. Device Channel (Haptics, Wake Lock, Hardware Info)
    deviceChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "setKeepScreenOn":
        let args = call.arguments as? [String: Any]
        let keepOn = args?["keepOn"] as? Bool ?? true
        UIApplication.shared.isIdleTimerDisabled = keepOn
        result(true)
      case "hapticFeedback":
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        result(true)
      case "getBatteryInfo":
        UIDevice.current.isBatteryMonitoringEnabled = true
        let batteryLevel = UIDevice.current.batteryLevel
        result(batteryLevel >= 0 ? Int(batteryLevel * 100) : 92)
      case "getDeviceInfo":
        let info: [String: Any] = [
          "manufacturer": "Apple",
          "model": UIDevice.current.model,
          "systemName": UIDevice.current.systemName,
          "systemVersion": UIDevice.current.systemVersion
        ]
        result(info)
      case "getAppVersion":
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        result(version)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // 5. Storage Channel (replaces shared_preferences)
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
      case "getString":
        result(defaults.string(forKey: key))
      case "setString":
        let val = args["value"] as? String
        defaults.set(val, forKey: key)
        result(true)
      case "getBool":
        result(defaults.object(forKey: key) != nil ? defaults.bool(forKey: key) : nil)
      case "setBool":
        let val = args["value"] as? Bool
        defaults.set(val, forKey: key)
        result(true)
      case "getInt":
        result(defaults.object(forKey: key) != nil ? defaults.integer(forKey: key) : nil)
      case "setInt":
        let val = args["value"] as? Int
        defaults.set(val, forKey: key)
        result(true)
      case "getDouble":
        result(defaults.object(forKey: key) != nil ? defaults.double(forKey: key) : nil)
      case "setDouble":
        let val = args["value"] as? Double
        defaults.set(val, forKey: key)
        result(true)
      case "remove":
        defaults.removeObject(forKey: key)
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // 6. Notifications Channel (replaces flutter_local_notifications)
    notificationChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "requestNotificationPermissions":
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
          result(granted)
        }
      case "showNotification":
        guard let args = call.arguments as? [String: Any] else {
          result(false)
          return
        }
        let id = args["id"] as? Int ?? 1
        let title = args["title"] as? String ?? "SwiftRide"
        let body = args["body"] as? String ?? ""

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(identifier: "swiftride_notif_\(id)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
          result(error == nil)
        }
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

    // 7. Launcher Channel (replaces url_launcher)
    launcherChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "launchDialer":
        if let args = call.arguments as? [String: Any],
           let phone = args["phone"] as? String,
           let url = URL(string: "tel://\(phone.replacingOccurrences(of: " ", with: ""))") {
          UIApplication.shared.open(url, options: [:]) { success in
            result(success)
          }
        } else {
          result(false)
        }
      case "launchSms":
        if let args = call.arguments as? [String: Any],
           let phone = args["phone"] as? String,
           let url = URL(string: "sms:\(phone.replacingOccurrences(of: " ", with: ""))") {
          UIApplication.shared.open(url, options: [:]) { success in
            result(success)
          }
        } else {
          result(false)
        }
      case "launchUrl":
        if let args = call.arguments as? [String: Any],
           let urlStr = args["url"] as? String,
           let url = URL(string: urlStr) {
          UIApplication.shared.open(url, options: [:]) { success in
            result(success)
          }
        } else {
          result(false)
        }
      case "launchMapsDirections":
        if let args = call.arguments as? [String: Any],
           let lat = args["latitude"] as? Double,
           let lng = args["longitude"] as? Double {
          // Open Apple Maps directions
          let appleMapsUrl = URL(string: "http://maps.apple.com/?daddr=\(lat),\(lng)&dirflg=d")
          if let url = appleMapsUrl, UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:]) { success in
              result(success)
            }
          } else {
            result(false)
          }
        } else {
          result(false)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // 8. Connectivity Channel (replaces connectivity_plus)
    connectivityChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "getConnectivityStatus":
        result(self?.currentNetworkStatus ?? "wifi")
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // 9. Audio & Speech Channel (replaces audioplayers & flutter_tts)
    audioChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      guard let self = self else { return }
      switch call.method {
      case "speakText":
        let args = call.arguments as? [String: Any]
        let text = args?["text"] as? String ?? ""
        if !text.isEmpty {
          let utterance = AVSpeechUtterance(string: text)
          utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
          self.speechSynthesizer.speak(utterance)
        }
        result(true)
      case "playAlertTone":
        // Play system alert sound (e.g. 1005 = alarm)
        AudioServicesPlaySystemSound(1005)
        result(true)
      case "stopAudio":
        self.speechSynthesizer.stopSpeaking(at: .immediate)
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // 10. Map Utility Channel (complements / replaces google_maps_flutter)
    mapChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "calculateDistance":
        let args = call.arguments as? [String: Any]
        let lat1 = args?["lat1"] as? Double ?? 0.0
        let lon1 = args?["lon1"] as? Double ?? 0.0
        let lat2 = args?["lat2"] as? Double ?? 0.0
        let lon2 = args?["lon2"] as? Double ?? 0.0

        let loc1 = CLLocation(latitude: lat1, longitude: lon1)
        let loc2 = CLLocation(latitude: lat2, longitude: lon2)
        let meters = loc1.distance(from: loc2)
        result(meters / 1000.0) // in kilometers
      case "animateCamera", "addMarker", "clearMarkers", "setPolyline":
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
