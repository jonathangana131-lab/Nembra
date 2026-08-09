import Foundation
import Testing

@testable import NembraCore

@Suite("Completed ride duration persistence regressions")
struct CompletedRideDurationPersistenceRegressionTests {
    private let sessionID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    @Test("recovered ride may keep duration unavailable without fabricating zero")
    func recoveredUnknownDurationAccepted() throws {
        let ride = try CompletedRideEvidence(
            sessionID: sessionID,
            beganAtDate: Date(timeIntervalSinceReferenceDate: 1_000),
            confirmedAtDate: Date(timeIntervalSinceReferenceDate: 1_010),
            endedAtDate: Date(timeIntervalSinceReferenceDate: 1_200),
            startingOdometerKilometers: nil,
            endingOdometerKilometers: nil,
            qualityScreenedGPSDistanceMeters: 0,
            continuity: .recoveredCheckpoint
        )
        let duration = RideSessionDurationEvidenceAccumulator(sessionID: sessionID).snapshot

        let bound = try CompletedRideDurationEvidence(
            completedRide: ride,
            duration: duration
        )

        #expect(bound.observedDurationNanoseconds == nil)
        #expect(bound.coverage == .unknown)
        #expect(bound.observationSegmentCount == 0)
        #expect(bound.rideContinuity == .recoveredCheckpoint)
    }

    @Test("negative persisted archive observation segment count fails closed")
    func negativeSegmentCountRejected() {
        let data = Data(
            """
            {
              "sessionID": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
              "rideContinuity": "uninterruptedProcess",
              "observedDurationNanoseconds": 1,
              "coverage": "complete",
              "observationSegmentCount": -1
            }
            """.utf8
        )

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(CompletedRideDurationEvidenceArchive.self, from: data)
        }
    }
}