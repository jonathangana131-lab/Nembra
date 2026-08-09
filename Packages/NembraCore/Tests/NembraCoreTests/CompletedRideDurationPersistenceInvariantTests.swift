import Foundation
import Testing

@testable import NembraCore

@Suite("Completed ride duration persistence invariants")
struct CompletedRideDurationPersistenceInvariantTests {
    private let sessionID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    private func completedRide() throws -> CompletedRideEvidence {
        let date = Date(timeIntervalSinceReferenceDate: 1_000)
        return try CompletedRideEvidence(
            sessionID: sessionID,
            beganAtDate: date,
            confirmedAtDate: date,
            endedAtDate: date,
            startingOdometerKilometers: nil,
            endingOdometerKilometers: nil,
            qualityScreenedGPSDistanceMeters: 0,
            continuity: .uninterruptedProcess
        )
    }

    @Test("bound complete coverage cannot claim multiple observation segments")
    func boundCompleteMultipleSegmentsRejected() throws {
        let duration = RideSessionDurationEvidenceSnapshot(
            sessionID: sessionID,
            observedDurationNanoseconds: 2,
            coverage: .complete,
            observationSegmentCount: 2
        )

        #expect(throws: CompletedRideDurationEvidenceError.invalidDurationEvidence) {
            try CompletedRideDurationEvidence(
                completedRide: completedRide(),
                duration: duration
            )
        }
    }

    @Test("decoded complete archive cannot claim multiple observation segments")
    func malformedCompleteMultipleSegmentsRejected() {
        let data = Data(
            """
            {
              "sessionID": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
              "rideContinuity": "uninterruptedProcess",
              "observedDurationNanoseconds": 2,
              "coverage": "complete",
              "observationSegmentCount": 2
            }
            """.utf8
        )

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(CompletedRideDurationEvidenceArchive.self, from: data)
        }
    }

    @Test("partial coverage with one observed segment remains representable in archive")
    func partialSingleSegmentAccepted() throws {
        let data = Data(
            """
            {
              "sessionID": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
              "rideContinuity": "uninterruptedProcess",
              "observedDurationNanoseconds": 1,
              "coverage": "partial",
              "observationSegmentCount": 1
            }
            """.utf8
        )

        let decoded = try JSONDecoder().decode(
            CompletedRideDurationEvidenceArchive.self,
            from: data
        )

        #expect(decoded.observedDurationNanoseconds == 1)
        #expect(decoded.coverage == .partial)
        #expect(decoded.observationSegmentCount == 1)
    }
}