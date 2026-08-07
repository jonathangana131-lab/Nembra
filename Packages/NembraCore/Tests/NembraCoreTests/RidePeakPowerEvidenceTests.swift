import Foundation
import Testing

@testable import NembraCore

@Suite("Ride-bound observed peak-power evidence")
struct RidePeakPowerEvidenceTests {
    private let sessionID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let otherSessionID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let epoch = Date(timeIntervalSinceReferenceDate: 10_000)

    private struct StoredFixture: Codable {
        var sessionID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        var rideContinuity: RideSessionContinuity = .uninterruptedProcess
        var beganAfterKnownObservationGap = false
        var vehicleIdentityKey = "sim-es80"
        var confirmedModeKey: String? = "drive"
        var identityAuthority = ObservedPowerEnvelopeScopeAuthority.simulatorQA.rawValue
        var evidenceAuthority = ObservedPowerEnvelopeEvidenceAuthority.simulatorQA.rawValue
        var powerWatts = 500.0
        var acceptedMeasurementCount = 1
        var peakCandidateMeasurementCount = 1
        var qualityRejectedMeasurementCount = 0
        var knownInterruptionCount = 0
        var observationContinuity: PeakPowerObservationContinuity =
            .noRecordedSelectedSourceEvidenceLoss
    }

    private func completedRide(
        sessionID: UUID? = nil,
        continuity: RideSessionContinuity = .uninterruptedProcess
    ) throws -> CompletedRideEvidence {
        try CompletedRideEvidence(
            sessionID: sessionID ?? self.sessionID,
            beganAtDate: epoch,
            confirmedAtDate: epoch.addingTimeInterval(5),
            endedAtDate: epoch.addingTimeInterval(120),
            startingOdometerKilometers: nil,
            endingOdometerKilometers: nil,
            qualityScreenedGPSDistanceMeters: 0,
            continuity: continuity
        )
    }

    private func simulatorScope(mode: String? = "drive") throws -> ObservedPowerEnvelopeScope {
        try .simulatorQA(vehicleIdentityKey: "sim-es80", confirmedModeKey: mode)
    }

    private func physicalScope(mode: String? = "drive") throws -> ObservedPowerEnvelopeScope {
        try .verifiedVehicleIdentity(
            vehicleIdentityKey: "physical-es80-opaque-id",
            confirmedModeKey: mode
        )
    }

    private func simulatorObservation(
        scope: ObservedPowerEnvelopeScope,
        watts: Double,
        sequence: UInt64,
        uptime: UInt64? = nil
    ) -> ObservedPowerEnvelopeObservation {
        .simulatorQA(
            scope: scope,
            powerWatts: watts,
            receiptSequenceNumber: sequence,
            observedAtUptimeNanoseconds: uptime ?? sequence,
            learningEligibility: .measurementOnly
        )
    }

    private func physicalObservation(
        scope: ObservedPowerEnvelopeScope,
        watts: Double,
        sequence: UInt64,
        uptime: UInt64? = nil
    ) -> ObservedPowerEnvelopeObservation {
        .verifiedVehicleMeasurement(
            scope: scope,
            powerWatts: watts,
            receiptSequenceNumber: sequence,
            observedAtUptimeNanoseconds: uptime ?? sequence,
            learningEligibility: .measurementOnly
        )
    }

    private func ridePeak(
        sessionID: UUID? = nil,
        scope: ObservedPowerEnvelopeScope? = nil,
        watts: Double = 500,
        beginsAfterKnownObservationGap: Bool = false
    ) throws -> RidePeakPowerEvidence {
        let selectedScope = try scope ?? simulatorScope()
        var accumulator = try RidePeakPowerEvidenceAccumulator(
            sessionID: sessionID ?? self.sessionID,
            scope: selectedScope,
            beginsAfterKnownObservationGap: beginsAfterKnownObservationGap
        )
        let observation: ObservedPowerEnvelopeObservation
        switch selectedScope.identityAuthority {
        case .simulatorQA:
            observation = simulatorObservation(
                scope: selectedScope,
                watts: watts,
                sequence: 1,
                uptime: 100
            )
        case .verifiedVehicleIdentity:
            observation = physicalObservation(
                scope: selectedScope,
                watts: watts,
                sequence: 1,
                uptime: 100
            )
        }
        _ = accumulator.record(observation)
        return try #require(accumulator.evidence)
    }

