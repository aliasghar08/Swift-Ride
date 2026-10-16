import Flutter
import CoreLocation
import Foundation

public class NativeLocationService: NSObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var lastKnownLocation: CLLocation?
    private var pendingLocationRequests: [(id: UUID, result: FlutterResult)] = []

    public override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 5.0
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.allowsBackgroundLocationUpdates = false
    }

    public static func register(with messenger: FlutterBinaryMessenger) -> NativeLocationService {
        let service = NativeLocationService()
        let channel1 = FlutterMethodChannel(name: "com.swiftride.app/location", binaryMessenger: messenger)
        let channel2 = FlutterMethodChannel(name: "com.dartnexuslab.swiftride/location", binaryMessenger: messenger)
        
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
                locationManager.requestWhenInUseAuthorization()
                result(false)
            } else {
                result(status == .authorizedWhenInUse || status == .authorizedAlways)
            }

        case "getCurrentLocation":
            let status = locationManager.authorizationStatus
            if status == .denied || status == .restricted {
                result(FlutterError(code: "PERMISSION_DENIED", message: "Location permission not granted.", details: nil))
                return
            }

            if let loc = lastKnownLocation, loc.horizontalAccuracy >= 0, loc.horizontalAccuracy < 200 {
                result(Self.serialize(loc))
                return
            }

            if let loc = locationManager.location, loc.horizontalAccuracy >= 0, loc.horizontalAccuracy < 200 {
                lastKnownLocation = loc
                result(Self.serialize(loc))
                return
            }

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
                    if let fallback = self.lastKnownLocation ?? self.locationManager.location {
                        req.result(Self.serialize(fallback))
                    } else {
                        req.result(FlutterError(code: "LOCATION_TIMEOUT", message: "No GPS fix within 12 seconds.", details: nil))
                    }
                }
            }

        case "startLocationUpdates", "stopLocationUpdates":
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
                    if let name = pm.name, !name.isEmpty { parts.append(name) }
                    if let subLoc = pm.subLocality, !subLoc.isEmpty { parts.append(subLoc) }
                    if let loc = pm.locality, !loc.isEmpty { parts.append(loc) }
                    result(parts.isEmpty ? (pm.thoroughfare ?? String(format: "Location (%.4f, %.4f)", lat, lng)) : parts.joined(separator: ", "))
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
        guard loc.horizontalAccuracy >= 0, loc.horizontalAccuracy < 200 else { return }
        lastKnownLocation = loc
        resolvePendingLocationRequests(with: loc)
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let nsError = error as NSError
        if nsError.domain == kCLErrorDomain {
            switch nsError.code {
            case 0, 3: return
            default: break
            }
        }
        failAllPendingLocationRequests(code: "LOCATION_ERROR", message: error.localizedDescription)
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        case .denied, .restricted:
            failAllPendingLocationRequests(code: "PERMISSION_DENIED", message: "Location permission was denied.")
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

    public static func serialize(_ loc: CLLocation) -> [String: Any] {
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
}
