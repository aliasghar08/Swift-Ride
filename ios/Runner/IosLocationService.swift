import Flutter
import CoreLocation
import Foundation

/// Dedicated native iOS Location service managing CoreLocation hardware lifecycle.
/// Mirrors Android's NativeLocationService.kt architecture.
public class IosLocationService: NSObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private var lastKnownLocation: CLLocation?
    private var pendingLocationRequests: [(id: UUID, result: FlutterResult)] = []

    // Method channels retained strongly
    private var channel1: FlutterMethodChannel?
    private var channel2: FlutterMethodChannel?
    private var pendingPermissionRequests: [FlutterResult] = []

    public override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 5.0
        locationManager.pausesLocationUpdatesAutomatically = false

        // Pre-warm location from OS cache immediately so UI doesn't wait
        if let cached = locationManager.location, cached.horizontalAccuracy >= 0 {
            self.lastKnownLocation = cached
        }
    }

    public static func register(with messenger: FlutterBinaryMessenger) -> IosLocationService {
        let service = IosLocationService()
        let channel1 = FlutterMethodChannel(name: "com.swiftride.app/location", binaryMessenger: messenger)
        let channel2 = FlutterMethodChannel(name: "com.dartnexuslab.swiftride/location", binaryMessenger: messenger)
        service.channel1 = channel1
        service.channel2 = channel2

        let handler: FlutterMethodCallHandler = { [weak service] call, result in
            service?.handle(call, result: result)
        }
        channel1.setMethodCallHandler(handler)
        channel2.setMethodCallHandler(handler)
        return service
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "checkLocationPermissions":
            let status = locationManager.authorizationStatus
            let ok = (status == .authorizedWhenInUse || status == .authorizedAlways)
            result(ok)

        case "checkBackgroundLocationPermission":
            let status = locationManager.authorizationStatus
            result(status == .authorizedAlways)

        case "requestLocationPermissions":
            let status = locationManager.authorizationStatus
            if status == .notDetermined {
                pendingPermissionRequests.append(result)
                locationManager.requestWhenInUseAuthorization()
                DispatchQueue.main.asyncAfter(deadline: .now() + 15.0) { [weak self] in
                    guard let self = self else { return }
                    if !self.pendingPermissionRequests.isEmpty {
                        let pending = self.pendingPermissionRequests
                        self.pendingPermissionRequests.removeAll()
                        let s = self.locationManager.authorizationStatus
                        let authorized = (s == .authorizedWhenInUse || s == .authorizedAlways)
                        for r in pending { r(authorized) }
                    }
                }
            } else {
                result(status == .authorizedWhenInUse || status == .authorizedAlways)
            }

        case "requestBackgroundLocationPermission":
            let status = locationManager.authorizationStatus
            if status == .authorizedAlways {
                result(true)
            } else {
                pendingPermissionRequests.append(result)
                locationManager.requestAlwaysAuthorization()
                DispatchQueue.main.asyncAfter(deadline: .now() + 15.0) { [weak self] in
                    guard let self = self else { return }
                    if !self.pendingPermissionRequests.isEmpty {
                        let pending = self.pendingPermissionRequests
                        self.pendingPermissionRequests.removeAll()
                        let s = self.locationManager.authorizationStatus
                        let authorized = (s == .authorizedAlways)
                        for r in pending { r(authorized) }
                    }
                }
            }

        case "getCurrentLocation":
            let status = locationManager.authorizationStatus
            if status == .denied || status == .restricted {
                result(FlutterError(code: "PERMISSION_DENIED", message: "Location permission not granted.", details: nil))
                return
            }

            // 1. FAST-PATH: Return immediate valid cached location (< 120s old) instantly
            // while simultaneously requesting a fresh GPS fix (mirroring Android's lastLocation + FusedClient)
            if let loc = locationManager.location ?? lastKnownLocation, loc.horizontalAccuracy >= 0 {
                let age = abs(loc.timestamp.timeIntervalSinceNow)
                if age < 120.0 && loc.horizontalAccuracy <= 1000.0 {
                    lastKnownLocation = loc
                    result(Self.serialize(loc))
                    // Trigger a background single-shot location request to refine accuracy silently
                    if status == .authorizedWhenInUse || status == .authorizedAlways {
                        locationManager.requestLocation()
                    }
                    return
                }
            }

            // 2. COLD START: Wait for GPS acquisition with an 8-second deadline
            let id = UUID()
            pendingLocationRequests.append((id: id, result: result))

            // Queue pending request when authorization is not determined yet,
            // automatically resuming inside locationManagerDidChangeAuthorization once granted
            if status == .notDetermined {
                locationManager.requestWhenInUseAuthorization()
            } else if status == .authorizedWhenInUse || status == .authorizedAlways {
                locationManager.startUpdatingLocation()
                locationManager.requestLocation()
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { [weak self] in
                guard let self = self else { return }
                if let idx = self.pendingLocationRequests.firstIndex(where: { $0.id == id }) {
                    let req = self.pendingLocationRequests.remove(at: idx)
                    if let fallback = self.locationManager.location ?? self.lastKnownLocation, fallback.horizontalAccuracy >= 0 {
                        req.result(Self.serialize(fallback))
                    } else if let fallback = self.locationManager.location ?? self.lastKnownLocation {
                        req.result(Self.serialize(fallback))
                    } else {
                        req.result(FlutterError(code: "LOCATION_TIMEOUT", message: "No GPS fix within timeout.", details: nil))
                    }
                }
            }

        case "startLocationUpdates":
            let mode = (call.arguments as? [String: Any])?["mode"] as? String ?? "balanced"
            let isHighAccuracy = (mode == "high_accuracy")
            locationManager.desiredAccuracy = isHighAccuracy ? kCLLocationAccuracyBest : kCLLocationAccuracyHundredMeters
            locationManager.distanceFilter = isHighAccuracy ? 10.0 : 20.0

            let status = locationManager.authorizationStatus
            if status == .authorizedAlways {
                if let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String],
                   modes.contains("location") {
                    locationManager.allowsBackgroundLocationUpdates = isHighAccuracy
                    if #available(iOS 11.0, *) {
                        locationManager.showsBackgroundLocationIndicator = isHighAccuracy
                    }
                }
            }

            if status == .authorizedWhenInUse || status == .authorizedAlways {
                locationManager.startUpdatingLocation()
                // Emit cached location immediately so UI doesn't spin waiting for first satellite tick
                if let initial = locationManager.location ?? lastKnownLocation, initial.horizontalAccuracy >= 0 {
                    let payload = Self.serialize(initial)
                    channel1?.invokeMethod("onLocationUpdate", arguments: payload)
                    channel2?.invokeMethod("onLocationUpdate", arguments: payload)
                }
            }
            result(true)

        case "stopLocationUpdates":
            locationManager.allowsBackgroundLocationUpdates = false
            locationManager.stopUpdatingLocation()
            result(true)

        case "reverseGeocode":
            guard let args = call.arguments as? [String: Any],
                  let lat = args["latitude"] as? Double,
                  let lng = args["longitude"] as? Double else {
                result(FlutterError(code: "INVALID_ARGS", message: "latitude and longitude required", details: nil))
                return
            }
            IosGeocodingService.shared.reverseGeocode(latitude: lat, longitude: lng) { formatted in
                result(formatted)
            }

        case "reverseGeocodeDetailed":
            guard let args = call.arguments as? [String: Any],
                  let lat = args["latitude"] as? Double,
                  let lng = args["longitude"] as? Double else {
                result(FlutterError(code: "INVALID_ARGS", message: "latitude and longitude required", details: nil))
                return
            }
            IosGeocodingService.shared.reverseGeocodeDetailed(latitude: lat, longitude: lng) { dict in
                result(dict)
            }

        case "panReverseGeocode":
            guard let args = call.arguments as? [String: Any],
                  let lat = args["latitude"] as? Double,
                  let lng = args["longitude"] as? Double else {
                result(FlutterError(code: "INVALID_ARGS", message: "latitude and longitude required", details: nil))
                return
            }
            IosGeocodingService.shared.panReverseGeocode(latitude: lat, longitude: lng) { dict in
                result(dict)
            }

        case "cancelPendingGeocode":
            IosGeocodingService.shared.cancelPendingGeocode()
            result(true)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - CLLocationManagerDelegate
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        guard loc.horizontalAccuracy >= 0 else { return }
        lastKnownLocation = loc
        resolvePendingLocationRequests(with: loc)

        let payload = Self.serialize(loc)
        channel1?.invokeMethod("onLocationUpdate", arguments: payload)
        channel2?.invokeMethod("onLocationUpdate", arguments: payload)
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let nsError = error as NSError
        if nsError.domain == kCLErrorDomain {
            switch nsError.code {
            case 0, 3: return // kCLErrorLocationUnknown or kCLErrorHeadingFailure: transient, ignore
            default: break
            }
        }
        let status = manager.authorizationStatus
        if status == .denied || status == .restricted {
            failAllPendingLocationRequests(code: "PERMISSION_DENIED", message: error.localizedDescription)
        }
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        let authorized = (status == .authorizedWhenInUse || status == .authorizedAlways)
        if authorized {
            manager.startUpdatingLocation()
            manager.requestLocation()
            if let loc = manager.location, loc.horizontalAccuracy >= 0 {
                lastKnownLocation = loc
                resolvePendingLocationRequests(with: loc)
                let payload = Self.serialize(loc)
                channel1?.invokeMethod("onLocationUpdate", arguments: payload)
                channel2?.invokeMethod("onLocationUpdate", arguments: payload)
            }
        }
        if !pendingPermissionRequests.isEmpty {
            let pending = pendingPermissionRequests
            pendingPermissionRequests.removeAll()
            for req in pending {
                req(authorized)
            }
        }
        if status == .denied || status == .restricted {
            failAllPendingLocationRequests(code: "PERMISSION_DENIED", message: "Location permission was denied.")
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

    public static func serialize(_ loc: CLLocation) -> [String: Any] {
        var isMock = false
        if #available(iOS 15.0, *) {
            if let source = loc.sourceInformation {
                isMock = source.isSimulatedBySoftware || source.isProducedByAccessory
            }
        }

        return [
            "latitude": loc.coordinate.latitude,
            "longitude": loc.coordinate.longitude,
            "heading": loc.course >= 0 ? loc.course : 0.0,
            "speed": loc.speed >= 0 ? loc.speed : 0.0,
            "altitude": loc.altitude,
            "accuracy": loc.horizontalAccuracy,
            "timestamp": loc.timestamp.timeIntervalSince1970 * 1000.0,
            "isMock": isMock,
        ]
    }
}