    private func encoded(_ fixture: StoredFixture) throws -> Data {
        try JSONEncoder().encode(fixture)
    }

    @Test("ride accumulator binds peak to immutable session, scope, and simulator authority")
    func accumulatorBindsSessionScopeAndAuthority() throws {
        let scope = try simulatorScope(mode: "sport")
        var accumulator = try RidePeakPowerEvidenceAccumulator(
            sessionID: sessionID,
            scope: scope
        )

        #expect(accumulator.evidence == nil)
        guard case .peakUpdated = accumulator.record(simulatorObservation(
            scope: scope,
            watts: 612,
            sequence: 1,
            uptime: 100
        )) else {
            Issue.record("Expected accepted simulator observation to establish ride peak")
            return
        }

        let bound = try #require(accumulator.evidence)
        #expect(bound.sessionID == sessionID)
        #expect(bound.scope == scope)
        #expect(bound.beganAfterKnownObservationGap == false)
        #expect(bound.peakEvidence.evidenceAuthority == .simulatorQA)
        #expect(bound.peakEvidence.peak.powerWatts == 612)
        #expect(bound.peakEvidence.continuity == .noRecordedSelectedSourceEvidenceLoss)
    }

    @Test("verified scope mechanically selects verified measurement authority")
    func verifiedScopeDerivesVerifiedAuthority() throws {
        let scope = try physicalScope(mode: "sport")
        var accumulator = try RidePeakPowerEvidenceAccumulator(
            sessionID: sessionID,
            scope: scope
        )

        #expect(accumulator.evidenceAuthority == .verifiedVehicleMeasurement)
        guard case .peakUpdated = accumulator.record(physicalObservation(
            scope: scope,
            watts: 540,
            sequence: 1
        )) else {
            Issue.record("Expected package-owned verified observation to establish ride peak")
            return
        }
        #expect(accumulator.evidence?.peakEvidence.evidenceAuthority == .verifiedVehicleMeasurement)
    }

