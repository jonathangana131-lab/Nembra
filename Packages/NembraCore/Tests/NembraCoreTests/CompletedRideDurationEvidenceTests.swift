import Foundation
import Testing

@testable import NembraCore

@Suite("Completed ride duration evidence")
struct CompletedRideDurationEvidenceTests {
    private let sessionID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let processID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let secondProcessID = UUID(uuidString: "66666666-7777-8888-9999-AAAAAAAAAAAA")!
    private let segmentID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private let secondSegmentID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!

    private func completedRide(
        sessionID: UUID? = nil,
        continuity: RideSessionContinuity = .uninterruptedProcess,
        beganAtDate: Date = Date(timeIntervalSinceReferenceDate: 1_000),
        confirmedAtDate: Date = Date(timeIntervalSinceReferenceDate: 1_010),
        endedAtDate: Date = Date(timeIntervalSinceReferenceDate: 1_200)
    ) throws -> CompletedRideEvidence {
        try CompletedRideEvidence(
            sessionID: sessionID ?? self.sessionID,
            beganAtDate: beganAtDate,
            confirmedAtDate: confirmedAtDate,
            endedAtDate: endedAtDate,
            startingOdometerKilometers: nil,
            endingOdometerKilometers: nil,
            qualityScreenedGPSDistanceMeters: 0,
            continuity: continuity
        )
    }

    private func segment(
        segmentID: UUID,
        processID: UUID,
        sequence: UInt64,
        from start: UInt64,
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

    private func completeDuration(
        nanoseconds: UInt64 = 120_000_000_000
    ) throws -> RideSessionDurationEvidenceSnapshot {
        var accumulator = RideSessionDurationEvidenceAccumulator(sessionID: sessionID)
        try accumulator.upsert(
            segment(
                segmentID: segmentID,
                processID: processID,
                sequence: 0,
                from: 1_000,
                through: 1_000 + nanoseconds,
                followsGap: false
            )
        )
        return accumulator.snapshot
    }

    private func partialDuration() throws -> RideSessionDurationEvidenceSnapshot {
        var accumulator = RideSessionDurationEvidenceAccumulator(sessionID: sessionID)
        try accumulator.upsert(
            segment(
                segmentID: segmentID,
                processID: processID,
                sequence: 0,
                from: 1_000,
                through: 1_100,
                followsGap: false
            )
        )
        try accumulator.upsert(
            segment(
                segmentID: secondSegmentID,
                processID: secondProcessID,
                sequence: 1,
                from: 5_000,
                through: 5_300,
                followsGap: true
            )
        )
        return accumulator.snapshot
    }

    @Test("uninterrupted completed ride keeps exact monotonic duration evidence")
    func completeUninterruptedDuration() throws {
        let ride = try completedRide()
        let duration = try completeDuration()

        let bound = try CompletedRideDurationEvidence(
            completedRide: ride,
            duration: duration
        )

        #expect(bound.sessionID == sessionID)
        #expect(bound.rideContinuity == .uninterruptedProcess)
        #expect(bound.observedDurationNanoseconds == 120_000_000_000)
        #expect(bound.coverage == .complete)
        #expect(bound.observationSegmentCount == 1)
        #expect(bound.isTrustedForProduction)
        try bound.validate(against: ride)
    }

    @Test("wall-clock reversal never changes observed duration")
    func wallClockReversalDoesNotBecomeDuration() throws {
        let ride = try completedRide(
            beganAtDate: Date(timeIntervalSinceReferenceDate: 5_000),
            confirmedAtDate: Date(timeIntervalSinceReferenceDate: 4_000),
            endedAtDate: Date(timeIntervalSinceReferenceDate: 3_000)
        )
        let duration = try completeDuration(nanoseconds: 90_000_000_000)

        let bound = try CompletedRideDurationEvidence(
            completedRide: ride,
            duration: duration
        )

        #expect(bound.observedDurationNanoseconds == 90_000_000_000)
        #expect(bound.coverage == .complete)
    }

    @Test("unavailable duration stays unavailable rather than fake zero")
    func unknownDurationIsPreserved() throws {
        let ride = try completedRide()
        let accumulator = RideSessionDurationEvidenceAccumulator(sessionID: sessionID)

        let bound = try CompletedRideDurationEvidence(
            completedRide: ride,
            duration: accumulator.snapshot
        )

        #expect(bound.observedDurationNanoseconds == nil)
        #expect(bound.coverage == .unknown)
        #expect(bound.observationSegmentCount == 0)
    }

    @Test("observed zero duration remains distinct from unavailable")
    func observedZeroIsPreserved() throws {
        let ride = try completedRide()
        var accumulator = RideSessionDurationEvidenceAccumulator(sessionID: sessionID)
        try accumulator.upsert(
            segment(
                segmentID: segmentID,
                processID: processID,
                sequence: 0,
                from: 1_000,
                through: 1_000,
                followsGap: false
            )
        )

        let bound = try CompletedRideDurationEvidence(
            completedRide: ride,
            duration: accumulator.snapshot
        )

        #expect(bound.observedDurationNanoseconds == 0)
        #expect(bound.coverage == .complete)
        #expect(bound.observationSegmentCount == 1)
    }

    @Test("session mismatch is rejected before history can join unrelated evidence")
    func sessionMismatchRejected() throws {
        let ride = try completedRide(sessionID: UUID())
        let duration = try completeDuration()

        #expect(throws: CompletedRideDurationEvidenceError.sessionMismatch) {
            try CompletedRideDurationEvidence(
                completedRide: ride,
                duration: duration
            )
        }
    }

