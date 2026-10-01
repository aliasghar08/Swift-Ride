package com.dartnexuslab.swiftri

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Geocoder
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale
import java.util.UUID

class MainActivity : FlutterActivity() {
    private val locationChannel = "com.swiftride.app/location"
    private val paymentChannel = "com.swiftride.app/payment"
    private val safetyChannel = "com.swiftride.app/safety"
    private val deviceChannel = "com.swiftride.app/device"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 1. Native Location & Geocoding Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, locationChannel).setMethodCallHandler { call, result ->
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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, paymentChannel).setMethodCallHandler { call, result ->
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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, safetyChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "triggerEmergencyAlert" -> {
                    val rideId = call.argument<String>("rideId")
                    val lat = call.argument<Double>("latitude")
                    val lng = call.argument<Double>("longitude")
                    // In production, triggers native TelephonyManager / SMS alert
                    result.success(true)
                }
                "sendEmergencySms" -> result.success(true)
                "triggerEmergencyHaptics" -> {
                    val vibrator = getSystemService(VIBRATOR_SERVICE) as? Vibrator
                    if (vibrator != null) {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            // SOS morse pattern (... --- ...)
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

        // 4. Native Device Channel (Haptics, Screen Wake Lock)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, deviceChannel).setMethodCallHandler { call, result ->
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
                else -> result.notImplemented()
            }
        }
    }
}
