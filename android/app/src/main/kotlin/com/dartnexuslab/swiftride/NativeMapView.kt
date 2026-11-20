package com.dartnexuslab.swiftride

import android.content.Context
import android.graphics.Color
import android.view.View
import android.widget.FrameLayout
import com.google.android.gms.maps.CameraUpdateFactory
import com.google.android.gms.maps.GoogleMap
import com.google.android.gms.maps.MapView
import com.google.android.gms.maps.MapsInitializer
import com.google.android.gms.maps.OnMapReadyCallback
import com.google.android.gms.maps.model.*
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import io.flutter.plugin.common.StandardMessageCodec

class NativeMapViewFactory(private val messenger: BinaryMessenger) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    @Suppress("UNCHECKED_CAST")
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val params = args as? Map<String, Any?>
        return NativeMapView(context, messenger, viewId, params)
    }
}

class NativeMapView(
    context: Context,
    messenger: BinaryMessenger,
    viewId: Int,
    args: Map<String, Any?>?
) : PlatformView, MethodChannel.MethodCallHandler, OnMapReadyCallback {

    private val containerView: FrameLayout = FrameLayout(context)
    private var mapViewInstance: MapView? = null
    private var isDisposed = false
    private val channel: MethodChannel =
        MethodChannel(messenger, "com.swiftride.app/native_map_view_$viewId")

    private var googleMap: GoogleMap? = null
    private val markers = mutableMapOf<String, Marker>()
    private val markerHues = mutableMapOf<String, Float>()
    private val polylines = mutableMapOf<String, Polyline>()

    private val initialLat = (args?.get("initialLat") as? Number)?.toDouble() ?: 31.2785
    private val initialLng = (args?.get("initialLng") as? Number)?.toDouble() ?: 72.3317
    private val initialZoom = (args?.get("initialZoom") as? Number)?.toFloat() ?: 15.0f
    private val isDark = args?.get("darkMode") as? Boolean ?: false
    private val showTraffic = args?.get("showTraffic") as? Boolean ?: true
    private val mapStyleJson = args?.get("mapStyle") as? String

    init {
        channel.setMethodCallHandler(this)
        containerView.setBackgroundColor(if (isDark) Color.parseColor("#0D1321") else Color.parseColor("#E5E9F0"))
        // Defer heavy Google Play Services Chimera Dynamite MapView creation until after
        // Flutter renders Frame 1, avoiding main-thread startup ANRs on budget OEM devices.
        containerView.postDelayed({
            if (!isDisposed) {
                initMapViewAsync(context)
            }
        }, 120L)
    }

    private fun initMapViewAsync(context: Context) {
        if (isDisposed || mapViewInstance != null) return
        try {
            MapsInitializer.initialize(context, MapsInitializer.Renderer.LEGACY) { }
        } catch (_: Exception) {
            try {
                MapsInitializer.initialize(context)
            } catch (_: Exception) {}
        }

        try {
            val mv = MapView(context)
            mv.onCreate(null)
            mv.onStart()
            mv.onResume()
            containerView.addView(
                mv,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT
                )
            )
            mv.getMapAsync(this)
            mapViewInstance = mv
        } catch (e: Exception) {
            android.util.Log.e("NativeMapView", "Failed to initialize MapView: ${e.message}", e)
        }
    }

    override fun getView(): View = containerView

    override fun onMapReady(map: GoogleMap) {
        googleMap = map
        map.uiSettings.isCompassEnabled = false
        map.uiSettings.isMyLocationButtonEnabled = false
        map.uiSettings.isMapToolbarEnabled = false
        map.uiSettings.isZoomControlsEnabled = false
        map.isTrafficEnabled = showTraffic
        map.isBuildingsEnabled = true

        if (!mapStyleJson.isNullOrBlank()) {
            try {
                map.setMapStyle(MapStyleOptions(mapStyleJson))
            } catch (_: Exception) {}
        }

        val initialPos = LatLng(initialLat, initialLng)
        map.moveCamera(CameraUpdateFactory.newLatLngZoom(initialPos, initialZoom))

        map.setOnMapClickListener { latLng ->
            channel.invokeMethod(
                "onMapTap",
                mapOf("latitude" to latLng.latitude, "longitude" to latLng.longitude)
            )
        }

        map.setOnCameraIdleListener {
            val center = map.cameraPosition.target
            val zoom = map.cameraPosition.zoom
            channel.invokeMethod(
                "onCameraIdle",
                mapOf(
                    "latitude" to center.latitude,
                    "longitude" to center.longitude,
                    "zoom" to zoom
                )
            )
        }

        map.setOnCameraMoveListener {
            val center = map.cameraPosition.target
            channel.invokeMethod(
                "onCameraMove",
                mapOf(
                    "latitude" to center.latitude,
                    "longitude" to center.longitude
                )
            )
        }

        channel.invokeMethod("onMapReady", null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val map = googleMap
        when (call.method) {
            "animateCamera" -> {
                val lat = call.argument<Double>("latitude") ?: initialLat
                val lng = call.argument<Double>("longitude") ?: initialLng
                val zoom = (call.argument<Number>("zoom"))?.toFloat()
                val bearing = (call.argument<Number>("bearing"))?.toFloat()
                val tilt = (call.argument<Number>("tilt"))?.toFloat()
                val target = LatLng(lat, lng)

                if (map != null) {
                    val cameraBuilder = com.google.android.gms.maps.model.CameraPosition.builder()
                        .target(target)
                    if (zoom != null) cameraBuilder.zoom(zoom) else cameraBuilder.zoom(map.cameraPosition.zoom)
                    if (bearing != null) cameraBuilder.bearing(bearing)
                    if (tilt != null) cameraBuilder.tilt(tilt)

                    map.animateCamera(CameraUpdateFactory.newCameraPosition(cameraBuilder.build()))
                    result.success(true)
                } else {
                    result.success(false)
                }
            }

            "setMarkers" -> {
                val markerList = call.argument<List<Map<String, Any>>>("markers") ?: emptyList()
                if (map != null) {
                    val incomingIds = mutableSetOf<String>()

                    for (item in markerList) {
                        val id = item["id"] as? String ?: continue
                        val lat = (item["latitude"] as? Number)?.toDouble() ?: continue
                        val lng = (item["longitude"] as? Number)?.toDouble() ?: continue
                        val title = item["title"] as? String
                        val colorHue = (item["hue"] as? Number)?.toFloat() ?: BitmapDescriptorFactory.HUE_RED
                        val rotation = (item["rotation"] as? Number)?.toFloat() ?: 0.0f
                        val newPosition = LatLng(lat, lng)

                        incomingIds.add(id)

                        val existing = markers[id]
                        if (existing != null) {
                            // In-place update to prevent flicker/texture re-allocation
                            if (existing.position != newPosition) {
                                existing.position = newPosition
                            }
                            if (existing.rotation != rotation) {
                                existing.rotation = rotation
                            }
                            if (existing.title != title) {
                                existing.title = title
                            }
                            val prevHue = markerHues[id]
                            if (prevHue != null && prevHue != colorHue) {
                                existing.setIcon(BitmapDescriptorFactory.defaultMarker(colorHue))
                                markerHues[id] = colorHue
                            }
                        } else {
                            val markerOptions = MarkerOptions()
                                .position(newPosition)
                                .title(title)
                                .icon(BitmapDescriptorFactory.defaultMarker(colorHue))
                                .rotation(rotation)
                                .anchor(0.5f, 0.5f)

                            val marker = map.addMarker(markerOptions)
                            if (marker != null) {
                                markers[id] = marker
                                markerHues[id] = colorHue
                            }
                        }
                    }

                    // Remove stale markers not in the new list
                    val staleIds = markers.keys.filter { it !in incomingIds }
                    for (staleId in staleIds) {
                        markers.remove(staleId)?.remove()
                        markerHues.remove(staleId)
                    }

                    result.success(true)
                } else {
                    result.success(false)
                }
            }

            "clearMarkers" -> {
                markers.values.forEach { it.remove() }
                markers.clear()
                markerHues.clear()
                result.success(true)
            }

            "setPolylines" -> {
                val polyList = call.argument<List<Map<String, Any>>>("polylines") ?: emptyList()
                if (map != null) {
                    polylines.values.forEach { it.remove() }
                    polylines.clear()

                    for (item in polyList) {
                        val id = item["id"] as? String ?: continue
                        val pointsRaw = item["points"] as? List<Map<String, Any>> ?: continue
                        val colorInt = (item["color"] as? Number)?.toInt() ?: Color.BLUE
                        val widthFloat = (item["width"] as? Number)?.toFloat() ?: 12f

                        val latLngList = pointsRaw.mapNotNull { pt ->
                            val lat = (pt["latitude"] as? Number)?.toDouble()
                            val lng = (pt["longitude"] as? Number)?.toDouble()
                            if (lat != null && lng != null) LatLng(lat, lng) else null
                        }

                        if (latLngList.isNotEmpty()) {
                            val polyOptions = PolylineOptions()
                                .addAll(latLngList)
                                .color(colorInt)
                                .width(widthFloat)
                                .geodesic(true)

                            val polyline = map.addPolyline(polyOptions)
                            polylines[id] = polyline
                        }
                    }
                    result.success(true)
                } else {
                    result.success(false)
                }
            }

            "setMyLocationEnabled" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                try {
                    map?.isMyLocationEnabled = enabled
                    result.success(true)
                } catch (_: SecurityException) {
                    result.success(false)
                }
            }

            "setTrafficEnabled" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                map?.isTrafficEnabled = enabled
                result.success(true)
            }

            "setMapStyle" -> {
                val style = call.argument<String>("style")
                if (map != null && !style.isNullOrBlank()) {
                    try {
                        map.setMapStyle(MapStyleOptions(style))
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("STYLE_ERROR", e.message, null)
                    }
                } else {
                    result.success(false)
                }
            }

            "onPause" -> {
                try { mapViewInstance?.onPause() } catch (_: Exception) {}
                result.success(true)
            }

            "onResume" -> {
                try { mapViewInstance?.onResume() } catch (_: Exception) {}
                result.success(true)
            }

            "onLowMemory" -> {
                try { mapViewInstance?.onLowMemory() } catch (_: Exception) {}
                result.success(true)
            }

            else -> result.notImplemented()
        }
    }

    override fun dispose() {
        isDisposed = true
        channel.setMethodCallHandler(null)
        try {
            markers.values.forEach { it.remove() }
            markers.clear()
            markerHues.clear()
            polylines.values.forEach { it.remove() }
            polylines.clear()
            containerView.removeAllViews()
            mapViewInstance?.onPause()
            mapViewInstance?.onStop()
            mapViewInstance?.onDestroy()
            mapViewInstance = null
            googleMap = null
        } catch (_: Exception) {}
    }
}
