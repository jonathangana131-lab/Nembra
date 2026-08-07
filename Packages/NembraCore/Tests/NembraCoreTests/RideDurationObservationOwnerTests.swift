import Foundation
import Testing

@testable import NembraCore

@Suite("Ride duration lifecycle observation owner")
struct RideDurationObservationOwnerTests {
    @Test("one contiguous observed ride remains complete")
    func contiguousRide() throws {
        let sessionID = UUID()
        let processID = UUID()
        var owner = RideDurationObservationOwner()

        try owner.begin(
            sessionID: sessionID,
            processGenerationID: processID,
            atUptimeNanoseconds: 100
        )
        try owner.observe(sessionID: sessionID, atUptimeNanoseconds: 600)
        let snapshot = try owner.end(sessionID: sessionID, atUptimeNanoseconds: 1_100)

        #expect(snapshot.sessionID == sessionID)
        #expect(snapshot.observedDurationNanoseconds == 1_000)
        #expect(snapshot.coverage == .complete)
        #expect(snapshot.observationSegmentCount == 1)
        #expect(owner.activeSessionID == nil)
        #expect(owner.snapshot == nil)
    }

    @Test("explicit gap never becomes elapsed duration")
    func gapStaysPartial() throws {
        let sessionID = UUID()
        let processID = UUID()
        var owner = RideDurationObservationOwner()

        try owner.begin(
            sessionID: sessionID,
            processGenerationID: processID,
            atUptimeNanoseconds: 100
        )
        try owner.markObservationGap(sessionID: sessionID, atUptimeNanoseconds: 600)
        try owner.resumeObservation(
            sessionID: sessionID,
            processGenerationID: processID,
            atUptimeNanoseconds: 1_600
        )
        let snapshot = try owner.end(sessionID: sessionID, atUptimeNanoseconds: 2_100)

        #expect(snapshot.observedDurationNanoseconds == 1_000)
        #expect(snapshot.coverage == .partial)
        #expect(snapshot.observationSegmentCount == 2)
        guard case let .observed(value) = RideDurationCockpitState(snapshot: snapshot) else {
            Issue.record("Expected partial observed cockpit value")
            return
        }
        #expect(value.role == .partialObserved)
        #expect(value.wholeObservedSeconds == 0)
    }

    @Test("rejected observation during a gap does not consume resume chronology")
    func rejectedGapObservationIsAtomic() throws {
        let sessionID = UUID()
        let processID = UUID()
        var owner = RideDurationObservationOwner()

        try owner.begin(
            sessionID: sessionID,
            processGenerationID: processID,
            atUptimeNanoseconds: 100
        )
        try owner.markObservationGap(sessionID: sessionID, atUptimeNanoseconds: 200)
        let beforeRejectedObservation = owner.snapshot

        #expect(throws: RideDurationObservationOwnerError.noActiveSession) {
            try owner.observe(sessionID: sessionID, atUptimeNanoseconds: 300)
        }
        #expect(owner.snapshot == beforeRejectedObservation)

        // The rejected callback must not advance the chronology floor. This exact
        // timestamp is still a legitimate boundary for the fresh observed segment.
        try owner.resumeObservation(
            sessionID: sessionID,
            processGenerationID: processID,
            atUptimeNanoseconds: 300
        )
        let snapshot = try owner.end(sessionID: sessionID, atUptimeNanoseconds: 400)

        #expect(snapshot.observedDurationNanoseconds == 200)
        #expect(snapshot.coverage == .partial)
        #expect(snapshot.observationSegmentCount == 2)
    }

    @Test("recovered attachment is partial from its first observed segment")
    func recoveredAttachment() throws {
        let sessionID = UUID()
        var owner = RideDurationObservationOwner()

        try owner.begin(
            sessionID: sessionID,
            processGenerationID: UUID(),
            atUptimeNanoseconds: 10_000,
            beginsAfterUnobservedInterval: true
        )
        let snapshot = try owner.end(sessionID: sessionID, atUptimeNanoseconds: 10_500)

        #expect(snapshot.observedDurationNanoseconds == 500)
        #expect(snapshot.coverage == .partial)
        #expect(snapshot.observationSegmentCount == 1)
    }

    @Test("stale callbacks and foreign sessions fail without extending evidence")
    func chronologyAndSessionIsolation() throws {
        let sessionID = UUID()
        var owner = RideDurationObservationOwner()
        try owner.begin(
            sessionID: sessionID,
            processGenerationID: UUID(),
            atUptimeNanoseconds: 100
        )
        try owner.observe(sessionID: sessionID, atUptimeNanoseconds: 200)
        let before = owner.snapshot

        #expect(throws: RideDurationObservationOwnerError.nonMonotonicObservation) {
            try owner.observe(sessionID: sessionID, atUptimeNanoseconds: 200)
        }
        #expect(throws: RideDurationObservationOwnerError.sessionMismatch) {
            try owner.observe(sessionID: UUID(), atUptimeNanoseconds: 300)
        }
        #expect(owner.snapshot == before)
    }

    @Test("gap boundary cannot be resumed twice")
    func resumeRequiresGap() throws {
        let sessionID = UUID()
        var owner = RideDurationObservationOwner()
        try owner.begin(
            sessionID: sessionID,
            processGenerationID: UUID(),
            atUptimeNanoseconds: 100
        )

        #expect(throws: RideDurationObservationOwnerError.sessionAlreadyActive) {
            try owner.resumeObservation(
                sessionID: sessionID,
                processGenerationID: UUID(),
                atUptimeNanoseconds: 200
            )
        }
    }
}
