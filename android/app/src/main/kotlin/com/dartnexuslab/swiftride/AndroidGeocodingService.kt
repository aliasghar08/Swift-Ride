package com.dartnexuslab.swiftride

import android.content.Context
import android.location.Geocoder
import android.os.Handler
import android.os.Looper
import android.util.Log
import kotlinx.coroutines.*
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.Date
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.*

/**
 * Structured geocoded address returned to Flutter and native callers.
 * Mirrors iOS GeocodedAddress 1:1.
 */
data class GeocodedAddress(
    val formattedAddress: String,
    val title: String = "",
    val subtitle: String = "",
    val plotNumber: String = "",
    val street: String = "",
    val neighborhood: String = "",
    val city: String = "",
    val provider: String = "",
    val isGranular: Boolean = false,
    val confidence: Double = 0.0,
    val distanceMeters: Double = 0.0,
    val quarantinedCity: String = ""
) {
    fun toMap(): Map<String, Any> {
        return mapOf(
            "formattedAddress" to formattedAddress,
            "title" to title,
            "subtitle" to subtitle,
            "plotNumber" to plotNumber,
            "street" to street,
            "neighborhood" to neighborhood,
            "city" to city,
            "provider" to provider,
            "isGranular" to isGranular,
            "confidence" to confidence,
            "distanceMeters" to distanceMeters,
            "quarantinedCity" to quarantinedCity
        )
    }

    companion object {
        fun fallback(lat: Double, lng: Double, locality: String = "Jhang"): GeocodedAddress {
            val plusCode = OpenLocationCodeHelper.encodeShort(lat, lng)
            val formatted = "$plusCode, $locality"
            return GeocodedAddress(
                formattedAddress = formatted,
                title = plusCode,
                subtitle = locality,
                city = locality,
                provider = "plus_code",
                isGranular = true,
                confidence = 0.5
            )
        }
    }
}

/** Known Pakistani city centroid for GeoGuard coordinate sanity validation. */
data class CityCentroid(
    val name: String,
    val lat: Double,
    val lng: Double
)

/** Authoritative Macro Ground Truth extracted from official polygons (Layer A). */
data class AuthoritativeArea(
    var city: String = "",
    var neighborhood: String = "",
    var street: String = "",
    var postalCode: String = "",
    var rooftopPlot: String = ""
)

/** Candidate micro-identity from Places or secondary sources (Layer B). */
data class MicroCandidate(
    val placeId: String,
    val displayName: String,
    val plotNumber: String,
    val premise: String,
    val route: String,
    val sublocality: String,
    val rawLocality: String,
    val distanceMeters: Double,
    val lat: Double?,
    val lng: Double?,
    val rawFormatted: String
)

/** Helper for Open Location Code (Plus Code) generation. */
object OpenLocationCodeHelper {
    private val alphabet = "23456789CFGHJMPQRVWX".toCharArray()
    private val pairResolutions = doubleArrayOf(20.0, 1.0, 0.05, 0.0025, 0.000125)

    fun encodeFull(lat: Double, lng: Double): String {
        val clampedLat = min(max(lat, -90.0), 90.0)
        var normalizedLng = lng % 360.0
        if (normalizedLng > 180.0) normalizedLng -= 360.0
        if (normalizedLng < -180.0) normalizedLng += 360.0

        var latVal = clampedLat + 90.0
        var lngVal = normalizedLng + 180.0

        val sb = StringBuilder()
        for (i in pairResolutions.indices) {
            val r = pairResolutions[i]
            val latDigit = min(max(floor(latVal / r).toInt(), 0), 19)
            val lngDigit = min(max(floor(lngVal / r).toInt(), 0), 19)
            sb.append(alphabet[latDigit])
            sb.append(alphabet[lngDigit])
            latVal -= latDigit * r
            lngVal -= lngDigit * r
            if (i == 3) {
                sb.append('+')
            }
        }
        return sb.toString()
    }

    fun encodeShort(lat: Double, lng: Double): String {
        val full = encodeFull(lat, lng)
        return if (full.length >= 8) full.substring(4) else full
    }
}

/**
 * Industry-Grade Native Android Geocoding Service.
 * Mirrors iOS IosGeocodingService 1:1.
 *
 * Implements Two-Layer Authoritative Hierarchical Fusion:
 * - Layer A (Macro): Android OS Geocoder + Google Geocoding REST (ADDRESS_DESCRIPTORS)
 * - Layer B (Micro): Google Places API (New) searchNearby with strict spatial distance gating (<= 40m exact plot)
 * - GeoGuard: Sanitizes user-contributed Place records (>45km city mismatch quarantine, e.g. Sargodha -> Jhang)
 * - 4-Slot Assembly: primary, street, neighborhood, city (zero duplicate tokens or postal codes)
 */
class AndroidGeocodingService private constructor(private val appContext: Context) {

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val mainHandler = Handler(Looper.getMainLooper())

    private val defaultPlacesApiKey = "AIzaSyAph82ESQ7BZkhIoaGm5BFv5wMfP1qOwqE"

