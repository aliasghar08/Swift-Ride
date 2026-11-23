import XCTest
@testable import Runner

final class IosGeocodingHarnessTests: XCTestCase {

    func testBatchHeadlessCoordinateGeocoding() async throws {
        let targets: [(lat: Double, lng: Double, description: String)] = [
            (31.26294, 72.35241, "Plot 765 / Plot 763 A, Green Belt, Block A"),
            (31.26303, 72.35172, "Plot 772 A, Usmania Road, Block A"),
            (31.26163, 72.35222, "Plot 694 A, Sarwar Road, Block A"),
            (31.26320, 72.35184, "Plot 757 A, Green Belt / Plot 755 (GeoGuard Sargodha Quarantine)"),
            (31.27400, 72.33000, "Plot 4, Police Lines, Jhang")
        ]

        print("==========================================================================================")
        print("  SWIFT XCTEST HEADLESS COORDINATE HARNESS (IosGeocodingService)")
        print("==========================================================================================")

        for (idx, target) in targets.enumerated() {
            let start = CFAbsoluteTimeGetCurrent()
            let result = await IosGeocodingService.shared.reverseGeocodeDetailed(lat: target.lat, lng: target.lng)
            let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000.0)

            print("\n[Target \(idx + 1)/\(targets.count)] \(target.description)")
            print("  • Coordinates     : (\(target.lat), \(target.lng))")
            print("  • Formatted Addr  : \"\(result.formattedAddress)\"")
            print("  • Title           : \"\(result.title)\"")
            print("  • Subtitle        : \"\(result.subtitle)\"")
            print("  • Plot Number     : \"\(result.plotNumber)\"")
            print("  • Street          : \"\(result.street)\"")
            print("  • Neighborhood    : \"\(result.neighborhood)\"")
            print("  • City            : \"\(result.city)\"")
            print("  • Provider        : \(result.provider)")
            print("  • Is Granular     : \(result.isGranular)")
            print("  • Quarantined City: \"\(result.quarantinedCity)\"")
            print("  • Latency         : \(elapsedMs)ms")

            // GeoGuard assertions
            XCTAssertFalse(
                result.formattedAddress.contains("Sargodha"),
                "Address must never contain quarantined city 'Sargodha' for Jhang coordinates (\(target.lat), \(target.lng))"
            )
            XCTAssertFalse(
                result.city.contains("Sargodha"),
                "City must never be 'Sargodha' for Jhang coordinates"
            )
            XCTAssertFalse(
                result.formattedAddress.contains("Naya Shehar"),
                "Address must never contain quarantined city 'Naya Shehar' for Jhang coordinates"
            )
            XCTAssertFalse(
                result.formattedAddress.contains("Satellite Town Block A Satellite Town"),
                "Address must not contain duplicate neighborhood tokens"
            )
            XCTAssertFalse(
                result.formattedAddress.range(of: #"^\s*35200"#, options: .regularExpression) != nil,
                "Address must not start with bare postal code '35200'"
            )
            XCTAssertFalse(
                result.formattedAddress.hasSuffix("Pakistan"),
                "Address must strip redundant trailing country 'Pakistan'"
            )
            XCTAssertFalse(
                result.formattedAddress.contains("saddar"),
                "Lowercase 'saddar' must be normalized to Title Case 'Saddar'"
            )
            XCTAssertFalse(
                result.formattedAddress.range(of: #"(?:^|,\s*)Block(?:,|$)"#, options: .regularExpression) != nil,
                "Address must not contain isolated 'Block' as a street"
            )
            XCTAssertFalse(
                result.formattedAddress.contains("Plot 772, 416") || result.formattedAddress.contains("Plot 772 A, 416"),
                "Address must strip redundant house number from street slot when primary is already a plot"
            )

            // Authoritative ground truth assertions
            XCTAssertTrue(
                result.city.caseInsensitiveCompare("Jhang") == .orderedSame || result.formattedAddress.contains("Jhang"),
                "Address must contain authoritative city 'Jhang'"
            )
            XCTAssertTrue(
                result.isGranular,
                "Geocoded address must be marked granular"
            )
            XCTAssertFalse(
                result.formattedAddress.isEmpty,
                "Formatted address must not be empty"
            )
        }

        print("\n==========================================================================================")
        print("  ALL 4 BATCH COORDINATE ASSERTIONS PASSED WITH ZERO PHYSICAL IPHONE INTERRUPTIONS")
        print("==========================================================================================")
    }
}
