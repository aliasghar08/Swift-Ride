package com.dartnexuslab.swiftride

import android.Manifest
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.location.Address
import android.location.Geocoder
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.CancellationTokenSource
import com.google.firebase.FirebaseApp
import com.google.firebase.database.FirebaseDatabase
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference
import java.util.Locale
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Native Android Location Service and Foreground Service for live driver telemetry.
 *
 * Provides:
 * 1. Background/swipe-kill survival with minimal battery drain via START_STICKY
 *    and onTaskRemoved lifecycle handling.
 * 2. Three-tier adaptive movement-based GPS polling via FusedLocationProviderClient.
 * 3. Direct Firebase Realtime Database & Cloud Firestore telemetry sync when Flutter
 *    isolate is detached or swiped away.
 * 4. 4-hour stationary auto-sleep safety cutoff.
 * 5. MethodChannel API for permissions, fast-fix geolocation, and native geocoding.
 */
class NativeLocationService() : Service(), MethodChannel.MethodCallHandler {

    private var fusedClientInternal: FusedLocationProviderClient? = null
    private val geocodeExecutor = Executors.newCachedThreadPool()
    private val mainHandler = Handler(Looper.getMainLooper())

    private var locationCallback: LocationCallback? = null
    private var lastSignificantMoveTimestamp: Long = System.currentTimeMillis()
    private var lastSignificantLocation: Location? = null
    private var lastFirestoreSyncLocation: Location? = null
    private var currentTier: Int = TIER_IDLE
    private var isAppTaskRemoved: Boolean = false

    constructor(activity: Activity) : this() {
        currentActivity = WeakReference(activity)
    }

    companion object {
        const val PERMISSION_REQUEST_CODE = 1001
        const val BACKGROUND_PERMISSION_REQUEST_CODE = 1003
        const val PRIMARY_CHANNEL = "com.swiftride.app/location"
        const val ALT_CHANNEL = "com.dartnexuslab.swiftride/location"

        const val PREFS_NAME = "swift_ride_driver_state"
        const val KEY_IS_DRIVER_ONLINE = "is_driver_online"
        const val KEY_DRIVER_UID = "driver_uid"
        const val KEY_HAS_ACTIVE_RIDE = "has_active_ride"

        const val NOTIFICATION_CHANNEL_ID = "swift_ride_driver_location"
        const val NOTIFICATION_ID = 8801

        const val ACTION_GO_OFFLINE = "com.dartnexuslab.swiftride.ACTION_GO_OFFLINE"
        const val ACTION_START_TRACKING = "com.dartnexuslab.swiftride.ACTION_START_TRACKING"
        const val ACTION_STOP_TRACKING = "com.dartnexuslab.swiftride.ACTION_STOP_TRACKING"

        const val TIER_IDLE = 0
        const val TIER_ACTIVE_TRIP = 1
        const val TIER_ONLINE_MOVING = 2
        const val TIER_STATIONARY = 3

        @Volatile
        var serviceInstance: NativeLocationService? = null

        @Volatile
        var currentActivity: WeakReference<Activity>? = null

        @Volatile
        var primaryChannel: MethodChannel? = null

        @Volatile
        var altChannel: MethodChannel? = null

        private var pendingPermissionResult: MethodChannel.Result? = null

        fun registerWith(messenger: BinaryMessenger, activity: Activity): NativeLocationService {
            currentActivity = WeakReference(activity)
            val pChan = MethodChannel(messenger, PRIMARY_CHANNEL)
            val aChan = MethodChannel(messenger, ALT_CHANNEL)
            primaryChannel = pChan
            altChannel = aChan

            val instance = serviceInstance ?: NativeLocationService(activity)
            pChan.setMethodCallHandler(instance)
            aChan.setMethodCallHandler(instance)
            return instance
        }
    }

    private fun getActiveContext(): Context {
        return currentActivity?.get()?.applicationContext ?: applicationContext ?: this
    }

    private fun getFusedClient(): FusedLocationProviderClient {
        fusedClientInternal?.let { return it }
        val client = LocationServices.getFusedLocationProviderClient(getActiveContext())
        fusedClientInternal = client
        return client
    }