    // Major Pakistani city centroids for GeoGuard distance validation (identical to iOS)
    private val pakistanCityCentroids = listOf(
        CityCentroid("Jhang", 31.2681, 72.3181),
        CityCentroid("Sargodha", 32.0836, 72.6711),
        CityCentroid("Faisalabad", 31.4504, 73.1350),
        CityCentroid("Toba Tek Singh", 30.9747, 72.4828),
        CityCentroid("Chiniot", 31.7200, 72.9789),
        CityCentroid("Lahore", 31.5497, 74.3436),
        CityCentroid("Islamabad", 33.6844, 73.0479),
        CityCentroid("Rawalpindi", 33.5651, 73.0169),
        CityCentroid("Multan", 30.1575, 71.5249),
        CityCentroid("Karachi", 24.8607, 67.0011),
        CityCentroid("Gujranwala", 32.1877, 74.1945),
        CityCentroid("Peshawar", 34.0151, 71.5249),
        CityCentroid("Quetta", 30.1798, 66.9750),
        CityCentroid("Sialkot", 32.4945, 74.5229),
        CityCentroid("Bahawalpur", 29.3544, 71.6911),
        CityCentroid("Sukkur", 27.7052, 68.8574),
        CityCentroid("Hyderabad", 25.3960, 68.3578),
        CityCentroid("Sahiwal", 30.6682, 73.1114),
        CityCentroid("Kasur", 31.1179, 74.4461),
        CityCentroid("Sheikhupura", 31.7131, 73.9783)
    )

    // Spatial LRU Cache (~1.1m 5-decimal grid, 15-min TTL)
    private data class CacheEntry(val address: GeocodedAddress, val timestamp: Long)
    private val cache = LinkedHashMap<String, CacheEntry>(16, 0.75f, true)
    private val cacheLock = Any()
    private val maxCacheCapacity = 300
    private val cacheTtlMs = 15L * 60L * 1000L

    // In-flight Deduplication & Pan Cancellation
    private val inFlightTasks = ConcurrentHashMap<String, Deferred<GeocodedAddress>>()
    @Volatile
    private var currentPanJob: Job? = null

    companion object {
        private const val TAG = "AndroidGeocodingService"

        @Volatile
        private var instance: AndroidGeocodingService? = null

        fun initialize(context: Context): AndroidGeocodingService {
            return instance ?: synchronized(this) {
                instance ?: AndroidGeocodingService(context.applicationContext).also { instance = it }
            }
        }

        val shared: AndroidGeocodingService
            get() = instance ?: throw IllegalStateException("AndroidGeocodingService not initialized. Call initialize(context) first.")
    }

    // Resolves Centralized Google Places API Key with places.googleapis.com enabled
    private fun getPlacesApiKey(): String {
        return defaultPlacesApiKey
    }

    // MARK: - Main Geocode Entry Point
    suspend fun reverseGeocode(lat: Double, lng: Double): GeocodedAddress = withContext(Dispatchers.IO) {
        val gridKey = String.format(Locale.US, "%.5f,%.5f", lat, lng)

        getFromCache(gridKey)?.let { cached ->
            Log.d(TAG, "[Cache Hit] Grid $gridKey -> ${cached.formattedAddress}")
            return@withContext cached
        }

        inFlightTasks[gridKey]?.let { ongoing ->
            Log.d(TAG, "[Deduplication] Sharing in-flight request for $gridKey")
            return@withContext ongoing.await()
        }

        val deferred = async(Dispatchers.IO) {
            executeTwoLayerFusion(lat, lng)
        }
        inFlightTasks[gridKey] = deferred

        try {
            val result = deferred.await()
            if (result.isGranular) {
                saveToCache(gridKey, result)
            }
            result
        } finally {
            inFlightTasks.remove(gridKey)
        }
    }

    suspend fun reverseGeocodeDetailed(lat: Double, lng: Double): GeocodedAddress {
        return reverseGeocode(lat, lng)
    }

    suspend fun panReverseGeocode(lat: Double, lng: Double): GeocodedAddress = withContext(Dispatchers.IO) {
        currentPanJob?.cancel()
        val deferred = async(Dispatchers.IO) {
            reverseGeocode(lat, lng)
        }
        currentPanJob = deferred
        deferred.await()
    }

    fun cancelPendingGeocode() {
        currentPanJob?.cancel()
        currentPanJob = null
    }

