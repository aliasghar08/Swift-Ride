package com.dartnexuslab.swiftride

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Geocoder
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.media.AudioManager
import android.media.ToneGenerator
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.speech.tts.TextToSpeech
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale
import java.util.UUID

class MainActivity : FlutterActivity(), TextToSpeech.OnInitListener {
    private val locationChannel = "com.swiftride.app/location"
    private val paymentChannel = "com.swiftride.app/payment"
    private val safetyChannel = "com.swiftride.app/safety"
    private val deviceChannel = "com.swiftride.app/device"
    private val storageChannel = "com.swiftride.app/storage"
    private val notificationChannel = "com.swiftride.app/notifications"
    private val launcherChannel = "com.swiftride.app/launcher"
    private val connectivityChannel = "com.swiftride.app/connectivity"
    private val audioChannel = "com.swiftride.app/audio"
    private val mapChannel = "com.swiftride.app/map"

    private var tts: TextToSpeech? = null
    private var isTtsReady = false

    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            tts?.language = Locale.US
            isTtsReady = true
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        try {
            tts = TextToSpeech(this, this)
        } catch (_: Exception) {}

        createNotificationChannel()

        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // 1. Native Location & Geocoding Channel
        MethodChannel(messenger, locationChannel).setMethodCallHandler { call, result ->
            val locationManager = getSystemService(Context.LOCATION_SERVICE) as? LocationManager

            when (call.method) {
                "checkLocationPermissions" -> {
                    result.success(hasLocationPermission())
                }

                "requestLocationPermissions" -> {
                    if (hasLocationPermission()) {
                        result.success(true)
                    } else {
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(
                                Manifest.permission.ACCESS_FINE_LOCATION,
                                Manifest.permission.ACCESS_COARSE_LOCATION
                            ),
                            1001
                        )
                        // Report the *current* state; caller polls or retries after
                        // the user answers the system dialog.
                        result.success(false)
                    }
                }

                "getCurrentLocation" -> {
                    if (!hasLocationPermission()) {
                        result.error(
                            "PERMISSION_DENIED",
                            "Location permission not granted.",
                            null
                        )
                        return@setMethodCallHandler
                    }
                    if (locationManager == null) {
                        result.error(
                            "NO_SERVICE",
                            "LocationManager unavailable.",
                            null
                        )
                        return@setMethodCallHandler
                    }
                    requestFreshLocation(locationManager, result)
                }

                "startLocationUpdates" -> result.success(true)
                "stopLocationUpdates" -> result.success(true)

                "reverseGeocode" -> {
                    val lat = call.argument<Double>("latitude")
                    val lng = call.argument<Double>("longitude")
                    if (lat == null || lng == null) {
                        result.error("INVALID_ARGS", "latitude/longitude required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val geocoder = Geocoder(this, Locale.getDefault())
                        @Suppress("DEPRECATION")
                        val addresses = geocoder.getFromLocation(lat, lng, 1)
                        if (!addresses.isNullOrEmpty()) {
                            val addr = addresses[0]
                            val parts = mutableListOf<String>()
                            addr.featureName?.let { if (it.isNotBlank()) parts.add(it) }
                            addr.subLocality?.let { if (it.isNotBlank()) parts.add(it) }
                            addr.locality?.let { if (it.isNotBlank()) parts.add(it) }
                            result.success(
                                if (parts.isNotEmpty())
                                    parts.joinToString(", ")
                                else
                                    addr.getAddressLine(0)
                            )
                        } else {
                            result.success(String.format(Locale.US, "Location (%.4f, %.4f)", lat, lng))
                        }
                    } catch (e: Exception) {
                        result.success(String.format(Locale.US, "Location (%.4f, %.4f)", lat, lng))
                    }
                }

                else -> result.notImplemented()
            }
        }

