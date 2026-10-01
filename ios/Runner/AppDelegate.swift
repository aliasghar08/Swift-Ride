import Flutter
import UIKit
import CoreLocation
import PassKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
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

  private func setupMethodChannels(binaryMessenger: FlutterBinaryMessenger) {
    let locationChannel = FlutterMethodChannel(name: "com.swiftride.app/location", binaryMessenger: binaryMessenger)
    let paymentChannel = FlutterMethodChannel(name: "com.swiftride.app/payment", binaryMessenger: binaryMessenger)
    let safetyChannel = FlutterMethodChannel(name: "com.swiftride.app/safety", binaryMessenger: binaryMessenger)
    let deviceChannel = FlutterMethodChannel(name: "com.swiftride.app/device", binaryMessenger: binaryMessenger)

    // 1. Location Channel
    locationChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "checkLocationPermissions", "requestLocationPermissions":
        result(true)
      case "getCurrentLocation":
        let locationData: [String: Any] = [
          "latitude": 37.7749,
          "longitude": -122.4194,
          "heading": 45.0,
          "speed": 12.5,
          "isMock": false
        ]
        result(locationData)
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