    // MARK: - Two-Layer Authoritative Hierarchical Fusion Engine
    private suspend fun executeTwoLayerFusion(lat: Double, lng: Double): GeocodedAddress = coroutineScope {
        val startTime = System.currentTimeMillis()
        val apiKey = getPlacesApiKey()

        Log.d(TAG, "Two-Layer Fusion started for coordinates: ($lat, $lng)")

        // -------------------------------------------------------------
        // STAGE 1: Parallel Fetch of Layer A (Macro) & Layer B (Micro)
        // -------------------------------------------------------------
        val osTask = async(Dispatchers.IO) { fetchAndroidOsMacro(lat, lng) }
        val restTask = async(Dispatchers.IO) { fetchGeocodingRestMacro(lat, lng, apiKey) }
        val placesTask = async(Dispatchers.IO) { fetchPlacesMicroCandidates(lat, lng, apiKey) }

        val macroOs = osTask.await()
        val macroRest = restTask.await()
        val microCandidates = placesTask.await()

        // Combine Layer A sources (OS Geocoder + Geocoding REST)
        // Prefer official Geocoding REST street & rooftop (which extracts "Green Belt", "Usmania Road", "Plot 763 A")
        val cityCandidate = when {
            macroOs.city.isNotEmpty() && !macroOs.city.equals("Jhang", ignoreCase = true) -> macroOs.city
            macroRest.city.isNotEmpty() -> macroRest.city
            macroOs.city.isNotEmpty() -> macroOs.city
            else -> "Jhang"
        }

        val macroStreet = when {
            macroRest.street.isNotEmpty() && !macroRest.street.equals("block", ignoreCase = true) -> macroRest.street
            macroOs.street.isNotEmpty() && !macroOs.street.equals("block", ignoreCase = true) -> macroOs.street
            else -> ""
        }

        val macroNeighborhood = when {
            macroRest.neighborhood.isNotEmpty() -> macroRest.neighborhood
            macroOs.neighborhood.isNotEmpty() -> macroOs.neighborhood
            else -> ""
        }

        val macroRooftop = when {
            macroRest.rooftopPlot.isNotEmpty() -> macroRest.rooftopPlot
            macroOs.rooftopPlot.isNotEmpty() -> macroOs.rooftopPlot
            else -> ""
        }

        val macroArea = AuthoritativeArea(
            city = cityCandidate,
            neighborhood = macroNeighborhood,
            street = macroStreet,
            postalCode = if (macroRest.postalCode.isNotEmpty()) macroRest.postalCode else macroOs.postalCode,
            rooftopPlot = macroRooftop
        )

        // -------------------------------------------------------------
        // STAGE 2: Authoritative Macro Resolution (GeoGuard City Lock)
        // -------------------------------------------------------------
        val authoritativeCity = validateCityWithGeoGuard(lat, lng, macroArea.city).second
        macroArea.city = authoritativeCity

        // Clean redundant sublocality repetitions
        macroArea.neighborhood = cleanSublocalityRepetitions(macroArea.neighborhood)

        // Check microCandidates for block/phase if macroArea.neighborhood is missing it
        val hasBlockOrPhase = Regex("""\b(?:Block\s+[A-Za-z0-9]+|[A-Za-z0-9]+-Block|Phase\s+[0-9]+)\b""", RegexOption.IGNORE_CASE).containsMatchIn(macroArea.neighborhood)
        if (!hasBlockOrPhase) {
            for (cand in microCandidates) {
                val match = Regex("""\b(?:Block\s+[A-Za-z0-9]+|[A-Za-z0-9]+-Block|Phase\s+[0-9]+)\b""", RegexOption.IGNORE_CASE).find(cand.rawFormatted)
                if (match != null) {
                    macroArea.neighborhood = cleanSublocalityRepetitions("${macroArea.neighborhood} ${match.value}")
                    break
                }
            }
        }

        // If macro route is empty, enrich via Google Roads API (nearestRoads)
        if (macroArea.street.isEmpty()) {
            val snappedRoad = snapToNearestRoad(lat, lng, apiKey)
            if (!snappedRoad.isNullOrEmpty()) {
                macroArea.street = snappedRoad
                Log.d(TAG, "[Roads] Enriched road name: '$snappedRoad'")
            }
        }

        Log.d(TAG, "[AuthoritativeArea] Locked macro: city='${macroArea.city}', neighborhood='${macroArea.neighborhood}', street='${macroArea.street}'")

        // -------------------------------------------------------------
        // STAGE 3: Strict Spatial Gating & City Quarantine for Micro POIs
        // -------------------------------------------------------------
        var bestMicro: MicroCandidate? = null
        var quarantinedCityName = ""

        for (candidate in microCandidates) {
            // Guard: Spatial distance gate
            if (candidate.distanceMeters > 150.0) {
                continue
            }

            // Guard: City mismatch quarantine
            val (_, validatedCandidateCity) = validateCityWithGeoGuard(lat, lng, candidate.rawLocality)
            if (!validatedCandidateCity.equals(macroArea.city, ignoreCase = true)) {
                Log.d(TAG, "[GeoGuard] Quarantined dirty place city '${candidate.rawLocality}' on '${candidate.displayName}' -> enforced authoritative '${macroArea.city}'")
                quarantinedCityName = candidate.rawLocality
            }

            // Pick the closest valid micro property
            val currentBest = bestMicro
            if (currentBest == null || candidate.distanceMeters < currentBest.distanceMeters) {
                bestMicro = candidate
            }
        }

        // -------------------------------------------------------------
        // STAGE 4: Structured Slot Assembly (Zero Garbage Formatting)
        // -------------------------------------------------------------
        // Slot 1: Primary Micro-Identity (Priority 1: Rooftop Plot)
        var primary = ""
        var distanceToWinner = 0.0

        if (macroArea.rooftopPlot.isNotEmpty()) {
            primary = cleanPlotString(macroArea.rooftopPlot)
            distanceToWinner = 0.0
            Log.d(TAG, "Priority 1 Rooftop winner: '$primary'")
        } else if (bestMicro != null) {
            val micro = bestMicro
            distanceToWinner = micro.distanceMeters
            if (micro.distanceMeters <= 35.0) {
                // Tier 1: Exact plot/property residency (e.g. "Plot 755", "Plot 757")
                val plotClean = cleanPlotString(micro.plotNumber)
                if (plotClean.isNotEmpty()) {
                    primary = plotClean
                } else if (micro.displayName.isNotEmpty() && !isGenericGarbageToken(micro.displayName)) {
                    primary = micro.displayName
                }
            } else if (micro.distanceMeters <= 100.0) {
                // Tier 2: Neighboring plot/establishment — prefix "Near"
                val plotClean = cleanPlotString(micro.plotNumber)
                val name = if (plotClean.isNotEmpty()) plotClean else micro.displayName
                if (name.isNotEmpty() && !isGenericGarbageToken(name)) {
                    primary = "Near $name"
                }
            }
        }

        // Fallback primary to macro rooftop plot if micro was distant or absent
        if (primary.isEmpty() && macroArea.rooftopPlot.isNotEmpty()) {
            primary = cleanPlotString(macroArea.rooftopPlot)
        }

        // Fallback primary to street or landmark
        if (primary.isEmpty()) {
            primary = when {
                macroArea.street.isNotEmpty() -> macroArea.street
                macroArea.neighborhood.isNotEmpty() -> macroArea.neighborhood
                else -> macroArea.city
            }
        }

        // Slot 2: Verified Street (omitted if already inside primary or generic garbage)
        var street = if (macroArea.street.isNotEmpty() && !macroArea.street.equals("block", ignoreCase = true)) {
            macroArea.street
        } else {
            bestMicro?.route ?: ""
        }
        if (street.equals("block", ignoreCase = true) || isNormalizedSubstring(street, primary)) {
            street = ""
        } else if (primary.isNotEmpty() && (Regex("^(?:plot|house|flat|unit)\\s+\\d+", RegexOption.IGNORE_CASE).containsMatchIn(primary) || Regex("^\\d+").containsMatchIn(primary))) {
            // When primary already holds a rooftop plot/house number, strip any leading numeric house prefix from street slot (e.g. "416 Usmania Road" -> "Usmania Road")
            street = street.replaceFirst(Regex("^\\d+[A-Za-z]?(?:[/-]\\d+[A-Za-z]?)?[\\s,-]+"), "").trim()
            if (isNormalizedSubstring(street, primary)) {
                street = ""
            }
        }

        // Slot 3: Verified Neighborhood (omitted if already in primary or street)
        var neighborhood = if (macroArea.neighborhood.isNotEmpty()) macroArea.neighborhood else (bestMicro?.sublocality ?: "")
        neighborhood = cleanSublocalityRepetitions(neighborhood)
        if (isNormalizedSubstring(neighborhood, primary) || isNormalizedSubstring(neighborhood, street)) {
            neighborhood = ""
        }

        // Slot 4: Authoritative City (Strictly locked to Layer A ground truth)
        val city = macroArea.city

        // Assemble clean deduplicated slots
        val slots = mutableListOf<String>()
        val titlePrimary = toTitleCase(primary)
        if (titlePrimary.isNotEmpty()) slots.add(titlePrimary)

        val titleStreet = toTitleCase(street)
        if (titleStreet.isNotEmpty() && slots.none { it.equals(titleStreet, ignoreCase = true) } && !primary.contains(titleStreet, ignoreCase = true)) {
            slots.add(titleStreet)
        }

        val titleNeighborhood = toTitleCase(neighborhood)
        if (titleNeighborhood.isNotEmpty() && slots.none { it.equals(titleNeighborhood, ignoreCase = true) } && !primary.contains(titleNeighborhood, ignoreCase = true)) {
            slots.add(titleNeighborhood)
        }

        val titleCity = toTitleCase(city)
        if (titleCity.isNotEmpty() && slots.none { it.equals(titleCity, ignoreCase = true) }) {
            slots.add(titleCity)
        }

        val fullFormatted = slots.joinToString(", ")
        val subtitleSlots = slots.filter { it != titlePrimary }
        val subtitle = subtitleSlots.joinToString(", ")

        val latencyMs = System.currentTimeMillis() - startTime
        val providerName = when {
            macroArea.rooftopPlot.isNotEmpty() && primary == cleanPlotString(macroArea.rooftopPlot) -> "geocoding_rest_rooftop_fused"
            bestMicro != null && bestMicro.distanceMeters <= 35.0 -> "places_nearby_fused"
            bestMicro != null && bestMicro.distanceMeters <= 100.0 -> "places_nearby_near_fused"
            else -> "macro_authoritative_fused"
        }

        Log.d(TAG, "Winner provider: [$providerName] in ${latencyMs}ms: '$fullFormatted' (dist: ${String.format(Locale.US, "%.1f", distanceToWinner)}m)")

        GeocodedAddress(
            formattedAddress = fullFormatted,
            title = titlePrimary,
            subtitle = subtitle,
            plotNumber = cleanPlotNumberOnly(titlePrimary),
            street = if (titleStreet.isEmpty()) macroArea.street else titleStreet,
            neighborhood = if (titleNeighborhood.isEmpty()) macroArea.neighborhood else titleNeighborhood,
            city = titleCity,
            provider = providerName,
            isGranular = true,
            confidence = if (bestMicro != null && bestMicro.distanceMeters <= 35.0) 0.95 else 0.85,
            distanceMeters = distanceToWinner,
            quarantinedCity = quarantinedCityName
        )
    }