    @Test("foreign scope cannot establish evidence or poison selected chronology")
    func foreignScopeIsolationSurvivesRideBinding() throws {
        let selected = try simulatorScope(mode: "sport")
        let foreign = try simulatorScope(mode: "eco")
        var accumulator = try RidePeakPowerEvidenceAccumulator(
            sessionID: sessionID,
            scope: selected
        )

        #expect(accumulator.record(simulatorObservation(
            scope: foreign,
            watts: 900,
            sequence: 99
        )) == .rejected(.scopeMismatch(expected: selected, actual: foreign)))
        #expect(accumulator.evidence == nil)

        guard case .peakUpdated = accumulator.record(simulatorObservation(
            scope: selected,
            watts: 400,
            sequence: 1
        )) else {
            Issue.record("Foreign scope must not consume selected-stream chronology")
            return
        }
        #expect(accumulator.evidence?.peakEvidence.peak.powerWatts == 400)
    }

    @Test("known initial gap remains distinct from later generic interruptions")
    func initialKnownGapRemainsBound() throws {
        let bound = try ridePeak(beginsAfterKnownObservationGap: true)

        #expect(bound.beganAfterKnownObservationGap)
        #expect(bound.peakEvidence.knownInterruptionCount == 1)
        #expect(bound.peakEvidence.continuity == .partialSelectedSourceEvidence)
    }

    @Test("completed projection rejects unrelated ride identity")
    func completedProjectionRejectsSessionMismatch() throws {
        let peak = try ridePeak()
        let otherRide = try completedRide(sessionID: otherSessionID)

        #expect(throws: CompletedRidePeakPowerEvidenceError.sessionMismatch) {
            try CompletedRidePeakPowerEvidence(completedRide: otherRide, ridePeak: peak)
        }
    }

    @Test("recovered ride cannot claim gap-free process-local peak observation")
    func recoveredRideRequiresRecordedInitialGap() throws {
        let recoveredRide = try completedRide(continuity: .recoveredCheckpoint)
        let gapFreePeak = try ridePeak()

        #expect(throws: CompletedRidePeakPowerEvidenceError.continuityMismatch) {
            try CompletedRidePeakPowerEvidence(
                completedRide: recoveredRide,
                ridePeak: gapFreePeak
            )
        }
    }

    @Test("recovered ride retains observed peak after explicit initial gap")
    func recoveredRideWithRecordedGapAccepted() throws {
        let recoveredRide = try completedRide(continuity: .recoveredCheckpoint)
        let peak = try ridePeak(beginsAfterKnownObservationGap: true)

        let durable = try CompletedRidePeakPowerEvidence(
            completedRide: recoveredRide,
            ridePeak: peak
        )

        #expect(durable.sessionID == sessionID)
        #expect(durable.rideContinuity == .recoveredCheckpoint)
        #expect(durable.beganAfterKnownObservationGap)
        #expect(durable.powerWatts == 500)
        #expect(durable.knownInterruptionCount == 1)
        #expect(durable.observationContinuity == .partialSelectedSourceEvidence)
    }

    @Test("durable projection preserves exact vehicle mode and authority provenance")
    func scopeAndAuthorityProvenancePersist() throws {
        let scope = try physicalScope(mode: "sport")
        let durable = try CompletedRidePeakPowerEvidence(
            completedRide: completedRide(),
            ridePeak: ridePeak(scope: scope, watts: 575)
        )

        #expect(durable.vehicleIdentityKey == "physical-es80-opaque-id")
        #expect(durable.confirmedModeKey == "sport")
        #expect(durable.identityAuthority == .verifiedVehicleIdentity)
        #expect(durable.evidenceAuthority == .verifiedVehicleMeasurement)
        #expect(durable.powerWatts == 575)
    }

    @Test("signed accepted evidence remains counted without becoming positive peak candidate")
    func signedEvidenceCountsRemainTruthful() throws {
        let scope = try simulatorScope()
        var accumulator = try RidePeakPowerEvidenceAccumulator(
            sessionID: sessionID,
            scope: scope
        )
        #expect(accumulator.record(simulatorObservation(
            scope: scope,
            watts: -80,
            sequence: 1
        )) == .acceptedWithoutPeakChange)
        guard case .peakUpdated = accumulator.record(simulatorObservation(
            scope: scope,
            watts: 520,
            sequence: 2
        )) else {
            Issue.record("Expected later nonnegative measurement to establish peak")
            return
        }
        let ridePeak = try #require(accumulator.evidence)
        let durable = try CompletedRidePeakPowerEvidence(
            completedRide: completedRide(),
            ridePeak: ridePeak
        )
        #expect(durable.acceptedMeasurementCount == 2)
        #expect(durable.peakCandidateMeasurementCount == 1)
        #expect(durable.powerWatts == 520)
    }

    @Test("durable projection strips process-local receipt chronology")
    func durableProjectionOmitsProcessLocalClocks() throws {
        let durable = try CompletedRidePeakPowerEvidence(
            completedRide: completedRide(),
            ridePeak: ridePeak()
        )
        let data = try JSONEncoder().encode(durable)
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        #expect(object["receiptSequenceNumber"] == nil)
        #expect(object["observedAtUptimeNanoseconds"] == nil)
        #expect(object["learningEligibility"] == nil)
        #expect(object["powerWatts"] != nil)
        #expect(object["vehicleIdentityKey"] != nil)
    }

    @Test("durable round trip preserves ride-bound peak evidence")
    func durableRoundTrip() throws {
        let original = try CompletedRidePeakPowerEvidence(
            completedRide: completedRide(),
            ridePeak: ridePeak(
                scope: physicalScope(mode: "sport"),
                watts: 575,
                beginsAfterKnownObservationGap: true
            )
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(
            CompletedRidePeakPowerEvidence.self,
            from: data
        )

        #expect(decoded == original)
    }

    @Test("decoded unknown identity authority cannot masquerade as durable peak")
    func decodedUnknownIdentityAuthorityRejected() throws {
        var fixture = StoredFixture()
        fixture.identityAuthority = "future-or-forged-authority"

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                CompletedRidePeakPowerEvidence.self,
                from: encoded(fixture)
            )
        }
    }

    @Test("decoded identity and measurement authorities must remain paired")
    func decodedCrossAuthorityPairRejected() throws {
        var fixture = StoredFixture()
        fixture.evidenceAuthority = ObservedPowerEnvelopeEvidenceAuthority.verifiedVehicleMeasurement.rawValue

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                CompletedRidePeakPowerEvidence.self,
                from: encoded(fixture)
            )
        }
    }

    @Test("decoded blank vehicle or confirmed mode identity fails closed")
    func decodedBlankScopeIdentityRejected() throws {
        var blankVehicle = StoredFixture()
        blankVehicle.vehicleIdentityKey = "   "
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                CompletedRidePeakPowerEvidence.self,
                from: encoded(blankVehicle)
            )
        }

        var blankMode = StoredFixture()
        blankMode.confirmedModeKey = "\n\t"
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                CompletedRidePeakPowerEvidence.self,
                from: encoded(blankMode)
            )
        }
    }

    @Test("decoded propulsion peak cannot be negative")
    func decodedNegativePeakRejected() throws {
        var fixture = StoredFixture()
        fixture.powerWatts = -1

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                CompletedRidePeakPowerEvidence.self,
                from: encoded(fixture)
            )
        }
    }

    @Test("decoded accepted and peak-candidate counts must be structurally possible")
    func decodedMeasurementCountsRejected() throws {
        var noAccepted = StoredFixture()
        noAccepted.acceptedMeasurementCount = 0
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                CompletedRidePeakPowerEvidence.self,
                from: encoded(noAccepted)
            )
        }

        var noCandidate = StoredFixture()
        noCandidate.peakCandidateMeasurementCount = 0
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                CompletedRidePeakPowerEvidence.self,
                from: encoded(noCandidate)
            )
        }

        var tooManyCandidates = StoredFixture()
        tooManyCandidates.acceptedMeasurementCount = 1
        tooManyCandidates.peakCandidateMeasurementCount = 2
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                CompletedRidePeakPowerEvidence.self,
                from: encoded(tooManyCandidates)
            )
        }
    }

    @Test("decoded no-loss continuity cannot hide recorded evidence loss")
    func decodedNoLossWithLossCountersRejected() throws {
        var fixture = StoredFixture()
        fixture.qualityRejectedMeasurementCount = 1

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                CompletedRidePeakPowerEvidence.self,
                from: encoded(fixture)
            )
        }
    }

    @Test("decoded partial continuity requires a recorded evidence-loss cause")
    func decodedPartialWithoutLossCountersRejected() throws {
        var fixture = StoredFixture()
        fixture.observationContinuity = .partialSelectedSourceEvidence

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                CompletedRidePeakPowerEvidence.self,
                from: encoded(fixture)
            )
        }
    }

    @Test("decoded initial-gap provenance requires an interruption")
    func decodedInitialGapWithoutInterruptionRejected() throws {
        var fixture = StoredFixture()
        fixture.beganAfterKnownObservationGap = true
        fixture.observationContinuity = .partialSelectedSourceEvidence
        fixture.qualityRejectedMeasurementCount = 1

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                CompletedRidePeakPowerEvidence.self,
                from: encoded(fixture)
            )
        }
    }

    @Test("decoded recovered ride requires explicit initial-gap provenance")
    func decodedRecoveredWithoutInitialGapRejected() throws {
        var fixture = StoredFixture()
        fixture.rideContinuity = .recoveredCheckpoint
        fixture.observationContinuity = .partialSelectedSourceEvidence
        fixture.knownInterruptionCount = 1
        fixture.beganAfterKnownObservationGap = false

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                CompletedRidePeakPowerEvidence.self,
                from: encoded(fixture)
            )
        }
    }

    @Test("joining durable peak against another ride fails closed")
    func validationSessionMismatchRejected() throws {
        let durable = try CompletedRidePeakPowerEvidence(
            completedRide: completedRide(),
            ridePeak: ridePeak()
        )
        let other = try completedRide(sessionID: otherSessionID)

        #expect(throws: CompletedRidePeakPowerEvidenceError.sessionMismatch) {
            try durable.validate(against: other)
        }
    }

    @Test("joining durable peak against changed ride continuity fails closed")
    func validationContinuityMismatchRejected() throws {
        let durable = try CompletedRidePeakPowerEvidence(
            completedRide: completedRide(),
            ridePeak: ridePeak()
        )
        let conflicting = try completedRide(continuity: .recoveredCheckpoint)

        #expect(throws: CompletedRidePeakPowerEvidenceError.continuityMismatch) {
            try durable.validate(against: conflicting)
        }
    }
}