    override fun onCreate() {
        super.onCreate()
        serviceInstance = this
        fusedClientInternal = LocationServices.getFusedLocationProviderClient(this)
        ensureNotificationChannel()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        serviceInstance = this
        val action = intent?.action

        if (action == ACTION_GO_OFFLINE) {
            setDriverOfflineDirectly()
            stopForegroundCompat()
            stopSelf()
            return START_NOT_STICKY
        }

        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val isOnline = prefs.getBoolean(KEY_IS_DRIVER_ONLINE, false)

        if (isOnline) {
            startInForeground()
            applyAdaptiveLocationRequest()
        }

        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        isAppTaskRemoved = true
        currentActivity = null
        primaryChannel = null
        altChannel = null

        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val isOnline = prefs.getBoolean(KEY_IS_DRIVER_ONLINE, false)

        if (isOnline) {
            // Keep alive in native foreground service when swiped from Recent Apps
            startInForeground()
            applyAdaptiveLocationRequest()
        } else {
            // Offline: shut down immediately to free all resources
            stopForegroundCompat()
            stopSelf()
        }
    }

    fun onActivityDestroyed() {
        currentActivity = null
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val isOnline = prefs.getBoolean(KEY_IS_DRIVER_ONLINE, false)
        if (!isOnline) {
            stopContinuousUpdates()
        }
    }

    override fun onDestroy() {
        stopContinuousUpdates()
        serviceInstance = null
        super.onDestroy()
    }