    // MARK: - Layer A: Android OS Geocoder Macro Fetch
    private fun fetchAndroidOsMacro(lat: Double, lng: Double): AuthoritativeArea {
        if (!Geocoder.isPresent()) {
            return AuthoritativeArea(city = "Jhang")
        }
        return try {
            val geocoder = Geocoder(appContext, Locale.ENGLISH)
            @Suppress("DEPRECATION")
            val addresses = geocoder.getFromLocation(lat, lng, 5)
            if (addresses.isNullOrEmpty()) {
                return AuthoritativeArea(city = "Jhang")
            }

            var city = ""
            var neighborhood = ""
            var street = ""
            var postal = ""
            var rooftop = ""

            for (addr in addresses) {
                if (city.isEmpty() && !addr.locality.isNullOrBlank()) {
                    city = addr.locality.trim()
                }
                if (neighborhood.isEmpty() && !addr.subLocality.isNullOrBlank()) {
                    neighborhood = addr.subLocality.trim()
                }
                if (street.isEmpty() && !addr.thoroughfare.isNullOrBlank()) {
                    street = addr.thoroughfare.trim()
                }
                if (postal.isEmpty() && !addr.postalCode.isNullOrBlank()) {
                    postal = addr.postalCode.trim()
                }

                // Check address line for rooftop plot without prepending duplicate subThoroughfare
                val maxLine = addr.maxAddressLineIndex
                for (i in 0..maxLine) {
                    val line = addr.getAddressLine(i) ?: continue
                    val cleaned = cleanGmsSingleLine(line)
                    val match = Regex("""(?:Plot|House|Flat|Unit|#)?\s*\b(?!35200|40100)\d{1,4}[A-Za-z]?\b""", RegexOption.IGNORE_CASE).find(cleaned)
                    if (rooftop.isEmpty() && match != null) {
                        rooftop = match.value.trim()
                    }
                }
            }

            AuthoritativeArea(
                city = if (city.isNotEmpty()) city else "Jhang",
                neighborhood = neighborhood,
                street = street,
                postalCode = postal,
                rooftopPlot = rooftop
            )
        } catch (e: Exception) {
            Log.w(TAG, "[OS Geocoder] Macro error: ${e.message}")
            AuthoritativeArea(city = "Jhang")
        }
    }

