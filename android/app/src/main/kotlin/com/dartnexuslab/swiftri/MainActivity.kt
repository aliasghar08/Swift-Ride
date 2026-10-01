package com.dartnexuslab.swiftri

import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

class MainActivity : FlutterActivity() {
    private val locationChannel = "com.swiftride.app/location"
    private val paymentChannel = "com.swiftride.app/payment"
    private val safetyChannel = "com.swiftride.app/safety"
    private val deviceChannel = "com.swiftride.app/device"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 1. Native Location Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, locationChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkLocationPermissions" -> result.success(true)
                "requestLocationPermissions" -> result.success(true)
                "getCurrentLocation" -> {
                    val locationData = mapOf(
                        "latitude" to 37.7749,
                        "longitude" to -122.4194,
                        "heading" to 45.0,
                        "speed" to 12.5,
                        "isMock" to false
                    )
                    result.success(locationData)
                }
                "startLocationUpdates" -> result.success(true)
                "stopLocationUpdates" -> result.success(true)
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