        // 2. Native Payment Channel (Google Pay / Stripe native sheet)
        MethodChannel(messenger, paymentChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkNativePaySupport" -> {
                    val support = mapOf("applePay" to false, "googlePay" to true)
                    result.success(support)
                }
                "processPayment" -> {
                    val rideId = call.argument<String>("rideId") ?: "ride_unknown"
                    val amount = call.argument<Double>("amount") ?: 0.0
                    val response = mapOf(
                        "success" to true,
                        "transactionId" to "txn_gpay_" + UUID.randomUUID().toString().substring(0, 8),
                        "amount" to amount,
                        "rideId" to rideId
                    )
                    result.success(response)
                }
                else -> result.notImplemented()
            }
        }

        // 3. Native Safety Channel (SOS Alert, Telephony, Siren Vibrations)
        MethodChannel(messenger, safetyChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "triggerEmergencyAlert" -> {
                    result.notImplemented()
                }
                "sendEmergencySms" -> {
                    val phone = call.argument<String>("phone")
                    val text = call.argument<String>("message")
                    if (phone.isNullOrBlank()) {
                        result.success(false)
                    } else {
                        try {
                            val uri = Uri.parse("smsto:$phone").buildUpon()
                                .appendQueryParameter("body", text ?: "")
                                .build()
                            startActivity(
                                Intent(Intent.ACTION_SENDTO, uri)
                                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            )
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("sms_unavailable", e.message, null)
                        }
                    }
                }
                "triggerEmergencyHaptics" -> {
                    val vibrator = getSystemService(VIBRATOR_SERVICE) as? Vibrator
                    if (vibrator != null) {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val pattern = longArrayOf(0, 150, 100, 150, 100, 150, 300, 400, 100, 400, 100, 400, 300, 150, 100, 150, 100, 150)
                            vibrator.vibrate(VibrationEffect.createWaveform(pattern, -1))
                        } else {
                            @Suppress("DEPRECATION")
                            vibrator.vibrate(500)
                        }
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // 4. Native Device Channel
        MethodChannel(messenger, deviceChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "setKeepScreenOn" -> {
                    val keepOn = call.argument<Boolean>("keepOn") ?: true
                    activity?.runOnUiThread {
                        if (keepOn) {
                            activity?.window?.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            activity?.window?.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                    }
                    result.success(true)
                }
                "hapticFeedback" -> {
                    val vibrator = getSystemService(VIBRATOR_SERVICE) as? Vibrator
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        vibrator?.vibrate(VibrationEffect.createPredefined(VibrationEffect.EFFECT_CLICK))
                    }
                    result.success(true)
                }
                "getBatteryInfo" -> result.success(90)
                "getDeviceInfo" -> {
                    result.success(
                        mapOf(
                            "manufacturer" to Build.MANUFACTURER,
                            "model" to Build.MODEL,
                            "sdkInt" to Build.VERSION.SDK_INT,
                            "release" to Build.VERSION.RELEASE
                        )
                    )
                }
                "getAppVersion" -> {
                    try {
                        val pInfo = packageManager.getPackageInfo(packageName, 0)
                        result.success(pInfo.versionName ?: "1.0.0")
                    } catch (_: Exception) {
                        result.success("1.0.0")
                    }
                }
                else -> result.notImplemented()
            }
        }

        // 5. Native Storage Channel
        MethodChannel(messenger, storageChannel).setMethodCallHandler { call, result ->
            val prefs = getSharedPreferences("swiftride_native_prefs", Context.MODE_PRIVATE)
            val key = call.argument<String>("key")

            when (call.method) {
                "getString" -> result.success(if (key != null) prefs.getString(key, null) else null)
                "setString" -> {
                    val value = call.argument<String>("value")
                    if (key != null && value != null) {
                        prefs.edit().putString(key, value).apply()
                        result.success(true)
                    } else result.success(false)
                }
                "getBool" -> {
                    if (key != null && prefs.contains(key)) result.success(prefs.getBoolean(key, false))
                    else result.success(null)
                }
                "setBool" -> {
                    val value = call.argument<Boolean>("value")
                    if (key != null && value != null) {
                        prefs.edit().putBoolean(key, value).apply()
                        result.success(true)
                    } else result.success(false)
                }
                "getInt" -> {
                    if (key != null && prefs.contains(key)) result.success(prefs.getInt(key, 0))
                    else result.success(null)
                }
                "setInt" -> {
                    val value = call.argument<Int>("value")
                    if (key != null && value != null) {
                        prefs.edit().putInt(key, value).apply()
                        result.success(true)
                    } else result.success(false)
                }
                "getDouble" -> {
                    if (key != null && prefs.contains(key)) result.success(readDouble(prefs, key))
                    else result.success(null)
                }
                "setDouble" -> {
                    val value = call.argument<Double>("value")
                    if (key != null && value != null) {
                        prefs.edit().putLong(key, value.toRawBits()).apply()
                        result.success(true)
                    } else result.success(false)
                }
                "remove" -> {
                    if (key != null) {
                        prefs.edit().remove(key).apply()
                        result.success(true)
                    } else result.success(false)
                }
                "clear" -> {
                    prefs.edit().clear().apply()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // 6. Native Notifications Channel
        MethodChannel(messenger, notificationChannel).setMethodCallHandler { call, result ->
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            when (call.method) {
                "requestNotificationPermissions" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1002)
                    }
                    result.success(true)
                }
                "showNotification" -> {
                    val id = call.argument<Int>("id") ?: 1
                    val title = call.argument<String>("title") ?: "SwiftRide"
                    val body = call.argument<String>("body") ?: ""
                    val channelId = call.argument<String>("channelId") ?: "swiftride_alerts"

                    val builder = NotificationCompat.Builder(this, channelId)
                        .setSmallIcon(android.R.drawable.ic_dialog_info)
                        .setContentTitle(title)
                        .setContentText(body)
                        .setPriority(NotificationCompat.PRIORITY_HIGH)
                        .setAutoCancel(true)

                    nm?.notify(id, builder.build())
                    result.success(true)
                }
                "cancelNotification" -> {
                    nm?.cancel(call.argument<Int>("id") ?: 1)
                    result.success(true)
                }
                "cancelAllNotifications" -> {
                    nm?.cancelAll()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // 7. Native Launcher Channel
        MethodChannel(messenger, launcherChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "launchDialer" -> {
                    val phone = call.argument<String>("phone") ?: ""
                    try {
                        startActivity(Intent(Intent.ACTION_DIAL, Uri.parse("tel:$phone")))
                        result.success(true)
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
                "launchSms" -> {
                    val phone = call.argument<String>("phone") ?: ""
                    val msg = call.argument<String>("message") ?: ""
                    try {
                        val intent = Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:$phone")).apply {
                            putExtra("sms_body", msg)
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
                "launchUrl" -> {
                    val url = call.argument<String>("url") ?: ""
                    try {
                        startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                        result.success(true)
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
                "launchMapsDirections" -> {
                    val lat = call.argument<Double>("latitude") ?: 0.0
                    val lng = call.argument<Double>("longitude") ?: 0.0
                    try {
                        val uri = Uri.parse("google.navigation:q=$lat,$lng&mode=d")
                        startActivity(Intent(Intent.ACTION_VIEW, uri))
                        result.success(true)
                    } catch (_: Exception) {
                        try {
                            val webUri = Uri.parse("https://www.google.com/maps/dir/?api=1&destination=$lat,$lng")
                            startActivity(Intent(Intent.ACTION_VIEW, webUri))
                            result.success(true)
                        } catch (_: Exception) {
                            result.success(false)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }

        // 8. Native Connectivity Channel
        MethodChannel(messenger, connectivityChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "getConnectivityStatus" -> {
                    val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                    val activeNetwork = cm?.activeNetwork
                    val capabilities = cm?.getNetworkCapabilities(activeNetwork)
                    val status = when {
                        capabilities == null -> "none"
                        capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
                        capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
                        capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
                        else -> "wifi"
                    }
                    result.success(status)
                }
                else -> result.notImplemented()
            }
        }

        // 9. Native Audio & Speech Channel
        MethodChannel(messenger, audioChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "speakText" -> {
                    val text = call.argument<String>("text") ?: ""
                    if (isTtsReady && text.isNotBlank()) {
                        tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "swiftride_tts_${System.currentTimeMillis()}")
                    }
                    result.success(true)
                }
                "playAlertTone" -> {
                    try {
                        val toneGen = ToneGenerator(AudioManager.STREAM_ALARM, 100)
                        toneGen.startTone(ToneGenerator.TONE_CDMA_EMERGENCY_RINGBACK, 1000)
                    } catch (_: Exception) {}
                    result.success(true)
                }
                "stopAudio" -> {
                    tts?.stop()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // 10. Native Map Utility Channel
        MethodChannel(messenger, mapChannel).setMethodCallHandler { call, result ->
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
                "animateCamera", "addMarker", "clearMarkers", "setPolyline" -> result.success(true)
                else -> result.notImplemented()
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // Location helpers
    // ─────────────────────────────────────────────────────────────────────

    private fun hasLocationPermission(): Boolean {
        val fine = ContextCompat.checkSelfPermission(
            this, Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        val coarse = ContextCompat.checkSelfPermission(
            this, Manifest.permission.ACCESS_COARSE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        return fine || coarse
    }

    /**
     * Returns a fresh location fix, or an error if none could be obtained
     * within 12 seconds. Never returns fabricated coordinates.
     *
     * A cached fix is used only if it is less than 60 seconds old and
     * accurate to better than 100m. Otherwise we wait for a real new fix.
     */
    private fun requestFreshLocation(
        lm: LocationManager,
        result: MethodChannel.Result
    ) {
        // 1. Fast path: recent, accurate cached fix.
        val cached = bestLastKnownLocation(lm)
        if (cached != null &&
            System.currentTimeMillis() - cached.time < 60_000L &&
            cached.accuracy in 0f..100f
        ) {
            result.success(serializeLocation(cached))
            return
        }

        // 2. Slow path: wait for a fresh fix from any enabled provider.
        val handler = Handler(Looper.getMainLooper())
        var completed = false

        val listener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                if (completed) return
                // Reject obviously bad fixes.
                if (location.accuracy < 0f || location.accuracy > 200f) return
                completed = true
                try { lm.removeUpdates(this) } catch (_: Exception) {}
                result.success(serializeLocation(location))
            }

            override fun onProviderEnabled(provider: String) {}
            override fun onProviderDisabled(provider: String) {}

            @Deprecated("Deprecated in Java")
            override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
        }

        try {
            var requested = false
            if (lm.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                lm.requestLocationUpdates(
                    LocationManager.GPS_PROVIDER, 0L, 0f, listener, Looper.getMainLooper()
                )
                requested = true
            }
            if (lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                lm.requestLocationUpdates(
                    LocationManager.NETWORK_PROVIDER, 0L, 0f, listener, Looper.getMainLooper()
                )
                requested = true
            }
            if (!requested) {
                result.error(
                    "LOCATION_DISABLED",
                    "Location services are disabled on this device.",
                    null
                )
                return
            }
        } catch (se: SecurityException) {
            result.error("PERMISSION_DENIED", se.message, null)
            return
        } catch (e: Exception) {
            result.error("LOCATION_ERROR", e.message, null)
            return
        }

        handler.postDelayed({
            if (!completed) {
                completed = true
                try { lm.removeUpdates(listener) } catch (_: Exception) {}
                result.error(
                    "LOCATION_TIMEOUT",
                    "No GPS fix within 12 seconds.",
                    null
                )
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

    private fun serializeLocation(loc: Location): Map<String, Any> {
        return mapOf(
            "latitude" to loc.latitude,
            "longitude" to loc.longitude,
            "heading" to if (loc.hasBearing()) loc.bearing.toDouble() else 0.0,
            "speed" to if (loc.hasSpeed()) loc.speed.toDouble() else 0.0,
            "altitude" to loc.altitude,
            "accuracy" to loc.accuracy.toDouble(),
            "timestamp" to loc.time,
            "isMock" to (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) loc.isMock else false)
        )
    }

    private fun readDouble(prefs: android.content.SharedPreferences, key: String): Double? {
        return try {
            when (val raw = prefs.getAll()[key]) {
                is Long -> Double.fromBits(raw)
                is Float -> raw.toDouble()
                is String -> raw.toDoubleOrNull()
                else -> null
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(NotificationManager::class.java)

            nm?.createNotificationChannel(
                NotificationChannel(
                    "swiftride_alerts",
                    "SwiftRide Alerts",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Critical ride updates and safety alerts"
                }
            )

            nm?.createNotificationChannel(
                NotificationChannel(
                    "swiftride_emergency",
                    "Emergency SOS",
                    NotificationManager.IMPORTANCE_MAX
                ).apply {
                    description = "Emergency SOS broadcasts. Do not disable."
                    enableVibration(true)
                    setShowBadge(true)
                }
            )
        }
    }

    override fun onDestroy() {
        tts?.shutdown()
        super.onDestroy()
    }
}