    // MARK: - Layer A2: Google Geocoding REST Macro Fetch
    private fun fetchGeocodingRestMacro(lat: Double, lng: Double, apiKey: String): AuthoritativeArea {
        val urlStr = "https://maps.googleapis.com/maps/api/geocode/json?latlng=$lat,$lng&language=en&extra_computations=ADDRESS_DESCRIPTORS&key=$apiKey"
        val (code, resp) = httpGet(urlStr)
        if (code != 200 || resp.isNullOrBlank()) {
            return AuthoritativeArea()
        }

        return try {
            val json = JSONObject(resp)
            val results = json.optJSONArray("results") ?: return AuthoritativeArea()
            if (results.length() == 0) return AuthoritativeArea()

            var city = ""
            var subloc1 = ""
            var subloc2 = ""
            var street = ""
            var postal = ""
            var rooftop = ""
            var blockToken = ""

            for (i in 0 until results.length()) {
                val r = results.getJSONObject(i)
                val formatted = r.optString("formatted_address", "")
                if (blockToken.isEmpty()) {
                    val match = Regex("""\b(?:Block\s+[A-Za-z0-9]+|[A-Za-z0-9]+-Block|Phase\s+[0-9]+)\b""", RegexOption.IGNORE_CASE).find(formatted)
                    if (match != null) blockToken = match.value
                }

                val comps = r.optJSONArray("address_components") ?: continue
                for (j in 0 until comps.length()) {
                    val comp = comps.getJSONObject(j)
                    val types = jsonArrayToStringList(comp.optJSONArray("types"))
                    val name = comp.optString("long_name", comp.optString("short_name", "")).trim()

                    if (city.isEmpty() && (types.contains("locality") || types.contains("administrative_area_level_2"))) {
                        city = name
                    }
                    if (subloc1.isEmpty() && (types.contains("sublocality_level_1") || types.contains("neighborhood") || types.contains("sublocality"))) {
                        subloc1 = name
                    }
                    if (subloc2.isEmpty() && types.contains("sublocality_level_2")) {
                        subloc2 = name
                    }
                    if (street.isEmpty() && types.contains("route") && !name.equals("block", ignoreCase = true)) {
                        street = name
                    }
                    if (postal.isEmpty() && types.contains("postal_code")) {
                        postal = name
                    }
                    if (rooftop.isEmpty() && (types.contains("street_number") || types.contains("premise"))) {
                        if (!name.equals("block", ignoreCase = true) && !name.equals("35200") && !name.equals("40100")) {
                            rooftop = name
                        }
                    }
                }
            }

            var combinedNeighborhood = subloc1
            if (subloc2.isNotEmpty()) {
                combinedNeighborhood = if (combinedNeighborhood.isEmpty()) {
                    subloc2
                } else if (!combinedNeighborhood.contains(subloc2, ignoreCase = true)) {
                    "$combinedNeighborhood $subloc2"
                } else {
                    combinedNeighborhood
                }
            } else if (blockToken.isNotEmpty()) {
                combinedNeighborhood = if (combinedNeighborhood.isEmpty()) {
                    blockToken
                } else if (!combinedNeighborhood.contains(blockToken, ignoreCase = true)) {
                    "$combinedNeighborhood $blockToken"
                } else {
                    combinedNeighborhood
                }
            }

            AuthoritativeArea(
                city = city,
                neighborhood = cleanSublocalityRepetitions(combinedNeighborhood),
                street = street,
                postalCode = postal,
                rooftopPlot = rooftop
            )
        } catch (e: Exception) {
            Log.w(TAG, "[GeocodingREST] Macro error: ${e.message}")
            AuthoritativeArea()
        }
    }

    // MARK: - Layer B: Google Places API New Micro Fetch
    private suspend fun fetchPlacesMicroCandidates(lat: Double, lng: Double, apiKey: String): List<MicroCandidate> {
        val candidates250 = queryPlacesNearbyRadius(lat, lng, 250.0, apiKey)
        if (candidates250.isNotEmpty()) {
            return candidates250
        }
        return queryPlacesNearbyRadius(lat, lng, 500.0, apiKey)
    }

    private fun queryPlacesNearbyRadius(lat: Double, lng: Double, radius: Double, apiKey: String): List<MicroCandidate> {
        val urlStr = "https://places.googleapis.com/v1/places:searchNearby"
        val bodyJson = JSONObject().apply {
            put("locationRestriction", JSONObject().apply {
                put("circle", JSONObject().apply {
                    put("center", JSONObject().apply {
                        put("latitude", lat)
                        put("longitude", lng)
                    })
                    put("radius", radius)
                })
            })
            put("rankPreference", "DISTANCE")
            put("maxResultCount", 8)
        }

        val headers = mapOf(
            "X-Goog-Api-Key" to apiKey,
            "X-Goog-FieldMask" to "places.id,places.displayName,places.formattedAddress,places.addressComponents,places.location,places.types"
        )

        val (code, resp) = httpPostJson(urlStr, bodyJson.toString(), headers)
        if (code != 200 || resp.isNullOrBlank()) {
            Log.w(TAG, "[PlacesNearby] Radius ${radius}m returned HTTP $code: ${resp?.take(120)}")
            return emptyList()
        }

        return try {
            val json = JSONObject(resp)
            val places = json.optJSONArray("places") ?: return emptyList()
            Log.d(TAG, "[PlacesNearby] Radius ${radius}m: HTTP 200 OK, found ${places.length()} places")

            val results = mutableListOf<MicroCandidate>()
            for (i in 0 until places.length()) {
                val p = places.getJSONObject(i)
                parseMicroCandidate(p, lat, lng)?.let { candidate ->
                    results.add(candidate)
                    Log.d(TAG, "[PlacesNearby]   - '${candidate.displayName}' [plot: '${candidate.plotNumber}'] at ${String.format(Locale.US, "%.1f", candidate.distanceMeters)}m")
                }
            }
            results
        } catch (e: Exception) {
            Log.w(TAG, "[PlacesNearby] Parsing error: ${e.message}")
            emptyList()
        }
    }

