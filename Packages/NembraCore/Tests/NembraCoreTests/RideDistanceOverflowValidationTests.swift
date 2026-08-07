import Foundation
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

    @Test("completed ride bridge rejects meter overflow without rewriting raw ODO evidence")
    func completedRideBridgeRejectsMeterOverflow() throws {
        let completedRide = try CompletedRideEvidence(
            sessionID: UUID(),
            beganAtDate: Date(timeIntervalSinceReferenceDate: 100),
            confirmedAtDate: Date(timeIntervalSinceReferenceDate: 101),
            endedAtDate: Date(timeIntervalSinceReferenceDate: 200),
            startingOdometerKilometers: 0,
            endingOdometerKilometers: .greatestFiniteMagnitude,
            qualityScreenedGPSDistanceMeters: 0,
            continuity: .uninterruptedProcess
        )

        #expect(completedRide.odometerDeltaKilometers?.isFinite == true)
        #expect(throws: RideDistanceReconciliationError.invalidEvidence) {
            _ = try RideDistanceEvidence(
                completedRide: completedRide,
                odometerCoverage: .complete,
                gpsRouteCoverage: .unknown,
                liveDistanceAggregate: nil,
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
