import Foundation
import CoreLocation
import GoogleMaps
import os

/// Structured geocoded address returned to Flutter and native callers.
public struct GeocodedAddress: Sendable {
    public let formattedAddress: String
    public let title: String
    public let subtitle: String
    public let plotNumber: String
    public let street: String
    public let neighborhood: String
    public let city: String
    public let provider: String
    public let isGranular: Bool
    public let confidence: Double
    public let distanceMeters: Double
    public let quarantinedCity: String

    public init(
        formattedAddress: String,
        title: String = "",
        subtitle: String = "",
        plotNumber: String = "",
        street: String = "",
        neighborhood: String = "",
        city: String = "",
        provider: String = "",
        isGranular: Bool = false,
        confidence: Double = 0.0,
        distanceMeters: Double = 0.0,
        quarantinedCity: String = ""
    ) {
        self.formattedAddress = formattedAddress
        self.title = title
        self.subtitle = subtitle
        self.plotNumber = plotNumber
        self.street = street
        self.neighborhood = neighborhood
        self.city = city
        self.provider = provider
        self.isGranular = isGranular
        self.confidence = confidence
        self.distanceMeters = distanceMeters
        self.quarantinedCity = quarantinedCity
    }

    public func toDictionary() -> [String: Any] {
        return [
            "formattedAddress": formattedAddress,
            "title": title,
            "subtitle": subtitle,
            "plotNumber": plotNumber,
            "street": street,
            "neighborhood": neighborhood,
            "city": city,
            "provider": provider,
            "isGranular": isGranular,
            "confidence": confidence,
            "distanceMeters": distanceMeters,
            "quarantinedCity": quarantinedCity
        ]
    }

    public static func fallback(lat: Double, lng: Double, locality: String = "Jhang") -> GeocodedAddress {
        let plusCode = OpenLocationCodeHelper.encodeShort(lat: lat, lng: lng)
        let formatted = "\(plusCode), \(locality)"
        return GeocodedAddress(
            formattedAddress: formatted,
            title: plusCode,
            subtitle: locality,
            city: locality,
            provider: "plus_code",
            isGranular: true,
            confidence: 0.5
        )
    }
}

/// Known Pakistani city centroid for GeoGuard coordinate sanity validation.
struct CityCentroid: Sendable {
    let name: String
    let lat: Double
    let lng: Double
}

/// Authoritative Macro Ground Truth extracted from official polygons (Layer A).
struct AuthoritativeArea: Sendable {
    var city: String
    var neighborhood: String
    var street: String
    var postalCode: String
    var rooftopPlot: String
}

/// Candidate micro-identity from Places or secondary sources (Layer B).
struct MicroCandidate: Sendable {
    let placeId: String
    let displayName: String
    let plotNumber: String
    let premise: String
    let route: String
    let sublocality: String
    let rawLocality: String
    let distanceMeters: Double
    let coordinate: CLLocationCoordinate2D?
    let rawFormatted: String
}

/// Helper for Open Location Code (Plus Code) generation.
public enum OpenLocationCodeHelper {
    private static let alphabet = Array("23456789CFGHJMPQRVWX")
    private static let pairResolutions: [Double] = [20.0, 1.0, 0.05, 0.0025, 0.000125]

    public static func encodeFull(lat: Double, lng: Double) -> String {
        let clampedLat = min(max(lat, -90.0), 90.0)
        let normalizedLng = (lng + 180.0).truncatingRemainder(dividingBy: 360.0) - 180.0
        var latVal = clampedLat + 90.0
        var lngVal = normalizedLng + 180.0

        var chars = ""
        for (i, r) in pairResolutions.enumerated() {
            let latDigit = min(max(Int(floor(latVal / r)), 0), 19)
            let lngDigit = min(max(Int(floor(lngVal / r)), 0), 19)
            chars.append(alphabet[latDigit])
            chars.append(alphabet[lngDigit])
            latVal -= Double(latDigit) * r
            lngVal -= Double(lngDigit) * r
            if i == 3 {
                chars.append("+")
            }
        }
        return chars
    }

    public static func encodeShort(lat: Double, lng: Double) -> String {
        let full = encodeFull(lat: lat, lng: lng)
        if full.count >= 8 {
            let index = full.index(full.startIndex, offsetBy: 4)
            return String(full[index...])
        }
        return full
    }
}