    private fun parseMicroCandidate(place: JSONObject, userLat: Double, userLng: Double): MicroCandidate? {
        val placeId = place.optString("id", "")
        val displayName = place.optJSONObject("displayName")?.optString("text", "") ?: ""
        val formatted = place.optString("formattedAddress", "")

        var streetNumber = ""
        var subpremise = ""
        var premise = ""
        var route = ""
        var subloc1 = ""
        var subloc2 = ""
        var locality = ""
        var admin2 = ""

        val components = place.optJSONArray("addressComponents")
        if (components != null) {
            for (i in 0 until components.length()) {
                val comp = components.getJSONObject(i)
                val types = jsonArrayToStringList(comp.optJSONArray("types"))
                val name = comp.optString("longText", comp.optString("shortText", "")).trim()

                when {
                    types.contains("street_number") && streetNumber.isEmpty() -> streetNumber = name
                    types.contains("subpremise") && subpremise.isEmpty() -> subpremise = name
                    types.contains("premise") && premise.isEmpty() -> premise = name
                    types.contains("route") && route.isEmpty() -> route = name
                    (types.contains("sublocality_level_1") || types.contains("neighborhood")) && subloc1.isEmpty() -> subloc1 = name
                    types.contains("sublocality_level_2") && subloc2.isEmpty() -> subloc2 = name
                    types.contains("locality") && locality.isEmpty() -> locality = name
                    types.contains("administrative_area_level_2") && admin2.isEmpty() -> admin2 = name
                }
            }
        }

        var combinedNeighborhood = subloc1
        if (subloc2.isNotEmpty()) {
            combinedNeighborhood = if (combinedNeighborhood.isEmpty()) {
                subloc2
            } else if (!combinedNeighborhood.contains(subloc2, ignoreCase = true)) {
                "$combinedNeighborhood $subloc2"
            } else {
                combinedNeighborhood
            }
        }

        // If components have premise (e.g. premise: "755", subpremise: "H")
        var plot = ""
        if (streetNumber.isNotEmpty()) {
            plot = streetNumber
        } else if (premise.isNotEmpty() && premise.matches(Regex("""^\d+[A-Za-z]?$"""))) {
            plot = if (subpremise.isNotEmpty()) "$premise $subpremise" else premise
        }

        // If displayName contains plot (e.g. "Plot 741 A", "Plot 602 A", "Plot 757 A")
        if (plot.isEmpty()) {
            val match = Regex("""(?:Plot|House|H|Unit)\s*#?\s*([0-9]+[A-Za-z]?)""", RegexOption.IGNORE_CASE).find(displayName)
            if (match != null) {
                plot = match.value.trim()
            }
        }

        var pLat: Double? = null
        var pLng: Double? = null
        var dist = 9999.0
        val loc = place.optJSONObject("location")
        if (loc != null) {
            pLat = loc.optDouble("latitude")
            pLng = loc.optDouble("longitude")
            dist = haversineDistance(userLat, userLng, pLat, pLng)
        }

        return MicroCandidate(
            placeId = placeId,
            displayName = displayName,
            plotNumber = plot,
            premise = premise,
            route = route,
            sublocality = combinedNeighborhood,
            rawLocality = if (locality.isNotEmpty()) locality else admin2,
            distanceMeters = dist,
            lat = pLat,
            lng = pLng,
            rawFormatted = formatted
        )
    }

    // MARK: - GeoGuard Coordinate-to-City Distance Validator
    fun validateCityWithGeoGuard(lat: Double, lng: Double, candidateCity: String): Pair<Boolean, String> {
        val trimmed = candidateCity.trim()
        val nearest = findNearestCityCentroid(lat, lng)

        if (trimmed.isEmpty() || trimmed.equals("naya shehar", ignoreCase = true)) {
            return Pair(false, nearest.name)
        }

        for (c in pakistanCityCentroids) {
            if (c.name.equals(trimmed, ignoreCase = true)) {
                val distKm = haversineDistance(lat, lng, c.lat, c.lng) / 1000.0
                return if (distKm > 45.0) {
                    Pair(false, nearest.name)
                } else {
                    Pair(true, c.name)
                }
            }
        }

        return Pair(true, trimmed)
    }

    private fun findNearestCityCentroid(lat: Double, lng: Double): CityCentroid {
        var best = pakistanCityCentroids[0]
        var minDist = Double.MAX_VALUE
        for (c in pakistanCityCentroids) {
            val d = haversineDistance(lat, lng, c.lat, c.lng)
            if (d < minDist) {
                minDist = d
                best = c
            }
        }
        return best
    }

