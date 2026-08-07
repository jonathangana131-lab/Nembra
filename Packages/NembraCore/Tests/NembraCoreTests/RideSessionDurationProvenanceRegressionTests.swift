import Foundation
import Testing

@testable import NembraCore

@Suite("Ride session duration provenance regressions")
struct RideSessionDurationProvenanceRegressionTests {
    private let sessionID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let firstProcessID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let secondProcessID = UUID(uuidString: "66666666-7777-8888-9999-AAAAAAAAAAAA")!
    private let firstSegmentID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private let secondSegmentID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
    private let thirdSegmentID = UUID(uuidString: "30000000-0000-0000-0000-000000000003")!

    private func segment(
        segmentID: UUID,
        processID: UUID,
        sequence: UInt64,
        from start: UInt64 = 100,
        through end: UInt64,
        followsGap: Bool
    ) throws -> RideSessionDurationObservedSegment {
        try RideSessionDurationObservedSegment(
            sessionID: sessionID,
            segmentID: segmentID,
            processGenerationID: processID,
            sequenceNumber: sequence,
            observedFromUptimeNanoseconds: start,
            observedThroughUptimeNanoseconds: end,
            followsUnobservedInterval: followsGap
        )
    }

    @Test("a sealed earlier segment cannot grow after a later observation segment begins")
    func sealedSegmentCannotExtend() throws {
        var accumulator = RideSessionDurationEvidenceAccumulator(sessionID: sessionID)
        try accumulator.upsert(
            segment(
                segmentID: firstSegmentID,
                processID: firstProcessID,
                sequence: 0,
                through: 200,
                followsGap: false
            )
        )
        try accumulator.upsert(
            segment(
                segmentID: secondSegmentID,
                processID: firstProcessID,
                sequence: 1,
                from: 500,
                through: 600,
                followsGap: true
            )
        )
        let before = accumulator.snapshot

        #expect(throws: RideSessionDurationEvidenceError.closedSegmentCannotExtend) {
            try accumulator.upsert(
                segment(
                    segmentID: firstSegmentID,
                    processID: firstProcessID,
                    sequence: 0,
                    through: 250,
                    followsGap: false
                )
            )
        }
        #expect(accumulator.snapshot == before)
    }

    @Test("a retired process generation cannot reappear after relaunch")
    func retiredProcessGenerationCannotReturn() throws {
        var accumulator = RideSessionDurationEvidenceAccumulator(sessionID: sessionID)
        try accumulator.upsert(
            segment(
                segmentID: firstSegmentID,
                processID: firstProcessID,
                sequence: 0,
                through: 200,
                followsGap: false
            )
        )
        try accumulator.upsert(
            segment(
                segmentID: secondSegmentID,
                processID: secondProcessID,
                sequence: 1,
                through: 300,
                followsGap: true
            )
        )
        let before = accumulator.snapshot

        #expect(throws: RideSessionDurationEvidenceError.retiredProcessGenerationReused) {
            try accumulator.upsert(
                segment(
                    segmentID: thirdSegmentID,
                    processID: firstProcessID,
                    sequence: 2,
                    through: 400,
                    followsGap: true
                )
            )
        }
        #expect(accumulator.snapshot == before)
    }
}
