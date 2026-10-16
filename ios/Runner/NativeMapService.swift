import Flutter
import CoreLocation
import Foundation

public class NativeMapService: NSObject {
    private let locationService: NativeLocationService

    public init(locationService: NativeLocationService) {
        self.locationService = locationService
        super.init()
    }

    public static func register(with messenger: FlutterBinaryMessenger, locationService: NativeLocationService) -> NativeMapService {
        let service = NativeMapService(locationService: locationService)
        let channel1 = FlutterMethodChannel(name: "com.swiftride.app/map", binaryMessenger: messenger)
        let channel2 = FlutterMethodChannel(name: "com.dartnexuslab.swiftride/map", binaryMessenger: messenger)

        let handler: FlutterMethodCallHandler = { [weak service] call, result in
            service?.handle(call, result: result)
        }
        channel1.setMethodCallHandler(handler)
        channel2.setMethodCallHandler(handler)
        return service
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "calculateDistance":
            guard let args = call.arguments as? [String: Any],
                  let lat1 = args["lat1"] as? Double,
                  let lon1 = args["lon1"] as? Double,
                  let lat2 = args["lat2"] as? Double,
                  let lon2 = args["lon2"] as? Double else {
                result(0.0)
                return
            }
            let loc1 = CLLocation(latitude: lat1, longitude: lon1)
            let loc2 = CLLocation(latitude: lat2, longitude: lon2)
            let meters = loc1.distance(from: loc2)
            result(meters / 1000.0)

        case "checkLocationPermissions",
             "requestLocationPermissions",
             "getCurrentLocation",
             "reverseGeocode",
             "startLocationUpdates",
             "stopLocationUpdates":
            locationService.handle(call, result: result)

        case "animateCamera", "addMarker", "clearMarkers", "setPolyline":
            result(true)

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
