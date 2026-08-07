import Foundation
import Testing
@testable import NembraCore

@Suite("Ride route point date validation")
struct RideRoutePointDateValidationTests {
    private let validDate = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test("route points reject non-finite wall-clock dates")
    func nonFiniteDatesRejectedAtConstruction() {
        #expect(throws: RideRouteEvidenceError.invalidDate) {
            _ = try RideRoutePoint(
                sequence: 0,
                latitude: 45,
                longitude: -122,
                capturedAtDate: Date(timeIntervalSinceReferenceDate: .infinity)
            )
        }

        #expect(throws: RideRouteEvidenceError.invalidDate) {
            _ = try RideRoutePoint(
                sequence: 0,
                latitude: 45,
                longitude: -122,
                capturedAtDate: validDate,
                sourceMeasurementDate: Date(timeIntervalSinceReferenceDate: .nan)
            )
        }
    }

    @Test("decoded route points cannot bypass date invariants")
    func decodedNonFiniteDatesRejected() throws {
        let invalidCapturedDate = RawRoutePoint(
            sequence: 0,
            latitude: 45,
            longitude: -122,
            capturedAtDate: Date(timeIntervalSinceReferenceDate: .infinity),
            sourceMeasurementDate: validDate,
            horizontalAccuracyMeters: 4
        )
        let invalidSourceDate = RawRoutePoint(
            sequence: 1,
            latitude: 45,
            longitude: -122,
            capturedAtDate: validDate,
            sourceMeasurementDate: Date(timeIntervalSinceReferenceDate: .nan),
            horizontalAccuracyMeters: 4
        )

        let invalidCapturedData = try PropertyListEncoder().encode(invalidCapturedDate)
        let invalidSourceData = try PropertyListEncoder().encode(invalidSourceDate)

        #expect(throws: RideRouteEvidenceError.invalidDate) {
            _ = try PropertyListDecoder().decode(RideRoutePoint.self, from: invalidCapturedData)
        }
        #expect(throws: RideRouteEvidenceError.invalidDate) {
            _ = try PropertyListDecoder().decode(RideRoutePoint.self, from: invalidSourceData)
        }
    }

    @Test("finite route point dates remain valid")
    func finiteDatesRemainValid() throws {
        let point = try RideRoutePoint(
            sequence: 2,
            latitude: 45,
            longitude: -122,
            capturedAtDate: validDate,
            sourceMeasurementDate: validDate.addingTimeInterval(-1),
            horizontalAccuracyMeters: 4
        )

        #expect(point.capturedAtDate == validDate)
        #expect(point.sourceMeasurementDate == validDate.addingTimeInterval(-1))
    }
}

private struct RawRoutePoint: Encodable {
    let sequence: UInt64
    let latitude: Double
    let longitude: Double
    let capturedAtDate: Date
    let sourceMeasurementDate: Date?
    let horizontalAccuracyMeters: Double?
}
