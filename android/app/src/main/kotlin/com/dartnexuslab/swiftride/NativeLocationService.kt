package com.dartnexuslab.swiftride

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.location.Geocoder
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.CancellationTokenSource
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

/**
 * Modular native Android Location and Geocoding service.
 *
 * Utilizes FusedLocationProviderClient (Google Play Services) with fallback
 * to Android LocationManager, and native Android Geocoder for reverse-geocoding.
 */
class NativeLocationService(
    private val activity: Activity
) : MethodChannel.MethodCallHandler {

    private val fusedClient: FusedLocationProviderClient =
        LocationServices.getFusedLocationProviderClient(activity)
    private var pendingPermissionResult: MethodChannel.Result? = null

    companion object {
        const val PERMISSION_REQUEST_CODE = 1001
        const val PRIMARY_CHANNEL = "com.swiftride.app/location"
        const val ALT_CHANNEL = "com.dartnexuslab.swiftride/location"

        fun registerWith(messenger: BinaryMessenger, activity: Activity): NativeLocationService {
            val service = NativeLocationService(activity)
            MethodChannel(messenger, PRIMARY_CHANNEL).setMethodCallHandler(service)
            MethodChannel(messenger, ALT_CHANNEL).setMethodCallHandler(service)
            return service
        }
    }

    fun hasLocationPermission(): Boolean {
        val fine = ContextCompat.checkSelfPermission(
            activity, Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        val coarse = ContextCompat.checkSelfPermission(
            activity, Manifest.permission.ACCESS_COARSE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        return fine || coarse
    }

    fun handleRequestPermissionsResult(
        requestCode: Int,
        grantResults: IntArray
    ): Boolean {
        if (requestCode == PERMISSION_REQUEST_CODE) {
            val granted = grantResults.isNotEmpty() &&
                grantResults.any { it == PackageManager.PERMISSION_GRANTED }
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
            return true
        }
        return false
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "checkLocationPermissions" -> {
                result.success(hasLocationPermission())
            }

            "requestLocationPermissions" -> {
                if (hasLocationPermission()) {
                    result.success(true)
                } else {
                    pendingPermissionResult = result
                    ActivityCompat.requestPermissions(
                        activity,
                        arrayOf(
                            Manifest.permission.ACCESS_FINE_LOCATION,
                            Manifest.permission.ACCESS_COARSE_LOCATION
                        ),
                        PERMISSION_REQUEST_CODE
                    )
                }
            }

            "getCurrentLocation" -> {
                if (!hasLocationPermission()) {
                    result.error(
                        "PERMISSION_DENIED",
                        "Location permission not granted.",
                        null
                    )
                    return
                }
                fetchCurrentLocation(result)
            }

            "startLocationUpdates", "stopLocationUpdates" -> {
                result.success(true)
            }

            "reverseGeocode" -> {
                val lat = call.argument<Double>("latitude")
                val lng = call.argument<Double>("longitude")
                if (lat == null || lng == null) {
                    result.error("INVALID_ARGS", "latitude and longitude required", null)
                    return
                }
                reverseGeocode(lat, lng, result)
            }

            else -> result.notImplemented()
        }
    }

    /**
     * Obtains the highest-accuracy fresh location using FusedLocationProviderClient,
     * falling back to LocationManager if Play Services is unavailable.
     */
    private fun fetchCurrentLocation(result: MethodChannel.Result) {
        if (!hasLocationPermission()) {
            result.error("PERMISSION_DENIED", "Location permission missing", null)
            return
        }

        try {
            val cancellationTokenSource = CancellationTokenSource()
            fusedClient.getCurrentLocation(
                Priority.PRIORITY_HIGH_ACCURACY,
                cancellationTokenSource.token
            ).addOnSuccessListener { location: Location? ->
                if (location != null) {
                    result.success(serializeLocation(location))
                } else {
                    fallbackToLocationManager(result)
                }
            }.addOnFailureListener {
                fallbackToLocationManager(result)
            }

            // Safety timeout after 10 seconds
            Handler(Looper.getMainLooper()).postDelayed({
                cancellationTokenSource.cancel()
            }, 10_000L)
        } catch (_: SecurityException) {
            fallbackToLocationManager(result)
        } catch (_: Exception) {
            fallbackToLocationManager(result)
        }
    }

    private fun fallbackToLocationManager(result: MethodChannel.Result) {
        val lm = activity.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
        if (lm == null) {
            result.error("NO_LOCATION_SERVICE", "LocationManager unavailable", null)
            return
        }

        // Try cached location first
        val cached = bestLastKnownLocation(lm)
        if (cached != null &&
            System.currentTimeMillis() - cached.time < 15 * 60_000L &&
            cached.accuracy in 0f..500f
        ) {
            result.success(serializeLocation(cached))
            return
        }

        // Request single update
        var completed = false
        val handler = Handler(Looper.getMainLooper())
        val listener = object : android.location.LocationListener {
            override fun onLocationChanged(loc: Location) {
                if (!completed) {
                    completed = true
                    try { lm.removeUpdates(this) } catch (_: Exception) {}
                    result.success(serializeLocation(loc))
                }
            }
            override fun onProviderEnabled(p: String) {}
            override fun onProviderDisabled(p: String) {}
            @Deprecated("Deprecated in Java")
            override fun onStatusChanged(p: String?, s: Int, e: android.os.Bundle?) {}
        }

        try {
            @Suppress("MissingPermission")
            if (lm.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                lm.requestSingleUpdate(LocationManager.GPS_PROVIDER, listener, Looper.getMainLooper())
            }
            @Suppress("MissingPermission")
            if (lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                lm.requestSingleUpdate(LocationManager.NETWORK_PROVIDER, listener, Looper.getMainLooper())
            }
        } catch (_: Exception) {
            val best = bestLastKnownLocation(lm)
            if (best != null) {
                result.success(serializeLocation(best))
            } else {
                result.error("LOCATION_UNAVAILABLE", "Cannot obtain location fix", null)
            }
            return
        }

        handler.postDelayed({
            if (!completed) {
                completed = true
                try { lm.removeUpdates(listener) } catch (_: Exception) {}
                val fallback = bestLastKnownLocation(lm) ?: cached
                if (fallback != null) {
                    result.success(serializeLocation(fallback))
                } else {
                    result.error("LOCATION_TIMEOUT", "No GPS fix within timeout", null)
                }
            }
        }, 12_000L)
    }

    private fun bestLastKnownLocation(lm: LocationManager): Location? {
        var best: Location? = null
        try {
            @Suppress("MissingPermission")
            for (provider in lm.getProviders(true)) {
                @Suppress("MissingPermission")
                val l = lm.getLastKnownLocation(provider) ?: continue
                if (best == null || l.accuracy < best.accuracy) best = l
            }
        } catch (_: SecurityException) {
        } catch (_: Exception) {
        }
        return best
    }

    private fun reverseGeocode(lat: Double, lng: Double, result: MethodChannel.Result) {
        try {
            val geocoder = Geocoder(activity, Locale.getDefault())
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                geocoder.getFromLocation(lat, lng, 1) { addresses ->
                    if (!addresses.isNullOrEmpty()) {
                        val addr = addresses[0]
                        val parts = mutableListOf<String>()
                        addr.featureName?.let { if (it.isNotBlank()) parts.add(it) }
                        addr.subLocality?.let { if (it.isNotBlank()) parts.add(it) }
                        addr.locality?.let { if (it.isNotBlank()) parts.add(it) }
                        result.success(
                            if (parts.isNotEmpty()) parts.joinToString(", ") else addr.getAddressLine(0)
                        )
                    } else {
                        result.success(String.format(Locale.US, "Location (%.4f, %.4f)", lat, lng))
                    }
                }
            } else {
                @Suppress("DEPRECATION")
                val addresses = geocoder.getFromLocation(lat, lng, 1)
                if (!addresses.isNullOrEmpty()) {
                    val addr = addresses[0]
                    val parts = mutableListOf<String>()
                    addr.featureName?.let { if (it.isNotBlank()) parts.add(it) }
                    addr.subLocality?.let { if (it.isNotBlank()) parts.add(it) }
                    addr.locality?.let { if (it.isNotBlank()) parts.add(it) }
                    result.success(
                        if (parts.isNotEmpty()) parts.joinToString(", ") else addr.getAddressLine(0)
                    )
                } else {
                    result.success(String.format(Locale.US, "Location (%.4f, %.4f)", lat, lng))
                }
            }
        } catch (e: Exception) {
            result.success(String.format(Locale.US, "Location (%.4f, %.4f)", lat, lng))
        }
    }

    private fun serializeLocation(loc: Location): Map<String, Any> {
        return mapOf(
            "latitude" to loc.latitude,
            "longitude" to loc.longitude,
            "heading" to loc.bearing.toDouble(),
            "speed" to loc.speed.toDouble(),
            "altitude" to loc.altitude,
            "accuracy" to loc.accuracy.toDouble(),
            "timestamp" to loc.time.toDouble(),
            "isMock" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) loc.isMock else false
        )
    }
}
