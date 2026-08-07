import Testing
@testable import NembraCore

@Suite("Ride distance overflow validation")
struct RideDistanceOverflowValidationTests {
    @Test("finite odometer anchors are rejected when meter conversion would overflow")
    func rejectsFiniteOdometerMeterOverflow() {
        #expect(throws: RideDistanceReconciliationError.invalidEvidence) {
            _ = try RideDistanceEvidence(
                startingOdometerKilometers: 0,
                endingOdometerKilometers: .greatestFiniteMagnitude,
                odometerCoverage: .complete,
                gpsRouteDistanceMeters: nil,
                gpsRouteCoverage: .unknown,
                liveIntegratedDistanceMeters: nil,
                liveIntegratedCoverage: .unknown,
                transportGapOccurred: false
            )
        }
    }

    @Test("large finite odometer deltas remain usable when meter conversion stays finite")
    func acceptsLargeFiniteOdometerDelta() throws {
        let endingKilometers = Double.greatestFiniteMagnitude / 2_000
        let evidence = try RideDistanceEvidence(
            startingOdometerKilometers: 0,
            endingOdometerKilometers: endingKilometers,
            odometerCoverage: .complete,
            gpsRouteDistanceMeters: nil,
            gpsRouteCoverage: .unknown,
            liveIntegratedDistanceMeters: nil,
            liveIntegratedCoverage: .unknown,
            transportGapOccurred: false
        )

        let distanceMeters = try #require(evidence.scooterOdometerDeltaMeters)
        #expect(distanceMeters.isFinite)
        #expect(distanceMeters > 0)
    }
}
