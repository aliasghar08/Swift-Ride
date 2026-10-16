import Flutter
import UIKit
import GoogleMaps

class NativeMapViewFactory: NSObject, FlutterPlatformViewFactory {
  private var messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    return NativeMapView(
      frame: frame,
      viewIdentifier: viewId,
      arguments: args,
      messenger: messenger
    )
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    return FlutterStandardMessageCodec.sharedInstance()
  }
}

class NativeMapView: NSObject, FlutterPlatformView, GMSMapViewDelegate {
  private var mapView: GMSMapView
  private var channel: FlutterMethodChannel
  private var markers = [String: GMSMarker]()
  private var polylines = [String: GMSPolyline]()

  private var initialLat: Double = 31.2785
  private var initialLng: Double = 72.3317

  init(
    frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?,
    messenger: FlutterBinaryMessenger
  ) {
    let params = args as? [String: Any]
    initialLat = params?["initialLat"] as? Double ?? 31.2785
    initialLng = params?["initialLng"] as? Double ?? 72.3317
    let initialZoom = Float(params?["initialZoom"] as? Double ?? 15.0)

    let camera = GMSCameraPosition.camera(
      withLatitude: initialLat,
      longitude: initialLng,
      zoom: initialZoom
    )

    mapView = GMSMapView.map(withFrame: frame, camera: camera)
    channel = FlutterMethodChannel(
      name: "com.swiftride.app/native_map_view_\(viewId)",
      binaryMessenger: messenger
    )

    super.init()

    mapView.delegate = self
    mapView.isBuildingsEnabled = true

    if let styleJson = params?["mapStyle"] as? String, !styleJson.isEmpty {
      do {
        mapView.mapStyle = try GMSMapStyle(jsonString: styleJson)
      } catch {
        NSLog("[NativeMapView] Map style parsing error: %@", error.localizedDescription)
      }
    }

    channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      self?.handleMethodCall(call, result: result)
    }

    DispatchQueue.main.async { [weak self] in
      self?.channel.invokeMethod("onMapReady", arguments: nil)
    }
  }

  func view() -> UIView {
    return mapView
  }

  // MARK: - GMSMapViewDelegate

  func mapView(_ mapView: GMSMapView, didTapAt coordinate: CLLocationCoordinate2D) {
    channel.invokeMethod("onMapTap", arguments: [
      "latitude": coordinate.latitude,
      "longitude": coordinate.longitude
    ])
  }

  func mapView(_ mapView: GMSMapView, idleAt position: GMSCameraPosition) {
    channel.invokeMethod("onCameraIdle", arguments: [
      "latitude": position.target.latitude,
      "longitude": position.target.longitude,
      "zoom": position.zoom
    ])
  }

  func mapView(_ mapView: GMSMapView, didChange position: GMSCameraPosition) {
    channel.invokeMethod("onCameraMove", arguments: [
      "latitude": position.target.latitude,
      "longitude": position.target.longitude
    ])
  }

  // MARK: - Method Handling

  private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "animateCamera":
      guard let args = call.arguments as? [String: Any] else {
        result(false)
        return
      }
      let lat = args["latitude"] as? Double ?? initialLat
      let lng = args["longitude"] as? Double ?? initialLng
      let target = CLLocationCoordinate2D(latitude: lat, longitude: lng)

      if let zoom = args["zoom"] as? Double {
        let update = GMSCameraUpdate.setTarget(target, zoom: Float(zoom))
        mapView.animate(with: update)
      } else {
        let update = GMSCameraUpdate.setTarget(target)
        mapView.animate(with: update)
      }
      result(true)

    case "setMarkers":
      guard let args = call.arguments as? [String: Any],
            let list = args["markers"] as? [[String: Any]] else {
        result(false)
        return
      }

      for (_, m) in markers { m.map = nil }
      markers.removeAll()

      for item in list {
        guard let id = item["id"] as? String,
              let lat = item["latitude"] as? Double,
              let lng = item["longitude"] as? Double else {
          continue
        }

        let marker = GMSMarker(position: CLLocationCoordinate2D(latitude: lat, longitude: lng))
        marker.title = item["title"] as? String
        marker.groundAnchor = CGPoint(x: 0.5, y: 0.5)

        if let rotation = item["rotation"] as? Double {
          marker.rotation = rotation
        }

        let hue = item["hue"] as? Double ?? 0.0
        marker.icon = GMSMarker.markerImage(with: UIColor(hue: CGFloat(hue / 360.0), saturation: 1.0, brightness: 1.0, alpha: 1.0))
        marker.map = mapView
        markers[id] = marker
      }
      result(true)

    case "setPolylines":
      guard let args = call.arguments as? [String: Any],
            let list = args["polylines"] as? [[String: Any]] else {
        result(false)
        return
      }

      for (_, p) in polylines { p.map = nil }
      polylines.removeAll()

      for item in list {
        guard let id = item["id"] as? String,
              let rawPoints = item["points"] as? [[String: Any]] else {
          continue
        }

        let path = GMSMutablePath()
        for pt in rawPoints {
          if let lat = pt["latitude"] as? Double, let lng = pt["longitude"] as? Double {
            path.add(CLLocationCoordinate2D(latitude: lat, longitude: lng))
          }
        }

        let polyline = GMSPolyline(path: path)
        let colorInt = item["color"] as? Int64 ?? 0xFF0000FF
        let a = CGFloat((colorInt >> 24) & 0xFF) / 255.0
        let r = CGFloat((colorInt >> 16) & 0xFF) / 255.0
        let g = CGFloat((colorInt >> 8) & 0xFF) / 255.0
        let b = CGFloat(colorInt & 0xFF) / 255.0
        polyline.strokeColor = UIColor(red: r, green: g, blue: b, alpha: a > 0 ? a : 1.0)
        polyline.strokeWidth = CGFloat(item["width"] as? Double ?? 5.0)
        polyline.geodesic = true
        polyline.map = mapView
        polylines[id] = polyline
      }
      result(true)

    case "setMyLocationEnabled":
      let enabled = (call.arguments as? [String: Any])?["enabled"] as? Bool ?? false
      mapView.isMyLocationEnabled = enabled
      result(true)

    case "setTrafficEnabled":
      let enabled = (call.arguments as? [String: Any])?["enabled"] as? Bool ?? false
      mapView.isTrafficEnabled = enabled
      result(true)

    case "setMapStyle":
      if let styleStr = (call.arguments as? [String: Any])?["style"] as? String {
        do {
          mapView.mapStyle = try GMSMapStyle(jsonString: styleStr)
          result(true)
        } catch {
          result(FlutterError(code: "STYLE_ERROR", message: error.localizedDescription, details: nil))
        }
      } else {
        result(false)
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
