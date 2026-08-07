import Foundation
import Testing
@testable import NembraCore

@Suite("Ride live-distance reconciliation bridge")
struct RideLiveDistanceReconciliationBridgeTests {
    private let rideID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let otherRideID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    private let segmentID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    private func completedRide(sessionID: UUID) throws -> CompletedRideEvidence {
        try CompletedRideEvidence(
            sessionID: sessionID,
            beganAtDate: Date(timeIntervalSinceReferenceDate: 100),
            confirmedAtDate: Date(timeIntervalSinceReferenceDate: 101),
            endedAtDate: Date(timeIntervalSinceReferenceDate: 200),
            startingOdometerKilometers: nil,
            endingOdometerKilometers: nil,
            qualityScreenedGPSDistanceMeters: 0,
            continuity: .uninterruptedProcess
        )
    }

    private func aggregate(sessionID: UUID) throws -> RideLiveDistanceAggregate {
        let finalized = FinalizedLiveDistanceSegment(
            source: .scooterBluetooth,
            method: .trapezoidalBetweenMeasurements,
            segmentStartUptimeNanoseconds: 0,
            segmentEndUptimeNanoseconds: 1,
            firstAcceptedSampleUptimeNanoseconds: 0,
            lastAcceptedSampleUptimeNanoseconds: 1,
            distanceMeters: 10,
            coverage: .complete,
            acceptedSampleCount: 2,
            integratedIntervalCount: 1,
            knownCoverageGapCount: 0
        )
        let durable = try RideLiveDistanceSegmentEvidence(
            rideSessionID: sessionID,
            segmentID: segmentID,
            processSegmentSequence: 0,
            finalizedSegment: finalized
        )
        return try RideLiveDistanceAggregator.aggregate(
            rideSessionID: sessionID,
            source: .scooterBluetooth,
            method: .trapezoidalBetweenMeasurements,
            records: [durable]
        )
    }

    @Test("same-session aggregate becomes live distance evidence without losing coverage")
    func sameSessionBridges() throws {
        let completed = try completedRide(sessionID: rideID)
        let liveDistance = try aggregate(sessionID: rideID)

        let evidence = try RideDistanceEvidence(
            completedRide: completed,
            odometerCoverage: .unknown,
            gpsRouteCoverage: .complete,
            liveDistanceAggregate: liveDistance,
            transportGapOccurred: false
        )

        #expect(evidence.liveIntegratedDistanceMeters == 10)
        #expect(evidence.liveIntegratedCoverage == .complete)
        #expect(evidence.gpsRouteDistanceMeters == 0)
        #expect(evidence.gpsRouteCoverage == .complete)
    }

    @Test("aggregate from a different ride cannot be paired with completed evidence")
    func crossRideAggregateFailsClosed() throws {
        let completed = try completedRide(sessionID: rideID)
        let foreignAggregate = try aggregate(sessionID: otherRideID)

        #expect(throws: RideDistanceReconciliationError.invalidEvidence) {
            _ = try RideDistanceEvidence(
                completedRide: completed,
                odometerCoverage: .unknown,
                gpsRouteCoverage: .complete,
                liveDistanceAggregate: foreignAggregate,
                transportGapOccurred: false
            )
        }
    }

    @Test("missing aggregate remains unavailable instead of fabricating zero live distance")
    func missingAggregateRemainsUnknown() throws {
        let completed = try completedRide(sessionID: rideID)

        let evidence = try RideDistanceEvidence(
            completedRide: completed,
            odometerCoverage: .unknown,
            gpsRouteCoverage: .complete,
            liveDistanceAggregate: nil,
            transportGapOccurred: false
        )

        #expect(evidence.liveIntegratedDistanceMeters == nil)
        #expect(evidence.liveIntegratedCoverage == .unknown)
    }
}
