import Foundation
import Testing

@testable import NembraCore

@Suite("Ride history duration statistics adapter")
struct RideHistoryDurationStatisticsAdapterTests {
    private let sessionID = UUID(uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF")!
    private let beganAt = Date(timeIntervalSinceReferenceDate: 10_000)
    private let endedAt = Date(timeIntervalSinceReferenceDate: 10_300)

    private func completedRide(
        continuity: RideSessionContinuity = .uninterruptedProcess
    ) throws -> CompletedRideEvidence {
        try CompletedRideEvidence(
            sessionID: sessionID,
            beganAtDate: beganAt,
            confirmedAtDate: beganAt.addingTimeInterval(5),
            endedAtDate: endedAt,
            startingOdometerKilometers: 25,
            endingOdometerKilometers: 27,
            qualityScreenedGPSDistanceMeters: 1_900,
            continuity: continuity
        )
    }

    private func joinedRecord(
        observedDurationNanoseconds: UInt64?,
        coverage: RideSessionDurationCoverage,
        observationSegmentCount: Int,
        continuity: RideSessionContinuity = .uninterruptedProcess
    ) throws -> RideHistoryDurationJoinedRecord {
        let completed = try completedRide(continuity: continuity)
        let duration = RideSessionDurationEvidenceSnapshot(
            sessionID: sessionID,
            observedDurationNanoseconds: observedDurationNanoseconds,
            coverage: coverage,
            observationSegmentCount: observationSegmentCount
        )
        let durationEvidence = try CompletedRideDurationEvidence(
            completedRide: completed,
            duration: duration
        )

        return try RideHistoryDurationJoinedRecord(
            historyRecord: RideHistoryRecord(evidence: completed),
            durationRecord: RideHistoryDurationRecord(evidence: durationEvidence)
        )
    }

    @Test("validated history join becomes duration statistics without weakening evidence")
    func completeObservedDurationBridges() throws {
        let joined = try joinedRecord(
            observedDurationNanoseconds: 180_000_000_000,
            coverage: .complete,
            observationSegmentCount: 1
        )

        let ride = try RideDurationStatisticsRide(
            historyDurationRecord: joined,
            calendarAttribution: .rideEnded
        )

        #expect(ride.sessionID == sessionID)
        #expect(ride.attributedDate == endedAt)
        #expect(ride.observedDurationNanoseconds == 180_000_000_000)
        #expect(ride.coverage == .complete)
    }

    @Test("calendar attribution remains explicit at the trusted bridge")
    func beganAttributionBridges() throws {
        let joined = try joinedRecord(
            observedDurationNanoseconds: 42_000_000_000,
            coverage: .complete,
            observationSegmentCount: 1
        )

        let ride = try RideDurationStatisticsRide(
            historyDurationRecord: joined,
            calendarAttribution: .rideBegan
        )

        #expect(ride.attributedDate == beganAt)
    }

    @Test("unavailable duration stays unavailable through the statistics bridge")
    func unavailableDurationStaysUnavailable() throws {
        let joined = try joinedRecord(
            observedDurationNanoseconds: nil,
            coverage: .unknown,
            observationSegmentCount: 0
        )

        let ride = try RideDurationStatisticsRide(
            historyDurationRecord: joined,
            calendarAttribution: .rideEnded
        )

        #expect(ride.observedDurationNanoseconds == nil)
        #expect(ride.coverage == .unknown)
    }

    @Test("recovered partial duration remains partial through statistics bridge")
    func recoveredPartialDurationStaysPartial() throws {
        let joined = try joinedRecord(
            observedDurationNanoseconds: 75_000_000_000,
            coverage: .partial,
            observationSegmentCount: 1,
            continuity: .recoveredCheckpoint
        )

        let ride = try RideDurationStatisticsRide(
            historyDurationRecord: joined,
            calendarAttribution: .rideEnded
        )

        #expect(ride.observedDurationNanoseconds == 75_000_000_000)
        #expect(ride.coverage == .partial)
    }
}
