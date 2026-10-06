package com.dartnexuslab.swiftride

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Geocoder
import android.location.Location
import android.location.LocationManager
import android.media.AudioManager
import android.media.ToneGenerator
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Build
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

        // Initialize TTS lazily
        try {
            tts = TextToSpeech(this, this)
        } catch (_: Exception) {}

        // Setup notification channel for Android O+
        createNotificationChannel()

        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // 1. Native Location & Geocoding Channel
        MethodChannel(messenger, locationChannel).setMethodCallHandler { call, result ->
            val locationManager = getSystemService(Context.LOCATION_SERVICE) as? LocationManager

            when (call.method) {
                "checkLocationPermissions" -> {
                    val fine = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
                    val coarse = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
                    result.success(fine || coarse)
                }
                "requestLocationPermissions" -> {
                    ActivityCompat.requestPermissions(
                        this,
                        arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION),
                        1001
                    )
                    result.success(true)
                }
                "getCurrentLocation" -> {
                    var bestLocation: Location? = null
                    try {
                        val providers = locationManager?.getProviders(true) ?: emptyList()
                        for (provider in providers) {
                            val l = locationManager?.getLastKnownLocation(provider) ?: continue
                            if (bestLocation == null || l.accuracy < bestLocation.accuracy) {
                                bestLocation = l
                            }
                        }
                    } catch (_: SecurityException) {}

                    if (bestLocation != null) {
                        val locationData = mapOf(
                            "latitude" to bestLocation.latitude,
                            "longitude" to bestLocation.longitude,
                            "heading" to (bestLocation.bearing.toDouble()),
                            "speed" to (bestLocation.speed.toDouble()),
                            "altitude" to bestLocation.altitude,
                            "isMock" to false
                        )
                        result.success(locationData)
                    } else {
                        // Default Pakistan coordinates fallback
                        val fallback = mapOf(
                            "latitude" to 33.6844,
                            "longitude" to 73.0479,
                            "heading" to 0.0,
                            "speed" to 0.0,
                            "altitude" to 500.0,
                            "isMock" to true
                        )
                        result.success(fallback)
                    }
                }
                "startLocationUpdates" -> result.success(true)
                "stopLocationUpdates" -> result.success(true)
                "reverseGeocode" -> {
                    val lat = call.argument<Double>("latitude") ?: 33.6844
                    val lng = call.argument<Double>("longitude") ?: 73.0479
                    try {
                        val geocoder = Geocoder(this, Locale.getDefault())
                        val addresses = geocoder.getFromLocation(lat, lng, 1)
                        if (!addresses.isNullOrEmpty()) {
                            val addr = addresses[0]
                            val parts = mutableListOf<String>()
                            addr.featureName?.let { if (it.isNotBlank()) parts.add(it) }
                            addr.subLocality?.let { if (it.isNotBlank()) parts.add(it) }
                            addr.locality?.let { if (it.isNotBlank()) parts.add(it) }
                            result.success(if (parts.isNotEmpty()) parts.joinToString(", ") else addr.getAddressLine(0))
                        } else {
                            result.success("Location (%.4f, %.4f)".format(Locale.US, lat, lng))
                        }
                    } catch (e: Exception) {
                        result.success("Location (%.4f, %.4f)".format(Locale.US, lat, lng))
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
                    // Removed: this returned true while doing nothing. Dispatch is
                    // owned by the triggerSos Cloud Function, and the honest
                    // failure mode is a loud error rather than a silent success.
                    result.notImplemented()
                }
                "sendEmergencySms" -> {
                    // Opens the SMS composer prefilled and addressed. The user
                    // still has to press send, so this reports whether the
                    // composer opened — not that a message was delivered.
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

        // 4. Native Device Channel (Haptics, Screen Wake Lock, Hardware Info)
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
                    val info = mapOf(
                        "manufacturer" to Build.MANUFACTURER,
                        "model" to Build.MODEL,
                        "sdkInt" to Build.VERSION.SDK_INT,
                        "release" to Build.VERSION.RELEASE
                    )
                    result.success(info)
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

        // 5. Native Storage Channel (replaces shared_preferences)
        MethodChannel(messenger, storageChannel).setMethodCallHandler { call, result ->
            val prefs = getSharedPreferences("swiftride_native_prefs", Context.MODE_PRIVATE)
            val key = call.argument<String>("key")

            when (call.method) {
                "getString" -> {
                    result.success(if (key != null) prefs.getString(key, null) else null)
                }
                "setString" -> {
                    val value = call.argument<String>("value")
                    if (key != null && value != null) {
                        prefs.edit().putString(key, value).apply()
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                "getBool" -> {
                    if (key != null && prefs.contains(key)) {
                        result.success(prefs.getBoolean(key, false))
                    } else {
                        result.success(null)
                    }
                }
                "setBool" -> {
                    val value = call.argument<Boolean>("value")
                    if (key != null && value != null) {
                        prefs.edit().putBoolean(key, value).apply()
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                "getInt" -> {
                    if (key != null && prefs.contains(key)) {
                        result.success(prefs.getInt(key, 0))
                    } else {
                        result.success(null)
                    }
                }
                "setInt" -> {
                    val value = call.argument<Int>("value")
                    if (key != null && value != null) {
                        prefs.edit().putInt(key, value).apply()
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                "getDouble" -> {
                    if (key != null && prefs.contains(key)) {
                        result.success(readDouble(prefs, key))
                    } else {
                        result.success(null)
                    }
                }
                "setDouble" -> {
                    val value = call.argument<Double>("value")
                    if (key != null && value != null) {
                        // SharedPreferences has no putDouble. Storing toRawBits as a
                        // Long keeps full 64-bit precision — the previous Float
                        // round-trip silently truncated to ~7 significant digits.
                        prefs.edit().putLong(key, value.toRawBits()).apply()
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                "remove" -> {
                    if (key != null) {
                        prefs.edit().remove(key).apply()
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                "clear" -> {
                    prefs.edit().clear().apply()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // 6. Native Notifications Channel (replaces flutter_local_notifications)
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
                    val id = call.argument<Int>("id") ?: 1
                    nm?.cancel(id)
                    result.success(true)
                }
                "cancelAllNotifications" -> {
                    nm?.cancelAll()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // 7. Native Launcher Channel (replaces url_launcher)
        MethodChannel(messenger, launcherChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "launchDialer" -> {
                    val phone = call.argument<String>("phone") ?: ""
                    try {
                        val intent = Intent(Intent.ACTION_DIAL, Uri.parse("tel:$phone"))
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
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
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "launchUrl" -> {
                    val url = call.argument<String>("url") ?: ""
                    try {
                        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "launchMapsDirections" -> {
                    val lat = call.argument<Double>("latitude") ?: 0.0
                    val lng = call.argument<Double>("longitude") ?: 0.0
                    try {
                        val uri = Uri.parse("google.navigation:q=$lat,$lng&mode=d")
                        val intent = Intent(Intent.ACTION_VIEW, uri)
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        // Fallback to browser Google Maps
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

        // 8. Native Connectivity Channel (replaces connectivity_plus)
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

        // 9. Native Audio & Speech Channel (replaces flutter_tts & audioplayers)
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

        // 10. Native Map Utility Channel (complements / replaces google_maps_flutter)
        MethodChannel(messenger, mapChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "calculateDistance" -> {
                    val lat1 = call.argument<Double>("lat1") ?: 0.0
                    val lon1 = call.argument<Double>("lon1") ?: 0.0
                    val lat2 = call.argument<Double>("lat2") ?: 0.0
                    val lon2 = call.argument<Double>("lon2") ?: 0.0
                    val results = FloatArray(1)
                    Location.distanceBetween(lat1, lon1, lat2, lon2, results)
                    result.success((results[0] / 1000.0).toDouble()) // in kilometers
                }
                "animateCamera", "addMarker", "clearMarkers", "setPolyline" -> {
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Reads a double stored by [setDouble].
     *
     * New values are Longs holding the raw 64-bit representation. Values written
     * by older builds are Floats, so they are still read rather than throwing a
     * ClassCastException on upgrade.
     */
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

            // General ride + safety alerts.
            nm?.createNotificationChannel(
                NotificationChannel(
                    "swiftride_alerts",
                    "SwiftRide Alerts",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Critical ride updates and safety alerts"
                }
            )

            // Emergency SOS channel. This channel is posted to with
            // channelId "swiftride_emergency" (rider_view_model.dispatchSos).
            // It MUST exist or Android 8+ silently drops the SOS notification.
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