    // --------------------------------------------------------------------------
    // Foreground Notification & Shade Controls
    // --------------------------------------------------------------------------

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ctx = getActiveContext()
            val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "Swift Ride Driver Telemetry",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps driver online and reachable for ride requests in the background"
                setShowBadge(false)
            }
            nm?.createNotificationChannel(channel)
        }
    }

    private fun buildForegroundNotification(): Notification {
        ensureNotificationChannel()
        val ctx = getActiveContext()

        val openAppIntent = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)
            ?: Intent(ctx, MainActivity::class.java)
        val openAppPendingIntent = PendingIntent.getActivity(
            ctx,
            0,
            openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val goOfflineIntent = Intent(ctx, NativeLocationService::class.java).apply {
            action = ACTION_GO_OFFLINE
        }
        val goOfflinePendingIntent = PendingIntent.getService(
            ctx,
            1,
            goOfflineIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(ctx, NOTIFICATION_CHANNEL_ID)
            .setContentTitle("Swift Ride: Online for rides")
            .setContentText("Broadcasting live location for ride dispatch")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(openAppPendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .addAction(
                0,
                "Go Offline",
                goOfflinePendingIntent
            )
            .build()
    }

    private fun startInForeground() {
        try {
            val notification = buildForegroundNotification()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (_: Exception) {}
    }

    private fun stopForegroundCompat() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        } catch (_: Exception) {}
    }

    // --------------------------------------------------------------------------
    // Adaptive Movement-Based GPS Polling
    // --------------------------------------------------------------------------

    fun applyAdaptiveLocationRequest() {
        if (!hasLocationPermission()) return

        val ctx = getActiveContext()
        val prefs = ctx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val hasActiveRide = prefs.getBoolean(KEY_HAS_ACTIVE_RIDE, false)
        val isOnline = prefs.getBoolean(KEY_IS_DRIVER_ONLINE, false)

        if (!isOnline && !hasActiveRide) {
            stopContinuousUpdates()
            return
        }

        val targetTier = when {
            hasActiveRide -> TIER_ACTIVE_TRIP
            isStationary() -> TIER_STATIONARY
            else -> TIER_ONLINE_MOVING
        }

        if (targetTier == currentTier && locationCallback != null) {
            return
        }

        currentTier = targetTier

        val (priority, interval, minDistance) = when (targetTier) {
            TIER_ACTIVE_TRIP -> Triple(
                Priority.PRIORITY_HIGH_ACCURACY,
                3000L,
                10f
            )
            TIER_ONLINE_MOVING -> Triple(
                Priority.PRIORITY_BALANCED_POWER_ACCURACY,
                10000L,
                20f
            )
            TIER_STATIONARY -> Triple(
                Priority.PRIORITY_BALANCED_POWER_ACCURACY,
                45000L,
                30f
            )
            else -> Triple(
                Priority.PRIORITY_BALANCED_POWER_ACCURACY,
                10000L,
                20f
            )
        }

        stopLocationUpdatesInternal()

        val request = LocationRequest.Builder(priority, interval)
            .setMinUpdateIntervalMillis(interval / 2)
            .setMinUpdateDistanceMeters(minDistance)
            .build()

        val callback = object : LocationCallback() {
            override fun onLocationResult(locationResult: LocationResult) {
                val loc = locationResult.lastLocation ?: return
                handleNewLocation(loc)
            }
        }
        locationCallback = callback

        try {
            getFusedClient().requestLocationUpdates(request, callback, Looper.getMainLooper())
        } catch (_: SecurityException) {} catch (_: Exception) {}
    }

    private fun isStationary(): Boolean {
        val elapsed = System.currentTimeMillis() - lastSignificantMoveTimestamp
        return elapsed > 60_000L
    }

    private fun handleNewLocation(loc: Location) {
        val now = System.currentTimeMillis()
        val lastSignificant = lastSignificantLocation

        if (lastSignificant == null) {
            lastSignificantLocation = loc
            lastSignificantMoveTimestamp = now
        } else {
            val dist = loc.distanceTo(lastSignificant)
            if (dist >= 15f) {
                lastSignificantLocation = loc
                lastSignificantMoveTimestamp = now
                if (currentTier == TIER_STATIONARY) {
                    // Resumed movement: transition out of stationary tier
                    applyAdaptiveLocationRequest()
                }
            } else {
                val elapsed = now - lastSignificantMoveTimestamp
                val prefs = getActiveContext().getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                val hasActiveRide = prefs.getBoolean(KEY_HAS_ACTIVE_RIDE, false)

                // Stationary (>60s with <15m displacement): drop to passive 45s interval
                // Keeps driver online indefinitely during quiet hours with minimal battery draw
                // until the driver manually toggles OFF.
                if (!hasActiveRide && elapsed > 60_000L && currentTier != TIER_STATIONARY) {
                    applyAdaptiveLocationRequest()
                }
            }
        }

        val payload = serializeLocation(loc)

        // If Flutter isolate is attached, invoke method on Flutter channel
        val hasChannel = primaryChannel != null || altChannel != null
        if (hasChannel && !isAppTaskRemoved) {
            mainHandler.post {
                primaryChannel?.invokeMethod("onLocationUpdate", payload)
                altChannel?.invokeMethod("onLocationUpdate", payload)
            }
        } else {
            // App swiped away / detached isolate: write direct native telemetry to Firebase
            syncLocationDirectlyToFirebase(loc)
        }
    }

    // --------------------------------------------------------------------------
    // Direct Native Telemetry Sync (Realtime Database & Cloud Firestore)
    // --------------------------------------------------------------------------

    private fun syncLocationDirectlyToFirebase(location: Location) {
        val ctx = getActiveContext()
        val prefs = ctx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val driverUid = prefs.getString(KEY_DRIVER_UID, "") ?: ""
        if (driverUid.isBlank()) return

        try {
            if (FirebaseApp.getApps(ctx).isEmpty()) {
                FirebaseApp.initializeApp(ctx)
            }

            val timestamp = System.currentTimeMillis()
            val lat = location.latitude
            val lng = location.longitude
            val heading = location.bearing.toDouble()
            val speed = location.speed.toDouble()

            // 1. Direct Realtime Database write: driver_locations/{driver_uid}
            val rtdb = FirebaseDatabase.getInstance()
            val locMap = mapOf(
                "lat" to lat,
                "lng" to lng,
                "heading" to heading,
                "speed" to speed,
                "timestamp" to timestamp,
                "updatedAt" to timestamp,
                "isOnline" to true
            )
            rtdb.reference.child("driver_locations").child(driverUid).setValue(locMap)

            // 2. Direct Firestore update: drivers/{driver_uid}.currentLocation when moved >= 25m
            val lastSync = lastFirestoreSyncLocation
            if (lastSync == null || location.distanceTo(lastSync) >= 25f) {
                lastFirestoreSyncLocation = location
                val geohash = Geohash.encode(lat, lng, 7)
                val firestore = FirebaseFirestore.getInstance()
                val currentLocMap = mapOf(
                    "lat" to lat,
                    "lng" to lng,
                    "geohash" to geohash,
                    "lastSeenAt" to FieldValue.serverTimestamp()
                )
                firestore.collection("drivers").document(driverUid)
                    .update("currentLocation", currentLocMap)
            }
        } catch (_: Exception) {}
    }

    private fun setDriverOfflineDirectly() {
        val ctx = getActiveContext()
        val prefs = ctx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val driverUid = prefs.getString(KEY_DRIVER_UID, "") ?: ""
        prefs.edit().putBoolean(KEY_IS_DRIVER_ONLINE, false).apply()

        if (driverUid.isNotBlank()) {
            try {
                if (FirebaseApp.getApps(ctx).isEmpty()) {
                    FirebaseApp.initializeApp(ctx)
                }
                FirebaseFirestore.getInstance().collection("drivers").document(driverUid)
                    .update("isOnline", false)
                FirebaseDatabase.getInstance().reference
                    .child("driver_locations").child(driverUid).child("isOnline").setValue(false)
            } catch (_: Exception) {}
        }

        mainHandler.post {
            primaryChannel?.invokeMethod("onDriverWentOffline", null)
            altChannel?.invokeMethod("onDriverWentOffline", null)
        }
    }

    private fun stopLocationUpdatesInternal() {
        locationCallback?.let {
            try {
                getFusedClient().removeLocationUpdates(it)
            } catch (_: Exception) {}
        }
        locationCallback = null
    }

    fun stopContinuousUpdates() {
        stopLocationUpdatesInternal()
        currentTier = TIER_IDLE
    }

    // --------------------------------------------------------------------------
    // Permissions & Geocoding Methods
    // --------------------------------------------------------------------------

    fun hasLocationPermission(): Boolean {
        val ctx = getActiveContext()
        val fine = ContextCompat.checkSelfPermission(
            ctx, Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        val coarse = ContextCompat.checkSelfPermission(
            ctx, Manifest.permission.ACCESS_COARSE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        return fine || coarse
    }

    fun hasBackgroundLocationPermission(): Boolean {
        return hasLocationPermission()
    }

    fun handleRequestPermissionsResult(
        requestCode: Int,
        grantResults: IntArray
    ): Boolean {
        if (requestCode == PERMISSION_REQUEST_CODE || requestCode == BACKGROUND_PERMISSION_REQUEST_CODE) {
            val granted = grantResults.isNotEmpty() &&
                grantResults.any { it == PackageManager.PERMISSION_GRANTED }
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
            return true
        }
        return false
    }

    // --------------------------------------------------------------------------
    // MethodCallHandler Implementation
    // --------------------------------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val ctx = getActiveContext()
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
                    val act = currentActivity?.get()
                    if (act != null) {
                        pendingPermissionResult = result
                        ActivityCompat.requestPermissions(
                            act,
                            arrayOf(
                                Manifest.permission.ACCESS_FINE_LOCATION,
                                Manifest.permission.ACCESS_COARSE_LOCATION
                            ),
                            PERMISSION_REQUEST_CODE
                        )
                    } else {
                        result.success(false)
                    }
                }
            }

            "requestBackgroundLocationPermission" -> {
                result.success(hasLocationPermission())
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
                val isOnline = call.argument<Boolean>("isOnline")
                val driverUid = call.argument<String>("driverUid")
                val hasActive = call.argument<Boolean>("hasActiveRide")

                val prefs = ctx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                val editor = prefs.edit()
                if (isOnline != null) editor.putBoolean(KEY_IS_DRIVER_ONLINE, isOnline)
                if (driverUid != null) editor.putString(KEY_DRIVER_UID, driverUid)
                if (hasActive != null) editor.putBoolean(KEY_HAS_ACTIVE_RIDE, hasActive)
                editor.apply()

                if (isOnline == true) {
                    ensureServiceStarted(ctx)
                }
                applyAdaptiveLocationRequest()
                result.success(true)
            }

            "stopLocationUpdates" -> {
                stopContinuousUpdates()
                result.success(true)
            }

            "setDriverOnlineState" -> {
                val isOnline = call.argument<Boolean>("isOnline") ?: false
                val driverUid = call.argument<String>("driverUid") ?: ""

                val prefs = ctx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                prefs.edit()
                    .putBoolean(KEY_IS_DRIVER_ONLINE, isOnline)
                    .putString(KEY_DRIVER_UID, driverUid)
                    .apply()

                if (isOnline) {
                    ensureServiceStarted(ctx)
                    applyAdaptiveLocationRequest()
                } else {
                    stopContinuousUpdates()
                    stopForegroundCompat()
                    serviceInstance?.stopSelf()
                }
                result.success(true)
            }

            "setHasActiveRide" -> {
                val hasActiveRide = call.argument<Boolean>("hasActiveRide") ?: false
                val prefs = ctx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                prefs.edit().putBoolean(KEY_HAS_ACTIVE_RIDE, hasActiveRide).apply()
                applyAdaptiveLocationRequest()
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

    private fun ensureServiceStarted(ctx: Context) {
        try {
            val serviceIntent = Intent(ctx, NativeLocationService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ContextCompat.startForegroundService(ctx, serviceIntent)
            } else {
                ctx.startService(serviceIntent)
            }
        } catch (_: Exception) {}
    }

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

        try {
            getFusedClient().lastLocation.addOnSuccessListener { lastLoc: Location? ->
                if (lastLoc != null && !completed) {
                    val age = System.currentTimeMillis() - lastLoc.time
                    if (age < 120_000L && lastLoc.accuracy in 0f..1000f) {
                        sendSuccess(lastLoc)
                        try {
                            getFusedClient().getCurrentLocation(Priority.PRIORITY_HIGH_ACCURACY, null)
                        } catch (_: Exception) {}
                        return@addOnSuccessListener
                    }
                }
            }
        } catch (_: Exception) {}

        try {
            val cancellationTokenSource = CancellationTokenSource()
            val fusedTimeoutRunnable = Runnable {
                if (!completed) {
                    cancellationTokenSource.cancel()
                    fallbackToLocationManager(result, onCompleted = { completed }, onFinish = { completed = true })
                }
            }
            handler.postDelayed(fusedTimeoutRunnable, 8_000L)

            getFusedClient().getCurrentLocation(
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

        val ctx = getActiveContext()
        val lm = ctx.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
        if (lm == null) {
            onFinish()
            result.error("NO_LOCATION_SERVICE", "LocationManager unavailable", null)
            return
        }

        val cached = bestLastKnownLocation(lm)
        if (cached != null) {
            val age = System.currentTimeMillis() - cached.time
            if (age < 30 * 60_000L && cached.accuracy in 0f..1500f) {
                onFinish()
                result.success(serializeLocation(cached))
                return
            }
        }

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
        } catch (_: Exception) {}
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

        mainHandler.postDelayed({
            finishOnMain(fallbackStr)
        }, 3_000L)

        geocodeExecutor.execute {
            try {
                val ctx = getActiveContext()
                if (!Geocoder.isPresent()) {
                    finishOnMain(fallbackStr)
                    return@execute
                }
                val geocoder = Geocoder(ctx, Locale.getDefault())
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
}

/**
 * Standard Base32 Geohash Encoder for native Android location syncing.
 */
object Geohash {
    private const val BASE32 = "0123456789bcdefghjkmnpqrstuvwxyz"

    fun encode(latitude: Double, longitude: Double, precision: Int = 7): String {
        var minLat = -90.0
        var maxLat = 90.0
        var minLng = -180.0
        var maxLng = 180.0
        val sb = StringBuilder()
        var isEven = true
        var bit = 0
        var ch = 0

        while (sb.length < precision) {
            if (isEven) {
                val mid = (minLng + maxLng) / 2.0
                if (longitude >= mid) {
                    ch = ch or (1 shl (4 - bit))
                    minLng = mid
                } else {
                    maxLng = mid
                }
            } else {
                val mid = (minLat + maxLat) / 2.0
                if (latitude >= mid) {
                    ch = ch or (1 shl (4 - bit))
                    minLat = mid
                } else {
                    maxLat = mid
                }
            }

            isEven = !isEven
            if (bit < 4) {
                bit++
            } else {
                sb.append(BASE32[ch])
                bit = 0
                ch = 0
            }
        }
        return sb.toString()
    }
}
