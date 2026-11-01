import Flutter
import CoreLocation
import Foundation

public class NativeLocationService: NSObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var lastKnownLocation: CLLocation?
    private var pendingLocationRequests: [(id: UUID, result: FlutterResult)] = []

    // Retained strongly so method channel invocations reach Flutter
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

    public static func register(with messenger: FlutterBinaryMessenger) -> NativeLocationService {
        let service = NativeLocationService()
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

        case "getCurrentLocation":
            let status = locationManager.authorizationStatus
            if status == .denied || status == .restricted {
                result(FlutterError(code: "PERMISSION_DENIED", message: "Location permission not granted.", details: nil))
                return
            }

            // 1. FAST-PATH: Return immediate valid cached location (< 10 minutes old) instantly
            if let loc = lastKnownLocation ?? locationManager.location, loc.horizontalAccuracy >= 0 {
                let age = abs(loc.timestamp.timeIntervalSinceNow)
                if age < 600.0 {
                    lastKnownLocation = loc
                    result(Self.serialize(loc))
                    // Trigger a background single-shot location request to refine accuracy silently
                    if status == .authorizedWhenInUse || status == .authorizedAlways {
                        locationManager.requestLocation()
                    }
                    return
                }
            }

            // 2. COLD START: Wait for GPS acquisition with a generous 12-second deadline
            let id = UUID()
            pendingLocationRequests.append((id: id, result: result))

            if status == .notDetermined {
                locationManager.requestWhenInUseAuthorization()
            }
            locationManager.startUpdatingLocation()
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                locationManager.requestLocation()
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 12.0) { [weak self] in
                guard let self = self else { return }
                if let idx = self.pendingLocationRequests.firstIndex(where: { $0.id == id }) {
                    let req = self.pendingLocationRequests.remove(at: idx)
                    if let fallback = self.lastKnownLocation ?? self.locationManager.location, fallback.horizontalAccuracy >= 0 {
                        req.result(Self.serialize(fallback))
                    } else {
                        req.result(FlutterError(code: "LOCATION_TIMEOUT", message: "No GPS fix within timeout.", details: nil))
                    }
                }
            }

        case "startLocationUpdates":
            let status = locationManager.authorizationStatus
            if status == .authorizedAlways {
                if let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String],
                   modes.contains("location") {
                    locationManager.allowsBackgroundLocationUpdates = true
                    if #available(iOS 11.0, *) {
                        locationManager.showsBackgroundLocationIndicator = true
                    }
                }
            }

            if status == .authorizedWhenInUse || status == .authorizedAlways {
                locationManager.startUpdatingLocation()
                // Emit cached location immediately so UI doesn't spin waiting for first satellite tick
                if let initial = lastKnownLocation ?? locationManager.location, initial.horizontalAccuracy >= 0 {
                    let payload = Self.serialize(initial)
                    channel1?.invokeMethod("onLocationUpdate", arguments: payload)
                    channel2?.invokeMethod("onLocationUpdate", arguments: payload)
                }
            } else if status == .notDetermined {
                locationManager.requestWhenInUseAuthorization()
                locationManager.startUpdatingLocation()
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
            let location = CLLocation(latitude: lat, longitude: lng)
            geocoder.reverseGeocodeLocation(location) { placemarks, error in
                if let pm = placemarks?.first {
                    var parts: [String] = []
                    let streetNumber = pm.subThoroughfare?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let streetName = pm.thoroughfare?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let name = pm.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                    var plotOrStreet = ""
                    if !streetNumber.isEmpty && !streetName.isEmpty {
                        plotOrStreet = "Plot \(streetNumber), \(streetName)"
                    } else if !streetNumber.isEmpty {
                        plotOrStreet = "Plot \(streetNumber)"
                    } else if !streetName.isEmpty {
                        plotOrStreet = streetName
                    }

                    if !plotOrStreet.isEmpty {
                        parts.append(plotOrStreet)
                        if !name.isEmpty && name != streetNumber && name != streetName && !parts.contains(name) {
                            parts.insert(name, at: 0)
                        }
                    } else if !name.isEmpty {
                        parts.append(name)
                    }

                    if let subLoc = pm.subLocality, !subLoc.isEmpty, !parts.contains(subLoc) {
                        parts.append(subLoc)
                    }
                    if let loc = pm.locality, !loc.isEmpty, !parts.contains(loc) {
                        parts.append(loc)
                    }

                    let formatted = parts.joined(separator: ", ")
                    result(formatted.isEmpty ? String(format: "Location (%.4f, %.4f)", lat, lng) : formatted)
                } else {
                    result(String(format: "Location (%.4f, %.4f)", lat, lng))
                }
            }

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - CLLocationManagerDelegate
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        // Accept all valid locations (including cellular/approximate fixes with accuracy >= 0)
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
        failAllPendingLocationRequests(code: "LOCATION_ERROR", message: error.localizedDescription)
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        let authorized = (status == .authorizedWhenInUse || status == .authorizedAlways)
        if authorized {
            manager.startUpdatingLocation()
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
