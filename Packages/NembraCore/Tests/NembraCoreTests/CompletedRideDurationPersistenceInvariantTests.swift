import Foundation
import Testing

@testable import NembraCore

@Suite("Completed ride duration persistence invariants")
struct CompletedRideDurationPersistenceInvariantTests {
    @Test("decoded complete coverage cannot claim multiple observation segments")
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
            try JSONDecoder().decode(CompletedRideDurationEvidence.self, from: data)
        }
    }

    @Test("partial coverage with one observed segment remains representable")
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
            CompletedRideDurationEvidence.self,
            from: data
        )

        #expect(decoded.observedDurationNanoseconds == 1)
        #expect(decoded.coverage == .partial)
        #expect(decoded.observationSegmentCount == 1)
    }
}