/// Industry-Grade Native iOS Geocoding Service.
/// Implements Two-Layer Authoritative Hierarchical Fusion:
/// - Layer A (Macro): GMSGeocoder official municipal point-in-polygon boundaries (City, Neighborhood, Street)
/// - Layer B (Micro): Google Places API New searchNearby with strict spatial distance gating (<= 40m exact plot)
/// - GeoGuard: Sanitizes user-contributed Place records (>45km city mismatch quarantine, e.g. Sargodha -> Jhang)
/// - 4-Slot Assembly: primary, street, neighborhood, city (zero duplicate tokens or postal codes)
public actor IosGeocodingService {
    public static let shared = IosGeocodingService()

    private let logger = Logger(subsystem: "com.dartnexuslab.swiftride", category: "Geocoding")
    private let session: URLSession

    // Centralized Google Places API Key with places.googleapis.com enabled
    private let defaultPlacesApiKey = "AIzaSyAph82ESQ7BZkhIoaGm5BFv5wMfP1qOwqE"

    // Major Pakistani city centroids for GeoGuard distance validation
    private let pakistanCityCentroids: [CityCentroid] = [
        CityCentroid(name: "Jhang", lat: 31.2681, lng: 72.3181),
        CityCentroid(name: "Sargodha", lat: 32.0836, lng: 72.6711),
        CityCentroid(name: "Faisalabad", lat: 31.4504, lng: 73.1350),
        CityCentroid(name: "Toba Tek Singh", lat: 30.9747, lng: 72.4828),
        CityCentroid(name: "Chiniot", lat: 31.7200, lng: 72.9789),
        CityCentroid(name: "Lahore", lat: 31.5497, lng: 74.3436),
        CityCentroid(name: "Islamabad", lat: 33.6844, lng: 73.0479),
        CityCentroid(name: "Rawalpindi", lat: 33.5651, lng: 73.0169),
        CityCentroid(name: "Multan", lat: 30.1575, lng: 71.5249),
        CityCentroid(name: "Karachi", lat: 24.8607, lng: 67.0011),
        CityCentroid(name: "Gujranwala", lat: 32.1877, lng: 74.1945),
        CityCentroid(name: "Peshawar", lat: 34.0151, lng: 71.5249),
        CityCentroid(name: "Quetta", lat: 30.1798, lng: 66.9750),
        CityCentroid(name: "Sialkot", lat: 32.4945, lng: 74.5229),
        CityCentroid(name: "Bahawalpur", lat: 29.3544, lng: 71.6911),
        CityCentroid(name: "Sukkur", lat: 27.7052, lng: 68.8574),
        CityCentroid(name: "Hyderabad", lat: 25.3960, lng: 68.3578),
        CityCentroid(name: "Sahiwal", lat: 30.6682, lng: 73.1114),
        CityCentroid(name: "Kasur", lat: 31.1179, lng: 74.4461),
        CityCentroid(name: "Sheikhupura", lat: 31.7131, lng: 73.9783)
    ]

    // MARK: - Spatial LRU Cache (~1.1m 5-decimal grid, 15-min TTL)
    private struct CacheEntry {
        let address: GeocodedAddress
        let timestamp: Date
    }
    private var cache: [String: CacheEntry] = [:]
    private var cacheOrder: [String] = []
    private let maxCacheCapacity = 300
    private let cacheTTL: TimeInterval = 15.0 * 60.0 // 15 mins

    // MARK: - In-flight Deduplication & Pan Cancellation
    private var inFlightTasks: [String: Task<GeocodedAddress, Never>] = [:]
    private var currentPanTask: Task<GeocodedAddress, Never>?

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 3.5
        config.timeoutIntervalForResource = 5.0
        self.session = URLSession(configuration: config)
    }

    // MARK: - Main Geocode Entry Point
    public func reverseGeocode(latitude lat: Double, longitude lng: Double) async -> GeocodedAddress {
        let gridKey = String(format: "%.5f,%.5f", lat, lng)

        if let cached = getFromCache(key: gridKey) {
            print("[IosGeocodingService][Cache Hit] Grid \(gridKey) -> \(cached.formattedAddress)")
            return cached
        }

        if let ongoing = inFlightTasks[gridKey] {
            print("[IosGeocodingService][Deduplication] Sharing in-flight request for \(gridKey)")
            return await ongoing.value
        }

        let task = Task<GeocodedAddress, Never> { [weak self] in
            guard let self = self else {
                return GeocodedAddress.fallback(lat: lat, lng: lng)
            }
            return await self.executeTwoLayerFusion(lat: lat, lng: lng)
        }

        inFlightTasks[gridKey] = task
        let result = await task.value
        inFlightTasks.removeValue(forKey: gridKey)

        if result.isGranular {
            saveToCache(key: gridKey, address: result)
        }

        return result
    }

    public func reverseGeocodeDetailed(lat: Double, lng: Double) async -> GeocodedAddress {
        return await self.reverseGeocode(latitude: lat, longitude: lng)
    }

    public func panReverseGeocode(latitude lat: Double, longitude lng: Double) async -> GeocodedAddress {
        currentPanTask?.cancel()
        let panTask = Task<GeocodedAddress, Never> { [weak self] in
            guard let self = self else { return GeocodedAddress.fallback(lat: lat, lng: lng) }
            return await self.reverseGeocode(latitude: lat, longitude: lng)
        }
        currentPanTask = panTask
        return await panTask.value
    }

    public func cancelPanTask() {
        currentPanTask?.cancel()
        currentPanTask = nil
    }

    // MARK: - Two-Layer Authoritative Hierarchical Fusion Engine
    private func executeTwoLayerFusion(lat: Double, lng: Double) async -> GeocodedAddress {
        let startTime = CFAbsoluteTimeGetCurrent()
        let placesKey = (Bundle.main.object(forInfoDictionaryKey: "PlacesApiKey") as? String) ?? defaultPlacesApiKey

        print("[IosGeocodingService] Two-Layer Fusion started for coordinates: (\(lat), \(lng))")

        // -------------------------------------------------------------
        // STAGE 1: Parallel Fetch of Layer A (Macro) & Layer B (Micro)
        // -------------------------------------------------------------
        async let gmsTask = self.fetchGmsMacro(lat: lat, lng: lng)
        async let restTask = self.fetchGeocodingRestMacro(lat: lat, lng: lng, apiKey: placesKey)
        async let placesTask = self.fetchPlacesMicroCandidates(lat: lat, lng: lng, apiKey: placesKey)

        let (macroGms, macroRest, microCandidates) = await (gmsTask, restTask, placesTask)

        // Combine Layer A sources (GMS + Geocoding REST)
        var macroArea = AuthoritativeArea(
            city: !macroGms.city.isEmpty && macroGms.city != "Jhang" ? macroGms.city : (!macroRest.city.isEmpty ? macroRest.city : "Jhang"),
            neighborhood: !macroGms.neighborhood.isEmpty ? macroGms.neighborhood : macroRest.neighborhood,
            street: !macroGms.street.isEmpty ? macroGms.street : macroRest.street,
            postalCode: !macroGms.postalCode.isEmpty ? macroGms.postalCode : macroRest.postalCode,
            rooftopPlot: !macroGms.rooftopPlot.isEmpty ? macroGms.rooftopPlot : macroRest.rooftopPlot
        )

        // -------------------------------------------------------------
        // STAGE 2: Authoritative Macro Resolution (GeoGuard City Lock)
        // -------------------------------------------------------------
        let (isCityValid, authoritativeCity) = validateCityWithGeoGuard(lat: lat, lng: lng, candidateCity: macroArea.city)
        macroArea.city = authoritativeCity

        // Clean redundant sublocality repetitions (e.g. "Satellite Town Block A Satellite Town")
        macroArea.neighborhood = cleanSublocalityRepetitions(macroArea.neighborhood)

        // Check microCandidates for block/phase if macroArea.neighborhood is missing it
        let hasBlockOrPhase = macroArea.neighborhood.range(of: #"\b(?:Block\s+[A-Za-z0-9]+|[A-Za-z0-9]+-Block|Phase\s+[0-9]+)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
        if !hasBlockOrPhase {
            for cand in microCandidates {
                if let match = cand.rawFormatted.range(of: #"\b(?:Block\s+[A-Za-z0-9]+|[A-Za-z0-9]+-Block|Phase\s+[0-9]+)\b"#, options: [.regularExpression, .caseInsensitive]) {
                    let token = String(cand.rawFormatted[match])
                    macroArea.neighborhood = cleanSublocalityRepetitions("\(macroArea.neighborhood) \(token)")
                    break
                }
            }
        }

        // If macro route is empty, enrich via Google Roads API (nearestRoads)
        if macroArea.street.isEmpty {
            if let snapped = await self.snapToNearestRoad(lat: lat, lng: lng, apiKey: placesKey), !snapped.roadName.isEmpty {
                macroArea.street = snapped.roadName
                print("[IosGeocodingService][Roads] Enriched road name: '\(snapped.roadName)'")
            }
        }

        print("[IosGeocodingService][AuthoritativeArea] Locked macro: city='\(macroArea.city)', neighborhood='\(macroArea.neighborhood)', street='\(macroArea.street)'")

        // -------------------------------------------------------------
        // STAGE 3: Strict Spatial Gating & City Quarantine for Micro POIs
        // -------------------------------------------------------------
        var bestMicro: MicroCandidate?
        var quarantinedCityName = ""

        for candidate in microCandidates {
            // Guard: Spatial distance gate
            if candidate.distanceMeters > 150.0 {
                continue
            }

            // Guard: City mismatch quarantine
            let (_, validatedCandidateCity) = validateCityWithGeoGuard(lat: lat, lng: lng, candidateCity: candidate.rawLocality)
            if validatedCandidateCity.caseInsensitiveCompare(macroArea.city) != .orderedSame {
                print("[IosGeocodingService][GeoGuard] Quarantined dirty place city '\(candidate.rawLocality)' on '\(candidate.displayName)' -> enforced authoritative '\(macroArea.city)'")
                quarantinedCityName = candidate.rawLocality
            }

            // Pick the closest valid micro property
            if bestMicro == nil || candidate.distanceMeters < (bestMicro?.distanceMeters ?? Double.infinity) {
                bestMicro = candidate
            }
        }

        // -------------------------------------------------------------
        // STAGE 4: Structured Slot Assembly (Zero Garbage Formatting)
        // -------------------------------------------------------------
        // Slot 1: Primary Micro-Identity (Priority 1: Rooftop Plot)
        var primary = ""
        var distanceToWinner = 0.0

        if !macroArea.rooftopPlot.isEmpty {
            primary = cleanPlotString(macroArea.rooftopPlot)
            distanceToWinner = 0.0
            print("[IosGeocodingService] Priority 1 Rooftop winner: '\(primary)'")
        } else if let micro = bestMicro {
            distanceToWinner = micro.distanceMeters
            if micro.distanceMeters <= 35.0 {
                // Tier 1: Exact plot/property residency (e.g. "Plot 755", "Plot 757")
                let plotClean = cleanPlotString(micro.plotNumber)
                if !plotClean.isEmpty {
                    primary = plotClean
                } else if !micro.displayName.isEmpty && !isGenericGarbageToken(micro.displayName) {
                    primary = micro.displayName
                }
            } else if micro.distanceMeters <= 100.0 {
                // Tier 2: Neighboring plot/establishment — prefix "Near"
                let plotClean = cleanPlotString(micro.plotNumber)
                let name = !plotClean.isEmpty ? plotClean : micro.displayName
                if !name.isEmpty && !isGenericGarbageToken(name) {
                    primary = "Near \(name)"
                }
            }
        }

        // Fallback primary to macro rooftop plot if micro was distant or absent
        if primary.isEmpty && !macroArea.rooftopPlot.isEmpty {
            primary = cleanPlotString(macroArea.rooftopPlot)
        }

        // Fallback primary to street or landmark
        if primary.isEmpty {
            if !macroArea.street.isEmpty {
                primary = macroArea.street
            } else if !macroArea.neighborhood.isEmpty {
                primary = macroArea.neighborhood
            } else {
                primary = macroArea.city
            }
        }

        // Slot 2: Verified Street (omitted if already inside primary or generic garbage)
        var street = !macroArea.street.isEmpty ? macroArea.street : (bestMicro?.route ?? "")
        if street.caseInsensitiveCompare("block") == .orderedSame || isNormalizedSubstring(candidate: street, inside: primary) {
            street = ""
        } else if !primary.isEmpty && (primary.range(of: #"^(?:plot|house|flat|unit)\s+\d+"#, options: [.regularExpression, .caseInsensitive]) != nil || primary.range(of: #"^\d+"#, options: .regularExpression) != nil) {
            // When primary already holds a rooftop plot/house number, strip any leading numeric house prefix from street slot (e.g. "416 Usmania Road" -> "Usmania Road")
            street = street.replacingOccurrences(of: #"^\d+[A-Za-z]?(?:[/-]\d+[A-Za-z]?)?[\s,-]+"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
            if isNormalizedSubstring(candidate: street, inside: primary) {
                street = ""
            }
        }

        // Slot 3: Verified Neighborhood (omitted if already in primary or street)
        var neighborhood = !macroArea.neighborhood.isEmpty ? macroArea.neighborhood : (bestMicro?.sublocality ?? "")
        neighborhood = cleanSublocalityRepetitions(neighborhood)
        if isNormalizedSubstring(candidate: neighborhood, inside: primary) || isNormalizedSubstring(candidate: neighborhood, inside: street) {
            neighborhood = ""
        }

        // Slot 4: Authoritative City (Strictly locked to Layer A ground truth)
        let city = macroArea.city

        // Assemble clean deduplicated slots
        var slots: [String] = []
        let titlePrimary = toTitleCase(primary)
        if !titlePrimary.isEmpty { slots.append(titlePrimary) }

        let titleStreet = toTitleCase(street)
        if !titleStreet.isEmpty && !slots.contains(where: { $0.caseInsensitiveCompare(titleStreet) == .orderedSame }) && !primary.localizedCaseInsensitiveContains(titleStreet) {
            slots.append(titleStreet)
        }

        let titleNeighborhood = toTitleCase(neighborhood)
        if !titleNeighborhood.isEmpty && !slots.contains(where: { $0.caseInsensitiveCompare(titleNeighborhood) == .orderedSame }) && !primary.localizedCaseInsensitiveContains(titleNeighborhood) {
            slots.append(titleNeighborhood)
        }

        let titleCity = toTitleCase(city)
        if !titleCity.isEmpty && !slots.contains(where: { $0.caseInsensitiveCompare(titleCity) == .orderedSame }) {
            slots.append(titleCity)
        }

        let fullFormatted = slots.joined(separator: ", ")
        let subtitleSlots = slots.filter { $0 != titlePrimary }
        let subtitle = subtitleSlots.joined(separator: ", ")

        let latencyMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000.0)
        let providerName: String
        if !macroArea.rooftopPlot.isEmpty && primary == cleanPlotString(macroArea.rooftopPlot) {
            providerName = "geocoding_rest_rooftop_fused"
        } else if let micro = bestMicro {
            if micro.distanceMeters <= 35.0 {
                providerName = "places_nearby_fused"
            } else if micro.distanceMeters <= 100.0 {
                providerName = "places_nearby_near_fused"
            } else {
                providerName = "macro_authoritative_fused"
            }
        } else {
            providerName = "macro_authoritative_fused"
        }

        print("[IosGeocodingService] Winner provider: [\(providerName)] in \(latencyMs)ms: '\(fullFormatted)' (dist: \(String(format: "%.1f", distanceToWinner))m)")
        logger.info("Fused geocode resolved in \(latencyMs)ms: \(fullFormatted)")

        return GeocodedAddress(
            formattedAddress: fullFormatted,
            title: titlePrimary,
            subtitle: subtitle,
            plotNumber: cleanPlotNumberOnly(titlePrimary),
            street: titleStreet.isEmpty ? macroArea.street : titleStreet,
            neighborhood: titleNeighborhood.isEmpty ? macroArea.neighborhood : titleNeighborhood,
            city: titleCity,
            provider: providerName,
            isGranular: true,
            confidence: bestMicro != nil && bestMicro!.distanceMeters <= 35.0 ? 0.95 : 0.85,
            distanceMeters: distanceToWinner,
            quarantinedCity: quarantinedCityName
        )
    }

    // MARK: - Layer A: GMSGeocoder Macro Fetch
    @MainActor
    private func fetchGmsMacro(lat: Double, lng: Double) async -> AuthoritativeArea {
        let coord = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        let geocoder = GMSGeocoder()

        return await withCheckedContinuation { continuation in
            geocoder.reverseGeocodeCoordinate(coord) { response, error in
                if let error = error {
                    print("[IosGeocodingService][GMSGeocoder] Macro error: \(error.localizedDescription)")
                }
                guard let results = response?.results(), !results.isEmpty else {
                    continuation.resume(returning: AuthoritativeArea(city: "Jhang", neighborhood: "", street: "", postalCode: "", rooftopPlot: ""))
                    return
                }

                var city = ""
                var neighborhood = ""
                var street = ""
                var postal = ""
                var rooftop = ""

                for (idx, addr) in results.prefix(5).enumerated() {
                    let lines = addr.lines ?? []
                    print("[IosGeocodingService][GMSGeocoder] Macro [\(idx)] lines: \(lines)")

                    if city.isEmpty, let loc = addr.locality, !loc.isEmpty {
                        city = loc
                    }
                    if neighborhood.isEmpty, let sub = addr.subLocality, !sub.isEmpty {
                        neighborhood = sub
                    }
                    if street.isEmpty, let thoroughfare = addr.thoroughfare, !thoroughfare.isEmpty {
                        street = thoroughfare
                    }
                    if postal.isEmpty, let p = addr.postalCode, !p.isEmpty {
                        postal = p
                    }

                    // Extract rooftop plot if present in first line
                    if rooftop.isEmpty, let firstLine = lines.first {
                        let cleaned = self.cleanGmsSingleLine(firstLine)
                        if let match = cleaned.range(of: #"(?:Plot|House|Flat|Unit|#)?\s*\b(?!35200|40100)\d{1,4}[A-Za-z]?\b"#, options: .regularExpression) {
                            rooftop = String(cleaned[match])
                        }
                    }
                }

                continuation.resume(returning: AuthoritativeArea(
                    city: city.isEmpty ? "Jhang" : city,
                    neighborhood: neighborhood,
                    street: street,
                    postalCode: postal,
                    rooftopPlot: rooftop
                ))
            }
        }
    }

    // MARK: - Layer A2: Google Geocoding REST Macro Fetch
    private func fetchGeocodingRestMacro(lat: Double, lng: Double, apiKey: String) async -> AuthoritativeArea {
        guard let url = URL(string: "https://maps.googleapis.com/maps/api/geocode/json?latlng=\(lat),\(lng)&extra_computations=ADDRESS_DESCRIPTORS&key=\(apiKey)") else {
            return AuthoritativeArea(city: "", neighborhood: "", street: "", postalCode: "", rooftopPlot: "")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("com.dartnexuslab.swiftride", forHTTPHeaderField: "X-Ios-Bundle-Identifier")

        do {
            let (data, response) = try await session.data(for: req)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]], !results.isEmpty else {
                return AuthoritativeArea(city: "", neighborhood: "", street: "", postalCode: "", rooftopPlot: "")
            }

            var city = ""
            var subloc1 = ""
            var subloc2 = ""
            var street = ""
            var postal = ""
            var rooftop = ""
            var blockToken = ""

            for r in results {
                let formatted = r["formatted_address"] as? String ?? ""
                if blockToken.isEmpty, let match = formatted.range(of: #"\b(?:Block\s+[A-Za-z0-9]+|[A-Za-z0-9]+-Block|Phase\s+[0-9]+)\b"#, options: [.regularExpression, .caseInsensitive]) {
                    blockToken = String(formatted[match])
                }

                let comps = r["address_components"] as? [[String: Any]] ?? []
                for comp in comps {
                    let types = comp["types"] as? [String] ?? []
                    let name = (comp["long_name"] as? String ?? comp["short_name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if city.isEmpty && (types.contains("locality") || types.contains("administrative_area_level_2")) {
                        city = name
                    }
                    if subloc1.isEmpty && (types.contains("sublocality_level_1") || types.contains("neighborhood") || types.contains("sublocality")) {
                        subloc1 = name
                    }
                    if subloc2.isEmpty && types.contains("sublocality_level_2") {
                        subloc2 = name
                    }
                    if street.isEmpty && types.contains("route") && name.caseInsensitiveCompare("block") != .orderedSame {
                        street = name
                    }
                    if postal.isEmpty && types.contains("postal_code") {
                        postal = name
                    }
                    if rooftop.isEmpty && (types.contains("street_number") || types.contains("premise")) {
                        if name.caseInsensitiveCompare("block") != .orderedSame && name != "35200" && name != "40100" {
                            rooftop = name
                        }
                    }
                }
            }

            var combinedNeighborhood = subloc1
            if !subloc2.isEmpty {
                if combinedNeighborhood.isEmpty {
                    combinedNeighborhood = subloc2
                } else if !combinedNeighborhood.localizedCaseInsensitiveContains(subloc2) {
                    combinedNeighborhood = "\(combinedNeighborhood) \(subloc2)"
                }
            } else if !blockToken.isEmpty {
                if combinedNeighborhood.isEmpty {
                    combinedNeighborhood = blockToken
                } else if !combinedNeighborhood.localizedCaseInsensitiveContains(blockToken) {
                    combinedNeighborhood = "\(combinedNeighborhood) \(blockToken)"
                }
            }

            return AuthoritativeArea(
                city: city,
                neighborhood: cleanSublocalityRepetitions(combinedNeighborhood),
                street: street,
                postalCode: postal,
                rooftopPlot: rooftop
            )
        } catch {
            print("[IosGeocodingService][GeocodingREST] Macro error: \(error.localizedDescription)")
            return AuthoritativeArea(city: "", neighborhood: "", street: "", postalCode: "", rooftopPlot: "")
        }
    }

    // MARK: - Layer B: Google Places API New Micro Fetch
    private func fetchPlacesMicroCandidates(lat: Double, lng: Double, apiKey: String) async -> [MicroCandidate] {
        // Query single 250m circle with rankPreference: DISTANCE for instant sub-second nearest resolution
        let candidates = await queryPlacesNearbyRadius(lat: lat, lng: lng, radius: 250.0, apiKey: apiKey)
        if !candidates.isEmpty {
            return candidates
        }
        return await queryPlacesNearbyRadius(lat: lat, lng: lng, radius: 500.0, apiKey: apiKey)
    }

    private func queryPlacesNearbyRadius(lat: Double, lng: Double, radius: Double, apiKey: String) async -> [MicroCandidate] {
        guard let url = URL(string: "https://places.googleapis.com/v1/places:searchNearby") else { return [] }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        req.setValue("places.id,places.displayName,places.formattedAddress,places.addressComponents,places.location,places.types", forHTTPHeaderField: "X-Goog-FieldMask")

        let bodyJson: [String: Any] = [
            "locationRestriction": [
                "circle": [
                    "center": ["latitude": lat, "longitude": lng],
                    "radius": radius
                ]
            ],
            "rankPreference": "DISTANCE",
            "maxResultCount": 8
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: bodyJson) else { return [] }
        req.httpBody = bodyData

        do {
            let (data, response) = try await session.data(for: req)
            let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard httpStatus == 200 else {
                let errBody = String(data: data, encoding: .utf8) ?? ""
                print("[IosGeocodingService][PlacesNearby] HTTP \(httpStatus): \(errBody.prefix(120))")
                return []
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let places = json["places"] as? [[String: Any]] else {
                return []
            }

            print("[IosGeocodingService][PlacesNearby] Radius \(radius)m: HTTP 200 OK, found \(places.count) places")

            var results: [MicroCandidate] = []
            for p in places {
                if let candidate = parseMicroCandidate(p, userLat: lat, userLng: lng) {
                    results.append(candidate)
                    print("[IosGeocodingService][PlacesNearby]   - '\(candidate.displayName)' [plot: '\(candidate.plotNumber)'] at \(String(format: "%.1f", candidate.distanceMeters))m")
                }
            }
            return results
        } catch {
            print("[IosGeocodingService][PlacesNearby] Network error: \(error.localizedDescription)")
            return []
        }
    }

    private func parseMicroCandidate(_ place: [String: Any], userLat: Double, userLng: Double) -> MicroCandidate? {
        let placeId = place["id"] as? String ?? ""
        let displayName = (place["displayName"] as? [String: Any])?["text"] as? String ?? ""
        let formatted = place["formattedAddress"] as? String ?? ""

        var streetNumber = ""
        var subpremise = ""
        var premise = ""
        var route = ""
        var subloc1 = ""
        var subloc2 = ""
        var locality = ""
        var admin2 = ""

        if let components = place["addressComponents"] as? [[String: Any]] {
            for comp in components {
                let types = comp["types"] as? [String] ?? []
                let name = comp["longText"] as? String ?? comp["shortText"] as? String ?? ""
                if types.contains("street_number") && streetNumber.isEmpty {
                    streetNumber = name
                } else if types.contains("subpremise") && subpremise.isEmpty {
                    subpremise = name
                } else if types.contains("premise") && premise.isEmpty {
                    premise = name
                } else if types.contains("route") && route.isEmpty {
                    route = name
                } else if (types.contains("sublocality_level_1") || types.contains("neighborhood")) && subloc1.isEmpty {
                    subloc1 = name
                } else if types.contains("sublocality_level_2") && subloc2.isEmpty {
                    subloc2 = name
                } else if types.contains("locality") && locality.isEmpty {
                    locality = name
                } else if types.contains("administrative_area_level_2") && admin2.isEmpty {
                    admin2 = name
                }
            }
        }

        var combinedNeighborhood = subloc1
        if !subloc2.isEmpty {
            if combinedNeighborhood.isEmpty {
                combinedNeighborhood = subloc2
            } else if !combinedNeighborhood.localizedCaseInsensitiveContains(subloc2) {
                combinedNeighborhood = "\(combinedNeighborhood) \(subloc2)"
            }
        }

        // If components have premise (e.g. premise: "755", subpremise: "H")
        var plot = ""
        if !streetNumber.isEmpty {
            plot = streetNumber
        } else if !premise.isEmpty && premise.range(of: #"^\d+[A-Za-z]?$"#, options: .regularExpression) != nil {
            plot = !subpremise.isEmpty ? "\(premise) \(subpremise)" : premise
        }

        // If displayName contains plot (e.g. "Plot 741 A", "Plot 602 A", "Plot 757 A")
        if plot.isEmpty {
            if let match = displayName.range(of: #"(?:Plot|House|H|Unit)\s*#?\s*([0-9]+[A-Za-z]?)"#, options: .regularExpression) {
                plot = String(displayName[match])
            }
        }

        var coord: CLLocationCoordinate2D?
        var dist = 9999.0
        if let loc = place["location"] as? [String: Any],
           let pLat = loc["latitude"] as? Double,
           let pLng = loc["longitude"] as? Double {
            coord = CLLocationCoordinate2D(latitude: pLat, longitude: pLng)
            dist = haversineDistance(lat1: userLat, lon1: userLng, lat2: pLat, lon2: pLng)
        }

        return MicroCandidate(
            placeId: placeId,
            displayName: displayName,
            plotNumber: plot,
            premise: premise,
            route: route,
            sublocality: combinedNeighborhood,
            rawLocality: locality.isEmpty ? admin2 : locality,
            distanceMeters: dist,
            coordinate: coord,
            rawFormatted: formatted
        )
    }

    // MARK: - GeoGuard Coordinate-to-City Distance Validator
    nonisolated private func validateCityWithGeoGuard(lat: Double, lng: Double, candidateCity: String) -> (isValid: Bool, city: String) {
        let trimmed = candidateCity.trimmingCharacters(in: .whitespacesAndNewlines)
        let nearest = findNearestCityCentroid(lat: lat, lng: lng)

        if trimmed.isEmpty || trimmed.lowercased() == "naya shehar" {
            return (false, nearest.name)
        }

        for c in pakistanCityCentroids {
            if c.name.caseInsensitiveCompare(trimmed) == .orderedSame {
                let distKm = haversineDistance(lat1: lat, lon1: lng, lat2: c.lat, lon2: c.lng) / 1000.0
                if distKm > 45.0 {
                    return (false, nearest.name)
                } else {
                    return (true, c.name)
                }
            }
        }

        return (true, trimmed)
    }

    nonisolated private func findNearestCityCentroid(lat: Double, lng: Double) -> CityCentroid {
        var best = pakistanCityCentroids[0]
        var minDist = Double.infinity
        for c in pakistanCityCentroids {
            let d = haversineDistance(lat1: lat, lon1: lng, lat2: c.lat, lon2: c.lng)
            if d < minDist {
                minDist = d
                best = c
            }
        }
        return best
    }

    nonisolated private func haversineDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let r = 6371000.0
        let dLat = (lat2 - lat1) * .pi / 180.0
        let dLon = (lon2 - lon1) * .pi / 180.0
        let a = sin(dLat / 2) * sin(dLat / 2) +
                cos(lat1 * .pi / 180.0) * cos(lat2 * .pi / 180.0) *
                sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return r * c
    }

    // MARK: - Roads API: Curb-Snap Off-Road Pins to Nearest Road
    private func snapToNearestRoad(lat: Double, lng: Double, apiKey: String) async -> (lat: Double, lng: Double, roadName: String)? {
        guard let url = URL(string: "https://roads.googleapis.com/v1/nearestRoads?points=\(lat),\(lng)&key=\(apiKey)") else {
            return nil
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("com.dartnexuslab.swiftride", forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        do {
            let (data, response) = try await session.data(for: req)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let points = json["snappedPoints"] as? [[String: Any]],
                  let first = points.first else {
                return nil
            }
            let loc = first["location"] as? [String: Any]
            let sLat = loc?["latitude"] as? Double ?? lat
            let sLng = loc?["longitude"] as? Double ?? lng
            var roadName = ""
            if let placeId = first["placeId"] as? String, !placeId.isEmpty {
                roadName = await fetchRoadNameFromPlaceId(placeId: placeId, apiKey: apiKey)
            }
            return (lat: sLat, lng: sLng, roadName: roadName)
        } catch {
            return nil
        }
    }

    private func fetchRoadNameFromPlaceId(placeId: String, apiKey: String) async -> String {
        guard let url = URL(string: "https://maps.googleapis.com/maps/api/geocode/json?place_id=\(placeId)&key=\(apiKey)") else {
            return ""
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("com.dartnexuslab.swiftride", forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        do {
            let (data, response) = try await session.data(for: req)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]],
                  let first = results.first else {
                return ""
            }
            let comps = first["address_components"] as? [[String: Any]] ?? []
            for comp in comps {
                let types = comp["types"] as? [String] ?? []
                if types.contains("route") {
                    return (comp["long_name"] as? String ?? comp["short_name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        } catch {}
        return ""
    }

    // MARK: - Clean Formatting Helpers
    nonisolated private func toTitleCase(_ str: String) -> String {
        guard !str.isEmpty else { return str }
        let words = str.components(separatedBy: " ")
        return words.map { word -> String in
            guard let first = word.first else { return word }
            if word == word.uppercased() && word.count <= 4 {
                return word
            }
            if word.contains("-") {
                return word.components(separatedBy: "-").map { toTitleCase($0) }.joined(separator: "-")
            }
            return String(first).uppercased() + word.dropFirst().lowercased()
        }.joined(separator: " ")
    }

    nonisolated private func cleanPlotString(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "35200" || trimmed == "40100" || trimmed.lowercased() == "block" {
            return ""
        }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("plot ") || lower.hasPrefix("house ") || lower.hasPrefix("flat ") || lower.hasPrefix("unit ") {
            return trimmed
        }
        if trimmed.range(of: #"^\d+\s*[A-Za-z]?$"#, options: .regularExpression) != nil {
            return "Plot \(trimmed)"
        }
        return trimmed
    }

    nonisolated private func cleanPlotNumberOnly(_ primary: String) -> String {
        if let match = primary.range(of: #"\b\d{1,4}\s*[A-Za-z]?\b"#, options: .regularExpression) {
            return String(primary[match])
        }
        return ""
    }

    nonisolated private func cleanSublocalityRepetitions(_ raw: String) -> String {
        var s = raw.replacingOccurrences(of: "Satellite Town Block A Satellite Town", with: "Satellite Town Block A")
        s = s.replacingOccurrences(of: "Satellite Block A Town", with: "Satellite Town Block A")
        let words = s.components(separatedBy: " ").filter { !$0.isEmpty }
        if words.count >= 4 {
            for wlen in 2...(words.count / 2) {
                let prefix = words.prefix(wlen).joined(separator: " ")
                if s.hasSuffix(" " + prefix) {
                    s = String(s.dropLast(prefix.count + 1)).trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
                    break
                }
            }
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private func cleanGmsSingleLine(_ line: String) -> String {
        var s = line.replacingOccurrences(of: #"\b\d{5}\b"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\bPakistan\b"#, with: "", options: [.caseInsensitive, .regularExpression])
        s = s.replacingOccurrences(of: #"\bNaya Shehar\b"#, with: "", options: [.caseInsensitive, .regularExpression])
        s = s.replacingOccurrences(of: #"[\s,]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
        return cleanSublocalityRepetitions(s)
    }

    nonisolated private func isNormalizedSubstring(candidate: String, inside container: String) -> Bool {
        if candidate.isEmpty || container.isEmpty { return false }
        let c1 = candidate.lowercased().replacingOccurrences(of: "road", with: "rd").replacingOccurrences(of: "street", with: "st")
        let c2 = container.lowercased().replacingOccurrences(of: "road", with: "rd").replacingOccurrences(of: "street", with: "st")
        return c2.contains(c1)
    }

    nonisolated private func isGenericGarbageToken(_ name: String) -> Bool {
        let lower = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return lower.isEmpty || lower == "block" || lower == "h" || lower == "35200" || lower == "40100" || lower == "pakistan" || lower == "naya shehar"
    }

    // MARK: - Granularity Check
    public func isGranularAddress(_ address: String) -> Bool {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.starts(with: "Location (") || trimmed.starts(with: "Pinned Spot") {
            return false
        }

        let hasPlusCode = trimmed.range(of: #"\b[A-Za-z0-9]{4,8}\+[A-Za-z0-9]{2,5}\b"#, options: .regularExpression) != nil

        let withoutPlusCode = trimmed.replacingOccurrences(
            of: #"\b[A-Za-z0-9]{4,8}\+[A-Za-z0-9]{2,5}\b"#,
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        let broadCities = [
            "jhang", "central jhang", "jhang sadar", "jhang city", "lahore",
            "faisalabad", "karachi", "islamabad", "rawalpindi", "multan",
            "peshawar", "quetta", "sialkot", "gujranwala", "sargodha", "toba tek singh"
        ]
        let lower = withoutPlusCode.lowercased()
        if broadCities.contains(lower) {
            return hasPlusCode
        }

        let pattern = #"\b(plot|house|shop|flat|apt|apartment|suite|floor|unit|plaza|tower|center|centre|complex|arcade|heights|residency|villa|manzil|cottage|chambers|hospital|clinic|pharmacy|university|college|school|academy|institute|masjid|mosque|church|temple|market|bazaar|mall|mart|store|bank|hotel|restaurant|cafe|bakery|station|terminal|stop|park|stadium|club|gym|court|office|street|st|road|rd|avenue|ave|lane|ln|boulevard|blvd|chowk|bazar|gali|kucha|mohalla|mohallah|block|sector|phase|scheme|police|lines|cantonment|cantt|sadar|saddar|hall|markaz|branch|gate|pul|bridge|stand|adda|basti|kot|deh|chak|mouza|moza|deri|dhok|tehsil|headworks|patrolling|barracks|near|opposite|behind|beside)\b"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let range = NSRange(location: 0, length: withoutPlusCode.utf16.count)
            if regex.firstMatch(in: withoutPlusCode, options: [], range: range) != nil {
                return true
            }
        }

        if let numRegex = try? NSRegularExpression(pattern: #"(?:^|[,\s#/-])\d+[A-Za-z]?(?:\b|$)"#) {
            let range = NSRange(location: 0, length: withoutPlusCode.utf16.count)
            if numRegex.firstMatch(in: withoutPlusCode, options: [], range: range) != nil {
                return true
            }
        }

        let segments = withoutPlusCode.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let nonAdmin = segments.filter { seg in
            let s = seg.lowercased()
            if s == "pakistan" || s == "pk" { return false }
            if s == "punjab" || s == "sindh" || s == "kpk" || s == "khyber pakhtunkhwa" || s == "balochistan" || s == "islamabad capital territory" { return false }
            if broadCities.contains(s) { return false }
            if s.starts(with: "central ") && broadCities.contains(String(s.dropFirst(8))) { return false }
            return true
        }

        return nonAdmin.count >= 2 || hasPlusCode
    }

    // MARK: - Spatial LRU Cache Management
    private func getFromCache(key: String) -> GeocodedAddress? {
        guard let entry = cache[key] else { return nil }
        if Date().timeIntervalSince(entry.timestamp) > cacheTTL {
            cache.removeValue(forKey: key)
            cacheOrder.removeAll(where: { $0 == key })
            return nil
        }
        cacheOrder.removeAll(where: { $0 == key })
        cacheOrder.append(key)
        return entry.address
    }

    private func saveToCache(key: String, address: GeocodedAddress) {
        guard address.isGranular && isGranularAddress(address.formattedAddress) else { return }

        while cacheOrder.count >= maxCacheCapacity, let oldest = cacheOrder.first {
            cacheOrder.removeFirst()
            cache.removeValue(forKey: oldest)
        }

        cache[key] = CacheEntry(address: address, timestamp: Date())
        cacheOrder.removeAll(where: { $0 == key })
        cacheOrder.append(key)
    }
}

// MARK: - Nonisolated Bridge for Method Channels & Objective-C / Swift Callers
extension IosGeocodingService {
    nonisolated public func reverseGeocode(latitude lat: Double, longitude lng: Double, completion: @escaping (String) -> Void) {
        Task {
            let res = await self.reverseGeocode(latitude: lat, longitude: lng)
            DispatchQueue.main.async {
                completion(res.formattedAddress)
            }
        }
    }

    nonisolated public func reverseGeocodeDetailed(latitude lat: Double, longitude lng: Double, completion: @escaping ([String: Any]) -> Void) {
        Task {
            let res = await self.reverseGeocode(latitude: lat, longitude: lng)
            DispatchQueue.main.async {
                completion(res.toDictionary())
            }
        }
    }

    nonisolated public func panReverseGeocode(latitude lat: Double, longitude lng: Double, completion: @escaping ([String: Any]) -> Void) {
        Task {
            let res = await self.panReverseGeocode(latitude: lat, longitude: lng)
            DispatchQueue.main.async {
                completion(res.toDictionary())
            }
        }
    }

    nonisolated public func cancelPendingGeocode() {
        Task {
            await self.cancelPanTask()
        }
    }
}
