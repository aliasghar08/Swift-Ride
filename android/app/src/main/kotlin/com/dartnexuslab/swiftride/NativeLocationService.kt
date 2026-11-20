package com.dartnexuslab.swiftride

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.location.Address
import android.location.Geocoder
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.CancellationTokenSource
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

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
    private val geocodeExecutor = Executors.newCachedThreadPool()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var locationCallback: LocationCallback? = null
    private var primaryChannel: MethodChannel? = null
    private var altChannel: MethodChannel? = null

    companion object {
        const val PERMISSION_REQUEST_CODE = 1001
        const val BACKGROUND_PERMISSION_REQUEST_CODE = 1003
        const val PRIMARY_CHANNEL = "com.swiftride.app/location"
        const val ALT_CHANNEL = "com.dartnexuslab.swiftride/location"

        fun registerWith(messenger: BinaryMessenger, activity: Activity): NativeLocationService {
            val service = NativeLocationService(activity)
            val pChan = MethodChannel(messenger, PRIMARY_CHANNEL)
            val aChan = MethodChannel(messenger, ALT_CHANNEL)
            service.primaryChannel = pChan
            service.altChannel = aChan
            pChan.setMethodCallHandler(service)
            aChan.setMethodCallHandler(service)
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

    fun hasBackgroundLocationPermission(): Boolean {
        if (!hasLocationPermission()) return false
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ContextCompat.checkSelfPermission(
                activity, Manifest.permission.ACCESS_BACKGROUND_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
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
        } else if (requestCode == BACKGROUND_PERMISSION_REQUEST_CODE) {
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

            "checkBackgroundLocationPermission" -> {
                result.success(hasBackgroundLocationPermission())
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

            "requestBackgroundLocationPermission" -> {
                if (hasBackgroundLocationPermission()) {
                    result.success(true)
                } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    pendingPermissionResult = result
                    ActivityCompat.requestPermissions(
                        activity,
                        arrayOf(Manifest.permission.ACCESS_BACKGROUND_LOCATION),
                        BACKGROUND_PERMISSION_REQUEST_CODE
                    )
                } else {
                    result.success(true)
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

            "startLocationUpdates" -> {
                val mode = call.argument<String>("mode") ?: "balanced"
                startContinuousUpdates(mode)
                result.success(true)
            }

            "stopLocationUpdates" -> {
                stopContinuousUpdates()
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
     * Obtains location using FusedLocationProviderClient with fast-path on-device cache,
     * tight timeouts, and immediate fallback to LocationManager to prevent hangs on slow networks.
     */
    private fun fetchCurrentLocation(result: MethodChannel.Result) {
        if (!hasLocationPermission()) {
            result.error("PERMISSION_DENIED", "Location permission missing", null)
            return
        }

        var completed = false
        val handler = Handler(Looper.getMainLooper())

        val sendSuccess: (Location) -> Unit = { loc ->
            if (!completed) {
                completed = true
                result.success(serializeLocation(loc))
            }
        }

        // 1. FAST-PATH: Return immediate valid cached location (< 15 min old, accuracy <= 1000m) instantly (0-5ms)
        // This avoids blocking or hanging when mobile data is on 2G/3G/spotty network.
        try {
            fusedClient.lastLocation.addOnSuccessListener { lastLoc: Location? ->
                if (lastLoc != null && !completed) {
                    val age = System.currentTimeMillis() - lastLoc.time
                    if (age < 15 * 60_000L && lastLoc.accuracy in 0f..1000f) {
                        sendSuccess(lastLoc)
                        // Trigger background fresh fix silently to refine accuracy
                        try {
                            fusedClient.getCurrentLocation(Priority.PRIORITY_HIGH_ACCURACY, null)
                        } catch (_: Exception) {}
                        return@addOnSuccessListener
                    }
                }
            }
        } catch (_: Exception) {}

        // 2. FRESH FIX with responsive 8-second timeout
        try {
            val cancellationTokenSource = CancellationTokenSource()
            val fusedTimeoutRunnable = Runnable {
                if (!completed) {
                    cancellationTokenSource.cancel()
                    fallbackToLocationManager(result, onCompleted = { completed }, onFinish = { completed = true })
                }
            }
            handler.postDelayed(fusedTimeoutRunnable, 8_000L)

            fusedClient.getCurrentLocation(
                Priority.PRIORITY_HIGH_ACCURACY,
                cancellationTokenSource.token
            ).addOnSuccessListener { location: Location? ->
                handler.removeCallbacks(fusedTimeoutRunnable)
                if (location != null && !completed) {
                    sendSuccess(location)
                } else if (!completed) {
                    fallbackToLocationManager(result, onCompleted = { completed }, onFinish = { completed = true })
                }
            }.addOnFailureListener {
                handler.removeCallbacks(fusedTimeoutRunnable)
                if (!completed) {
                    fallbackToLocationManager(result, onCompleted = { completed }, onFinish = { completed = true })
                }
            }
        } catch (_: SecurityException) {
            fallbackToLocationManager(result, onCompleted = { completed }, onFinish = { completed = true })
        } catch (_: Exception) {
            fallbackToLocationManager(result, onCompleted = { completed }, onFinish = { completed = true })
        }
    }

    private fun fallbackToLocationManager(
        result: MethodChannel.Result,
        onCompleted: () -> Boolean = { false },
        onFinish: () -> Unit = {}
    ) {
        if (onCompleted()) return

        val lm = activity.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
        if (lm == null) {
            onFinish()
            result.error("NO_LOCATION_SERVICE", "LocationManager unavailable", null)
            return
        }

        // Try cached location first - if any reasonable cached fix is available, return immediately!
        val cached = bestLastKnownLocation(lm)
        if (cached != null) {
            val age = System.currentTimeMillis() - cached.time
            if (age < 30 * 60_000L && cached.accuracy in 0f..1500f) {
                onFinish()
                result.success(serializeLocation(cached))
                return
            }
        }

        // Request single update with tight 4-second timeout
        var updateReceived = false
        val handler = Handler(Looper.getMainLooper())
        val listener = object : android.location.LocationListener {
            override fun onLocationChanged(loc: Location) {
                if (!updateReceived && !onCompleted()) {
                    updateReceived = true
                    onFinish()
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
            val best = bestLastKnownLocation(lm) ?: cached
            if (best != null && !onCompleted()) {
                onFinish()
                result.success(serializeLocation(best))
            } else if (!onCompleted()) {
                onFinish()
                result.error("LOCATION_UNAVAILABLE", "Cannot obtain location fix", null)
            }
            return
        }

        handler.postDelayed({
            if (!updateReceived && !onCompleted()) {
                updateReceived = true
                onFinish()
                try { lm.removeUpdates(listener) } catch (_: Exception) {}
                val fallback = bestLastKnownLocation(lm) ?: cached
                if (fallback != null) {
                    result.success(serializeLocation(fallback))
                } else {
                    result.error("LOCATION_TIMEOUT", "No GPS fix within timeout", null)
                }
            }
        }, 8_000L)
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
        val fallbackStr = String.format(Locale.US, "Location (%.4f, %.4f)", lat, lng)
        val completed = AtomicBoolean(false)

        val finishOnMain: (String) -> Unit = { resolved ->
            if (completed.compareAndSet(false, true)) {
                mainHandler.post {
                    try {
                        result.success(resolved)
                    } catch (_: Exception) {}
                }
            }
        }

        // Strict 3-second timeout guard so hung OEM Geocoder services never stall Dart
        mainHandler.postDelayed({
            finishOnMain(fallbackStr)
        }, 3_000L)

        geocodeExecutor.execute {
            try {
                if (!Geocoder.isPresent()) {
                    finishOnMain(fallbackStr)
                    return@execute
                }
                val geocoder = Geocoder(activity.applicationContext, Locale.getDefault())
                @Suppress("DEPRECATION")
                val addresses = geocoder.getFromLocation(lat, lng, 1)
                if (!addresses.isNullOrEmpty()) {
                    val addr = addresses[0]
                    val parts = mutableListOf<String>()
                    val streetNumber = addr.subThoroughfare?.trim() ?: ""
                    val streetName = addr.thoroughfare?.trim() ?: ""
                    val premises = addr.premises?.trim() ?: ""
                    val feature = addr.featureName?.trim() ?: ""

                    val plotOrHouse = when {
                        streetNumber.isNotEmpty() && streetName.isNotEmpty() -> {
                            val prefix = if (streetNumber.matches(Regex("^\\d+[A-Za-z]?$"))) "Plot $streetNumber" else streetNumber
                            "$prefix, $streetName"
                        }
                        streetNumber.isNotEmpty() -> {
                            if (streetNumber.matches(Regex("^\\d+[A-Za-z]?$"))) "Plot $streetNumber" else streetNumber
                        }
                        streetName.isNotEmpty() -> streetName
                        else -> ""
                    }

                    if (premises.isNotEmpty() && premises != streetNumber && premises != streetName) {
                        parts.add(premises)
                    }
                    if (feature.isNotEmpty() &&
                        feature != streetNumber &&
                        feature != streetName &&
                        feature != addr.subLocality &&
                        feature != addr.locality &&
                        !feature.matches(Regex("^[A-Za-z0-9]{4,8}\\+[A-Za-z0-9]{2,5}$")) &&
                        !parts.contains(feature)
                    ) {
                        parts.add(feature)
                    }
                    if (plotOrHouse.isNotEmpty() && !parts.contains(plotOrHouse)) {
                        parts.add(plotOrHouse)
                    }

                    addr.subLocality?.let { if (it.isNotBlank() && !parts.contains(it)) parts.add(it) }
                    addr.locality?.let { if (it.isNotBlank() && !parts.contains(it)) parts.add(it) }

                    val formatted = if (parts.isNotEmpty()) {
                        parts.joinToString(", ")
                    } else {
                        addr.getAddressLine(0) ?: fallbackStr
                    }
                    finishOnMain(formatted)
                } else {
                    finishOnMain(fallbackStr)
                }
            } catch (_: Exception) {
                finishOnMain(fallbackStr)
            }
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

    private fun startContinuousUpdates(mode: String) {
        if (!hasLocationPermission()) return
        stopContinuousUpdates()

        val isHighAccuracy = mode == "high_accuracy"
        val interval = if (isHighAccuracy) 2000L else 12000L
        val minDistance = if (isHighAccuracy) 5f else 20f
        val priority = if (isHighAccuracy) Priority.PRIORITY_HIGH_ACCURACY else Priority.PRIORITY_BALANCED_POWER_ACCURACY

        val request = LocationRequest.Builder(priority, interval)
            .setMinUpdateIntervalMillis(interval / 2)
            .setMinUpdateDistanceMeters(minDistance)
            .build()

        val callback = object : LocationCallback() {
            override fun onLocationResult(locationResult: LocationResult) {
                val loc = locationResult.lastLocation ?: return
                val payload = serializeLocation(loc)
                primaryChannel?.invokeMethod("onLocationUpdate", payload)
                altChannel?.invokeMethod("onLocationUpdate", payload)
            }
        }
        locationCallback = callback

        try {
            fusedClient.requestLocationUpdates(request, callback, Looper.getMainLooper())
        } catch (_: SecurityException) {} catch (_: Exception) {}
    }

    private fun stopContinuousUpdates() {
        locationCallback?.let {
            try { fusedClient.removeLocationUpdates(it) } catch (_: Exception) {}
        }
        locationCallback = null
    }

    fun onDestroy() {
        stopContinuousUpdates()
    }
}
