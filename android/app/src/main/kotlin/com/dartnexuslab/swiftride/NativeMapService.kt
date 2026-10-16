package com.dartnexuslab.swiftride

import android.location.Location
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Reusable native Android Map service.
 * Handles distance calculations, camera commands, polyline utilities,
 * and delegates location queries to NativeLocationService.
 */
class NativeMapService(
    private val locationService: NativeLocationService
) : MethodChannel.MethodCallHandler {

    companion object {
        const val PRIMARY_CHANNEL = "com.swiftride.app/map"
        const val ALT_CHANNEL = "com.dartnexuslab.swiftride/map"

        fun registerWith(
            messenger: BinaryMessenger,
            locationService: NativeLocationService
        ): NativeMapService {
            val service = NativeMapService(locationService)
            MethodChannel(messenger, PRIMARY_CHANNEL).setMethodCallHandler(service)
            MethodChannel(messenger, ALT_CHANNEL).setMethodCallHandler(service)
            return service
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "calculateDistance" -> {
                val lat1 = call.argument<Double>("lat1") ?: 0.0
                val lon1 = call.argument<Double>("lon1") ?: 0.0
                val lat2 = call.argument<Double>("lat2") ?: 0.0
                val lon2 = call.argument<Double>("lon2") ?: 0.0
                val results = FloatArray(1)
                Location.distanceBetween(lat1, lon1, lat2, lon2, results)
                result.success((results[0] / 1000.0).toDouble())
            }

            // Location delegation so callers can invoke either channel seamlessly
            "checkLocationPermissions",
            "requestLocationPermissions",
            "getCurrentLocation",
            "reverseGeocode",
            "startLocationUpdates",
            "stopLocationUpdates" -> {
                locationService.onMethodCall(call, result)
            }

            "animateCamera", "addMarker", "clearMarkers", "setPolyline" -> {
                result.success(true)
            }

            else -> result.notImplemented()
        }
    }
}
