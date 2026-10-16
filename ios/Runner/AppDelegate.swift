import Flutter
import UIKit
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
    if let apiKey = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String, !apiKey.isEmpty {
      NSLog("[SwiftRide] Google Maps API Key initialized: %@...", String(apiKey.prefix(12)))
      GMSServices.provideAPIKey(apiKey)
    } else {
      NSLog("[SwiftRide] WARNING: GMSApiKey is missing or empty in Info.plist!")
    }

    GeneratedPluginRegistrant.register(with: self)

    if let registrar = self.registrar(forPlugin: "SwiftRideApp") {
      let messenger = registrar.messenger()
      setupMethodChannels(binaryMessenger: messenger)

      let locationService = NativeLocationService.register(with: messenger)
      _ = NativeMapService.register(with: messenger, locationService: locationService)

      registrar.register(
        NativeMapViewFactory(messenger: messenger),
        withId: "com.swiftride.app/native_map_view"
      )
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

  // MARK: - Method Channels

  private func setupMethodChannels(binaryMessenger: FlutterBinaryMessenger) {
    let paymentChannel = FlutterMethodChannel(name: "com.swiftride.app/payment", binaryMessenger: binaryMessenger)
    let safetyChannel = FlutterMethodChannel(name: "com.swiftride.app/safety", binaryMessenger: binaryMessenger)
    let deviceChannel = FlutterMethodChannel(name: "com.swiftride.app/device", binaryMessenger: binaryMessenger)
    let storageChannel = FlutterMethodChannel(name: "com.swiftride.app/storage", binaryMessenger: binaryMessenger)
    let notificationChannel = FlutterMethodChannel(name: "com.swiftride.app/notifications", binaryMessenger: binaryMessenger)
    let launcherChannel = FlutterMethodChannel(name: "com.swiftride.app/launcher", binaryMessenger: binaryMessenger)
    let connectivityChannel = FlutterMethodChannel(name: "com.swiftride.app/connectivity", binaryMessenger: binaryMessenger)
    let audioChannel = FlutterMethodChannel(name: "com.swiftride.app/audio", binaryMessenger: binaryMessenger)

    // 1. Payment Channel
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

    // 2. Safety Channel
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

    // 3. Device Channel
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

    // 4. Storage Channel
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

    // 5. Notifications
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

    // 6. Launcher
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

    // 7. Connectivity
    connectivityChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "getConnectivityStatus": result(self?.currentNetworkStatus ?? "wifi")
      default: result(FlutterMethodNotImplemented)
      }
    }

    // 8. Audio
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
  }
}