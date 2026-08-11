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

    @Test("duration producer authority is package-scoped in SwiftPM and file-private in direct-source builds")
    func producerAuthorityBuildModeFence() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Packages/NembraCore/Sources/NembraCore/RideSessionDurationEvidence.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("#if SWIFT_PACKAGE\n    /// Package tests and package-owned producers may construct snapshots directly."))
        #expect(source.contains("package init(\n        sessionID: UUID,\n        observedDurationNanoseconds: UInt64?"))
        #expect(source.contains("#else\n    /// Direct-source app builds keep snapshot minting in this file"))
        #expect(source.contains("fileprivate init(\n        sessionID: UUID,\n        observedDurationNanoseconds: UInt64?"))

        #expect(source.contains("package var snapshot: RideSessionDurationEvidenceSnapshot"))
        #expect(source.contains("fileprivate var snapshot: RideSessionDurationEvidenceSnapshot"))
        #expect(source.contains("private var projectedSnapshot: RideSessionDurationEvidenceSnapshot"))

        #expect(source.contains("package mutating func upsert("))
        #expect(source.contains("fileprivate mutating func upsert("))
        #expect(source.contains("private mutating func upsertValidated("))
        #expect(source.contains("try upsertValidated(segment)"))

        #expect(source.contains("package init(\n        sessionID: UUID,\n        beginsAfterUnobservedInterval: Bool = false"))
        #expect(source.contains("fileprivate init(\n        sessionID: UUID,\n        beginsAfterUnobservedInterval: Bool = false"))
    }
}