    private fun haversineDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val r = 6371000.0 // Earth radius in meters
        val dLat = Math.toRadians(lat2 - lat1)
        val dLon = Math.toRadians(lon2 - lon1)
        val a = sin(dLat / 2.0).pow(2.0) +
                cos(Math.toRadians(lat1)) * cos(Math.toRadians(lat2)) *
                sin(dLon / 2.0).pow(2.0)
        val c = 2.0 * atan2(sqrt(a), sqrt(1.0 - a))
        return r * c
    }

    // MARK: - Roads API: Curb-Snap Off-Road Pins to Nearest Road
    private fun snapToNearestRoad(lat: Double, lng: Double, apiKey: String): String? {
        val urlStr = "https://roads.googleapis.com/v1/nearestRoads?points=$lat,$lng&key=$apiKey"
        val (code, resp) = httpGet(urlStr)
        if (code != 200 || resp.isNullOrBlank()) {
            return null
        }
        return try {
            val json = JSONObject(resp)
            val points = json.optJSONArray("snappedPoints") ?: return null
            if (points.length() == 0) return null
            val first = points.getJSONObject(0)
            val placeId = first.optString("placeId", "")
            if (placeId.isNotEmpty()) {
                fetchRoadNameFromPlaceId(placeId, apiKey)
            } else {
                null
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun fetchRoadNameFromPlaceId(placeId: String, apiKey: String): String {
        val urlStr = "https://maps.googleapis.com/maps/api/geocode/json?place_id=$placeId&key=$apiKey"
        val (code, resp) = httpGet(urlStr)
        if (code != 200 || resp.isNullOrBlank()) return ""
        return try {
            val json = JSONObject(resp)
            val results = json.optJSONArray("results") ?: return ""
            if (results.length() == 0) return ""
            val first = results.getJSONObject(0)
            val comps = first.optJSONArray("address_components") ?: return ""
            for (i in 0 until comps.length()) {
                val comp = comps.getJSONObject(i)
                val types = jsonArrayToStringList(comp.optJSONArray("types"))
                if (types.contains("route")) {
                    return comp.optString("long_name", comp.optString("short_name", "")).trim()
                }
            }
            ""
        } catch (_: Exception) {
            ""
        }
    }

    // MARK: - Clean Formatting Helpers
    fun toTitleCase(str: String): String {
        if (str.isEmpty()) return str
        val words = str.split(" ")
        return words.joinToString(" ") { word ->
            if (word.isEmpty()) return@joinToString word
            if (word == word.uppercase(Locale.US) && word.length <= 4) {
                return@joinToString word
            }
            if (word.contains("-")) {
                return@joinToString word.split("-").joinToString("-") { toTitleCase(it) }
            }
            word.substring(0, 1).uppercase(Locale.US) + word.substring(1).lowercase(Locale.US)
        }
    }

    fun cleanPlotString(raw: String): String {
        val trimmed = raw.trim()
        if (trimmed.isEmpty() || trimmed == "35200" || trimmed == "40100" || trimmed.equals("block", ignoreCase = true)) {
            return ""
        }
        val lower = trimmed.lowercase(Locale.US)
        if (lower.startsWith("plot ") || lower.startsWith("house ") || lower.startsWith("flat ") || lower.startsWith("unit ")) {
            return trimmed
        }
        if (trimmed.matches(Regex("""^\d+\s*[A-Za-z]?$"""))) {
            return "Plot $trimmed"
        }
        return trimmed
    }

    fun cleanPlotNumberOnly(primary: String): String {
        val match = Regex("""\b\d{1,4}\s*[A-Za-z]?\b""").find(primary)
        return match?.value?.trim() ?: ""
    }

    fun cleanSublocalityRepetitions(raw: String): String {
        var s = raw.replace("Satellite Town Block A Satellite Town", "Satellite Town Block A")
            .replace("Satellite Block A Town", "Satellite Town Block A")
        val words = s.split(" ").filter { it.isNotEmpty() }
        if (words.size >= 4) {
            for (wlen in 2..(words.size / 2)) {
                val prefix = words.take(wlen).joinToString(" ")
                if (s.endsWith(" $prefix")) {
                    s = s.substring(0, s.length - (prefix.length + 1)).trimEnd(' ', ',')
                    break
                }
            }
        }
        return s.trim()
    }

    private fun cleanGmsSingleLine(line: String): String {
        var s = line.replace(Regex("""\b\d{5}\b"""), "")
        s = s.replace(Regex("""\bPakistan\b""", RegexOption.IGNORE_CASE), "")
        s = s.replace(Regex("""\bNaya Shehar\b""", RegexOption.IGNORE_CASE), "")
        s = s.replace(Regex("""[\s,]+"""), " ").trim(' ', ',')
        return cleanSublocalityRepetitions(s)
    }

    private fun isNormalizedSubstring(candidate: String, container: String): Boolean {
        if (candidate.isEmpty() || container.isEmpty()) return false
        val c1 = candidate.lowercase(Locale.US).replace("road", "rd").replace("street", "st")
        val c2 = container.lowercase(Locale.US).replace("road", "rd").replace("street", "st")
        return c2.contains(c1)
    }

    private fun isGenericGarbageToken(name: String): Boolean {
        val lower = name.lowercase(Locale.US).trim()
        return lower.isEmpty() || lower == "block" || lower == "h" || lower == "35200" || lower == "40100" || lower == "pakistan" || lower == "naya shehar"
    }

    // MARK: - Granularity Check
    fun isGranularAddress(address: String): Boolean {
        val trimmed = address.trim()
        if (trimmed.isEmpty() || trimmed.startsWith("Location (") || trimmed.startsWith("Pinned Spot")) {
            return false
        }

        val hasPlusCode = Regex("""\b[A-Za-z0-9]{4,8}\+[A-Za-z0-9]{2,5}\b""").containsMatchIn(trimmed)
        val withoutPlusCode = trimmed.replace(Regex("""\b[A-Za-z0-9]{4,8}\+[A-Za-z0-9]{2,5}\b"""), "").trim()

        val broadCities = listOf(
            "jhang", "central jhang", "jhang sadar", "jhang city", "lahore",
            "faisalabad", "karachi", "islamabad", "rawalpindi", "multan",
            "peshawar", "quetta", "sialkot", "gujranwala", "sargodha", "toba tek singh"
        )
        val lower = withoutPlusCode.lowercase(Locale.US)
        if (broadCities.contains(lower)) {
            return hasPlusCode
        }

        val pattern = """\b(plot|house|shop|flat|apt|apartment|suite|floor|unit|plaza|tower|center|centre|complex|arcade|heights|residency|villa|manzil|cottage|chambers|hospital|clinic|pharmacy|university|college|school|academy|institute|masjid|mosque|church|temple|market|bazaar|mall|mart|store|bank|hotel|restaurant|cafe|bakery|station|terminal|stop|park|stadium|club|gym|court|office|street|st|road|rd|avenue|ave|lane|ln|boulevard|blvd|chowk|bazar|gali|kucha|mohalla|mohallah|block|sector|phase|scheme|police|lines|cantonment|cantt|sadar|saddar|hall|markaz|branch|gate|pul|bridge|stand|adda|basti|kot|deh|chak|mouza|moza|deri|dhok|tehsil|headworks|patrolling|barracks|near|opposite|behind|beside)\b"""
        if (Regex(pattern, RegexOption.IGNORE_CASE).containsMatchIn(withoutPlusCode)) {
            return true
        }

        if (Regex("""(?:^|[,\s#/-])\d+[A-Za-z]?(?:\b|$)""").containsMatchIn(withoutPlusCode)) {
            return true
        }

        val segments = withoutPlusCode.split(",").map { it.trim() }.filter { it.isNotEmpty() }
        val nonAdmin = segments.filter { seg ->
            val s = seg.lowercase(Locale.US)
            if (s == "pakistan" || s == "pk") return@filter false
            if (s == "punjab" || s == "sindh" || s == "kpk" || s == "khyber pakhtunkhwa" || s == "balochistan" || s == "islamabad capital territory") return@filter false
            if (broadCities.contains(s)) return@filter false
            if (s.startsWith("central ") && broadCities.contains(s.removePrefix("central "))) return@filter false
            true
        }

        return nonAdmin.size >= 2 || hasPlusCode
    }

    // MARK: - Spatial LRU Cache Management
    private fun getFromCache(key: String): GeocodedAddress? = synchronized(cacheLock) {
        val entry = cache[key] ?: return null
        if (System.currentTimeMillis() - entry.timestamp > cacheTtlMs) {
            cache.remove(key)
            return null
        }
        return entry.address
    }

    private fun saveToCache(key: String, address: GeocodedAddress) {
        synchronized(cacheLock) {
            if (!address.isGranular || !isGranularAddress(address.formattedAddress)) return
            while (cache.size >= maxCacheCapacity) {
                val oldest = cache.keys.firstOrNull() ?: break
                cache.remove(oldest)
            }
            cache[key] = CacheEntry(address, System.currentTimeMillis())
        }
    }

    // MARK: - HTTP Network Helpers
    private fun httpGet(urlStr: String, headers: Map<String, String> = emptyMap(), timeoutMs: Int = 3500): Pair<Int, String?> {
        var conn: HttpURLConnection? = null
        return try {
            val url = URL(urlStr)
            conn = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                connectTimeout = timeoutMs
                readTimeout = timeoutMs
                for ((k, v) in headers) {
                    setRequestProperty(k, v)
                }
            }
            val code = conn.responseCode
            val stream = if (code in 200..299) conn.inputStream else conn.errorStream
            val resp = stream?.bufferedReader()?.use { it.readText() }
            Pair(code, resp)
        } catch (_: Exception) {
            Pair(-1, null)
        } finally {
            conn?.disconnect()
        }
    }

    private fun httpPostJson(urlStr: String, jsonBody: String, headers: Map<String, String> = emptyMap(), timeoutMs: Int = 3500): Pair<Int, String?> {
        var conn: HttpURLConnection? = null
        return try {
            val url = URL(urlStr)
            conn = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = timeoutMs
                readTimeout = timeoutMs
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
                for ((k, v) in headers) {
                    setRequestProperty(k, v)
                }
            }
            conn.outputStream.use { os ->
                os.write(jsonBody.toByteArray(Charsets.UTF_8))
                os.flush()
            }
            val code = conn.responseCode
            val stream = if (code in 200..299) conn.inputStream else conn.errorStream
            val resp = stream?.bufferedReader()?.use { it.readText() }
            Pair(code, resp)
        } catch (_: Exception) {
            Pair(-1, null)
        } finally {
            conn?.disconnect()
        }
    }

    private fun jsonArrayToStringList(arr: JSONArray?): List<String> {
        if (arr == null) return emptyList()
        val list = ArrayList<String>(arr.length())
        for (i in 0 until arr.length()) {
            list.add(arr.optString(i))
        }
        return list
    }

    // MARK: - Bridge for Method Channels & Java Callers
    fun reverseGeocode(lat: Double, lng: Double, completion: (String) -> Unit) {
        scope.launch {
            val res = reverseGeocode(lat, lng)
            mainHandler.post { completion(res.formattedAddress) }
        }
    }

    fun reverseGeocodeDetailed(lat: Double, lng: Double, completion: (Map<String, Any>) -> Unit) {
        scope.launch {
            val res = reverseGeocode(lat, lng)
            mainHandler.post { completion(res.toMap()) }
        }
    }

    fun panReverseGeocode(lat: Double, lng: Double, completion: (Map<String, Any>) -> Unit) {
        scope.launch {
            val res = panReverseGeocode(lat, lng)
            mainHandler.post { completion(res.toMap()) }
        }
    }
}