    @Test("recovered ride can retain partial observed duration")
    func recoveredPartialDurationAccepted() throws {
        let ride = try completedRide(continuity: .recoveredCheckpoint)
        let duration = try partialDuration()

        let bound = try CompletedRideDurationEvidence(
            completedRide: ride,
            duration: duration
        )

        #expect(bound.coverage == .partial)
        #expect(bound.observedDurationNanoseconds == 400)
        #expect(bound.observationSegmentCount == 2)
    }

    @Test("recovered ride cannot claim complete process-local duration coverage")
    func recoveredCompleteDurationRejected() throws {
        let ride = try completedRide(continuity: .recoveredCheckpoint)
        let duration = try completeDuration()

        #expect(throws: CompletedRideDurationEvidenceError.invalidDurationEvidence) {
            try CompletedRideDurationEvidence(
                completedRide: ride,
                duration: duration
            )
        }
    }

    @Test("durable round trip preserves fields but generic decode drops production authority")
    func codableRoundTripDemotesAuthorityUntilTrustedRestore() throws {
        let ride = try completedRide()
        let original = try CompletedRideDurationEvidence(
            completedRide: ride,
            duration: partialDuration()
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(
            CompletedRideDurationEvidence.self,
            from: data
        )

        #expect(decoded.sessionID == original.sessionID)
        #expect(decoded.rideContinuity == original.rideContinuity)
        #expect(decoded.observedDurationNanoseconds == original.observedDurationNanoseconds)
        #expect(decoded.coverage == original.coverage)
        #expect(decoded.observationSegmentCount == original.observationSegmentCount)
        #expect(decoded.isTrustedForProduction == false)
        #expect(decoded != original)
        #expect(throws: CompletedRideDurationEvidenceError.invalidDurationEvidence) {
            try decoded.validate(against: ride)
        }

        let restored = try CompletedRideDurationEvidence.trustedRestored(
            decoded,
            matching: ride
        )
        #expect(restored.isTrustedForProduction)
        #expect(restored == original)
        try restored.validate(against: ride)
    }

    @Test("caller-authored matching JSON cannot validate as observed duration")
    func matchingCallerAuthoredJSONStaysUntrusted() throws {
        let ride = try completedRide()
        let data = Data(
            """
            {
              "sessionID": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
              "rideContinuity": "uninterruptedProcess",
              "observedDurationNanoseconds": 999999999999,
              "coverage": "complete",
              "observationSegmentCount": 1
            }
            """.utf8
        )

        let decoded = try JSONDecoder().decode(
            CompletedRideDurationEvidence.self,
            from: data
        )

        #expect(decoded.isTrustedForProduction == false)
        #expect(throws: CompletedRideDurationEvidenceError.invalidDurationEvidence) {
            try decoded.validate(against: ride)
        }
    }

    @Test("decoded unavailable evidence cannot claim coverage or segments")
    func malformedUnavailablePersistenceRejected() {
        let data = Data(
            """
            {
              "sessionID": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
              "rideContinuity": "uninterruptedProcess",
              "coverage": "partial",
              "observationSegmentCount": 1
            }
            """.utf8
        )

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(CompletedRideDurationEvidence.self, from: data)
        }
    }

    @Test("decoded observed duration cannot claim unknown coverage")
    func malformedObservedUnknownPersistenceRejected() {
        let data = Data(
            """
            {
              "sessionID": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
              "rideContinuity": "uninterruptedProcess",
              "observedDurationNanoseconds": 1,
              "coverage": "unknown",
              "observationSegmentCount": 1
            }
            """.utf8
        )

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(CompletedRideDurationEvidence.self, from: data)
        }
    }

    @Test("decoded observed duration requires at least one observation segment")
    func malformedObservedSegmentCountRejected() {
        let data = Data(
            """
            {
              "sessionID": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
              "rideContinuity": "uninterruptedProcess",
              "observedDurationNanoseconds": 1,
              "coverage": "complete",
              "observationSegmentCount": 0
            }
            """.utf8
        )

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(CompletedRideDurationEvidence.self, from: data)
        }
    }

    @Test("decoded recovered ride cannot fabricate complete duration coverage")
    func malformedRecoveredCompletePersistenceRejected() {
        let data = Data(
            """
            {
              "sessionID": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
              "rideContinuity": "recoveredCheckpoint",
              "observedDurationNanoseconds": 1,
              "coverage": "complete",
              "observationSegmentCount": 1
            }
            """.utf8
        )

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(CompletedRideDurationEvidence.self, from: data)
        }
    }

    @Test("joining against a different completed ride fails closed")
    func validationSessionMismatchRejected() throws {
        let bound = try CompletedRideDurationEvidence(
            completedRide: completedRide(),
            duration: completeDuration()
        )
        let other = try completedRide(sessionID: UUID())

        #expect(throws: CompletedRideDurationEvidenceError.sessionMismatch) {
            try bound.validate(against: other)
        }
    }

    @Test("joining against changed ride continuity fails closed")
    func validationContinuityMismatchRejected() throws {
        let bound = try CompletedRideDurationEvidence(
            completedRide: completedRide(),
            duration: completeDuration()
        )
        let conflicting = try completedRide(continuity: .recoveredCheckpoint)

        #expect(throws: CompletedRideDurationEvidenceError.continuityMismatch) {
            try bound.validate(against: conflicting)
        }
    }
}