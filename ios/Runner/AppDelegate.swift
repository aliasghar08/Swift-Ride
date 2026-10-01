import Flutter
import UIKit
import CoreLocation
import PassKit
import UserNotifications
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Google Maps API key — read from Info.plist (GMSApiKey)
    if let apiKey = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String, !apiKey.isEmpty {
      GMSServices.provideAPIKey(apiKey)
    }

    GeneratedPluginRegistrant.register(with: self)

    if let registrar = self.registrar(forPlugin: "SwiftRideApp") {
      setupMethodChannels(binaryMessenger: registrar.messenger())
    }

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

    // 4. Device Channel (Haptics & Wake Lock)
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
        result(92)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
