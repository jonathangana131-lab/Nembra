import Foundation
import Testing

@testable import NembraCore

@Suite("Ride-bound observed peak-power evidence")
struct RidePeakPowerEvidenceTests {
    private let sessionID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let otherSessionID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let epoch = Date(timeIntervalSinceReferenceDate: 10_000)

    private struct StoredFixture: Codable {
        var schemaVersion = CompletedRidePeakPowerCheckpoint.currentSchemaVersion
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

    private func simulatorScope(
        vehicle: String = "sim-es80",
        mode: String? = "drive"
    ) throws -> ObservedPowerEnvelopeScope {
        try .simulatorQA(vehicleIdentityKey: vehicle, confirmedModeKey: mode)
    }

    private func physicalScope(
        vehicle: String = "physical-es80-opaque-id",
        mode: String? = "drive"
    ) throws -> ObservedPowerEnvelopeScope {
        try .verifiedVehicleIdentity(
            vehicleIdentityKey: vehicle,
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

        switch selectedScope.identityAuthority {
        case .simulatorQA:
            _ = accumulator.record(simulatorObservation(
                scope: selectedScope,
                watts: watts,
                sequence: 1,
                uptime: 100
            ))
        case .verifiedVehicleIdentity:
            _ = accumulator.record(physicalObservation(
                scope: selectedScope,
                watts: watts,
                sequence: 1,
                uptime: 100
            ))
        }
        return try #require(accumulator.evidence)
    }

    private func completedPeak(
        ride: CompletedRideEvidence? = nil,
        scope: ObservedPowerEnvelopeScope? = nil,
        watts: Double = 500,
        beginsAfterKnownObservationGap: Bool = false
    ) throws -> CompletedRidePeakPowerEvidence {
        let selectedRide = try ride ?? completedRide()
        return try CompletedRidePeakPowerEvidence(
            completedRide: selectedRide,
            ridePeak: ridePeak(
                sessionID: selectedRide.sessionID,
                scope: scope,
                watts: watts,
                beginsAfterKnownObservationGap: beginsAfterKnownObservationGap
            )
        )
    }

    private func encoded(_ fixture: StoredFixture) throws -> Data {
        try JSONEncoder().encode(fixture)
    }

    private func decodedCheckpoint(
        _ fixture: StoredFixture
    ) throws -> CompletedRidePeakPowerCheckpoint {
        try JSONDecoder().decode(
            CompletedRidePeakPowerCheckpoint.self,
            from: encoded(fixture)
        )
    }

    @Test("ride accumulator binds peak to immutable session, scope, and simulator authority")
    func accumulatorBindsSessionScopeAndAuthority() throws {
        let scope = try simulatorScope(mode: "sport")
        var accumulator = try RidePeakPowerEvidenceAccumulator(sessionID: sessionID, scope: scope)
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
        #expect(bound.peakEvidence.evidenceAuthority == .simulatorQA)
        #expect(bound.peakEvidence.peak.powerWatts == 612)
        #expect(bound.peakEvidence.continuity == .noRecordedSelectedSourceEvidenceLoss)
    }

    @Test("verified scope mechanically selects verified measurement authority")
    func verifiedScopeDerivesVerifiedAuthority() throws {
        let scope = try physicalScope(mode: "sport")
        var accumulator = try RidePeakPowerEvidenceAccumulator(sessionID: sessionID, scope: scope)
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
        var accumulator = try RidePeakPowerEvidenceAccumulator(sessionID: sessionID, scope: selected)

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
        #expect(throws: CompletedRidePeakPowerEvidenceError.sessionMismatch) {
            try CompletedRidePeakPowerEvidence(
                completedRide: completedRide(sessionID: otherSessionID),
                ridePeak: peak
            )
        }
    }

    @Test("recovered ride cannot claim gap-free process-local peak observation")
    func recoveredRideRequiresRecordedInitialGap() throws {
        let recovered = try completedRide(continuity: .recoveredCheckpoint)
        #expect(throws: CompletedRidePeakPowerEvidenceError.continuityMismatch) {
            try CompletedRidePeakPowerEvidence(
                completedRide: recovered,
                ridePeak: ridePeak(sessionID: recovered.sessionID)
            )
        }
    }

    @Test("recovered ride retains observed peak after explicit initial gap")
    func recoveredRideWithRecordedGapAccepted() throws {
        let recovered = try completedRide(continuity: .recoveredCheckpoint)
        let durable = try completedPeak(
            ride: recovered,
            beginsAfterKnownObservationGap: true
        )
        #expect(durable.rideContinuity == .recoveredCheckpoint)
        #expect(durable.beganAfterKnownObservationGap)
        #expect(durable.powerWatts == 500)
        #expect(durable.knownInterruptionCount == 1)
        #expect(durable.observationContinuity == .partialSelectedSourceEvidence)
    }

    @Test("durable projection preserves exact vehicle mode and authority provenance")
    func scopeAndAuthorityProvenancePersist() throws {
        let durable = try completedPeak(scope: physicalScope(mode: "sport"), watts: 575)
        #expect(durable.vehicleIdentityKey == "physical-es80-opaque-id")
        #expect(durable.confirmedModeKey == "sport")
        #expect(durable.identityAuthority == .verifiedVehicleIdentity)
        #expect(durable.evidenceAuthority == .verifiedVehicleMeasurement)
        #expect(durable.powerWatts == 575)
    }

    @Test("signed accepted evidence remains counted without becoming positive peak candidate")
    func signedEvidenceCountsRemainTruthful() throws {
        let scope = try simulatorScope()
        var accumulator = try RidePeakPowerEvidenceAccumulator(sessionID: sessionID, scope: scope)
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

        let durable = try CompletedRidePeakPowerEvidence(
            completedRide: completedRide(),
            ridePeak: #require(accumulator.evidence)
        )
        #expect(durable.acceptedMeasurementCount == 2)
        #expect(durable.peakCandidateMeasurementCount == 1)
        #expect(durable.powerWatts == 520)
    }

    @Test("durable checkpoint strips process-local receipt chronology")
    func durableProjectionOmitsProcessLocalClocks() throws {
        let checkpoint = try CompletedRidePeakPowerCheckpoint.simulatorQA(
            from: completedPeak()
        )
        let data = try JSONEncoder().encode(checkpoint)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["receiptSequenceNumber"] == nil)
        #expect(object["observedAtUptimeNanoseconds"] == nil)
        #expect(object["learningEligibility"] == nil)
        #expect(object["powerWatts"] != nil)
        #expect(object["vehicleIdentityKey"] != nil)
    }

    @Test("verified durable bytes restore only through package-sealed trusted ride and scope")
    func verifiedCheckpointRoundTrip() throws {
        let ride = try completedRide()
        let scope = try physicalScope(mode: "sport")
        let original = try completedPeak(
            ride: ride,
            scope: scope,
            watts: 575,
            beginsAfterKnownObservationGap: true
        )
        let checkpoint = try CompletedRidePeakPowerCheckpoint.verifiedVehicleMeasurements(
            from: original
        )
        let persistedData = try JSONEncoder().encode(checkpoint)
        let restored = try CompletedRidePeakPowerCheckpoint.restoreVerifiedVehicleMeasurement(
            fromPersistedData: persistedData,
            completedRide: ride,
            expectedScope: scope
        )
        #expect(restored == original)
    }

    @Test("generic public decode cannot mint forged exact-scope verified authority")
    func forgedVerifiedCheckpointCannotUsePublicDecode() throws {
        var fixture = StoredFixture()
        fixture.vehicleIdentityKey = "physical-es80-opaque-id"
        fixture.confirmedModeKey = "sport"
        fixture.identityAuthority = ObservedPowerEnvelopeScopeAuthority.verifiedVehicleIdentity.rawValue
        fixture.evidenceAuthority = ObservedPowerEnvelopeEvidenceAuthority.verifiedVehicleMeasurement.rawValue
        fixture.powerWatts = 999

        #expect(throws: DecodingError.self) {
            try decodedCheckpoint(fixture)
        }
    }

    @Test("package-sealed verified persisted restore still requires exact trusted scope")
    func verifiedPersistedRestoreRejectsScopeMismatch() throws {
        let ride = try completedRide()
        let scope = try physicalScope(mode: "sport")
        let checkpoint = try CompletedRidePeakPowerCheckpoint.verifiedVehicleMeasurements(
            from: completedPeak(ride: ride, scope: scope, watts: 575)
        )
        let persistedData = try JSONEncoder().encode(checkpoint)

        #expect(throws: CompletedRidePeakPowerEvidenceError.scopeMismatch) {
            try CompletedRidePeakPowerCheckpoint.restoreVerifiedVehicleMeasurement(
                fromPersistedData: persistedData,
                completedRide: ride,
                expectedScope: physicalScope(mode: "eco")
            )
        }
    }

    @Test("public simulator checkpoint creation refuses verified evidence")
    func simulatorCheckpointCannotRelabelVerifiedEvidence() throws {
        let physical = try completedPeak(scope: physicalScope())
        #expect(throws: CompletedRidePeakPowerEvidenceError.authorityMismatch) {
            try CompletedRidePeakPowerCheckpoint.simulatorQA(from: physical)
        }
    }

    @Test("verified restore requires exact independently trusted scope")
    func verifiedRestoreRejectsScopeMismatch() throws {
        let ride = try completedRide()
        let scope = try physicalScope(mode: "sport")
        let evidence = try completedPeak(ride: ride, scope: scope)
        let checkpoint = try CompletedRidePeakPowerCheckpoint.verifiedVehicleMeasurements(
            from: evidence
        )

        #expect(throws: CompletedRidePeakPowerEvidenceError.scopeMismatch) {
            try checkpoint.restoredVerifiedVehicleMeasurement(
                completedRide: ride,
                expectedScope: physicalScope(mode: "eco")
            )
        }
    }

    @Test("simulator checkpoint round trip restores only against exact simulator scope")
    func simulatorCheckpointRoundTrip() throws {
        let ride = try completedRide()
        let scope = try simulatorScope(mode: "drive")
        let original = try completedPeak(ride: ride, scope: scope, watts: 505)
        let checkpoint = try CompletedRidePeakPowerCheckpoint.simulatorQA(from: original)
        let decoded = try JSONDecoder().decode(
            CompletedRidePeakPowerCheckpoint.self,
            from: JSONEncoder().encode(checkpoint)
        )
        #expect(try decoded.restoredSimulatorQA(completedRide: ride, expectedScope: scope) == original)
    }

    @Test("checkpoint schema is explicit and unknown versions fail closed")
    func checkpointSchemaVersionIsExplicit() throws {
        let checkpoint = try CompletedRidePeakPowerCheckpoint.simulatorQA(
            from: completedPeak()
        )
        #expect(checkpoint.schemaVersion == CompletedRidePeakPowerCheckpoint.currentSchemaVersion)

        var fixture = StoredFixture()
        fixture.schemaVersion = CompletedRidePeakPowerCheckpoint.currentSchemaVersion + 1
        #expect(throws: DecodingError.self) { try decodedCheckpoint(fixture) }
    }

    @Test("decoded unknown identity authority is rejected as malformed checkpoint")
    func decodedUnknownIdentityAuthorityRejected() throws {
        var fixture = StoredFixture()
        fixture.identityAuthority = "future-or-forged-authority"
        #expect(throws: DecodingError.self) { try decodedCheckpoint(fixture) }
    }

    @Test("decoded identity and measurement authorities must remain paired")
    func decodedCrossAuthorityPairRejected() throws {
        var fixture = StoredFixture()
        fixture.evidenceAuthority = ObservedPowerEnvelopeEvidenceAuthority.verifiedVehicleMeasurement.rawValue
        #expect(throws: DecodingError.self) { try decodedCheckpoint(fixture) }
    }

    @Test("decoded blank vehicle or confirmed mode identity fails closed")
    func decodedBlankScopeIdentityRejected() throws {
        var blankVehicle = StoredFixture()
        blankVehicle.vehicleIdentityKey = "   "
        #expect(throws: DecodingError.self) { try decodedCheckpoint(blankVehicle) }

        var blankMode = StoredFixture()
        blankMode.confirmedModeKey = "\n\t"
        #expect(throws: DecodingError.self) { try decodedCheckpoint(blankMode) }
    }

    @Test("decoded propulsion peak cannot be negative")
    func decodedNegativePeakRejected() throws {
        var fixture = StoredFixture()
        fixture.powerWatts = -1
        #expect(throws: DecodingError.self) { try decodedCheckpoint(fixture) }
    }

    @Test("decoded accepted and peak-candidate counts must be structurally possible")
    func decodedMeasurementCountsRejected() throws {
        var noAccepted = StoredFixture()
        noAccepted.acceptedMeasurementCount = 0
        #expect(throws: DecodingError.self) { try decodedCheckpoint(noAccepted) }

        var noCandidate = StoredFixture()
        noCandidate.peakCandidateMeasurementCount = 0
        #expect(throws: DecodingError.self) { try decodedCheckpoint(noCandidate) }

        var tooManyCandidates = StoredFixture()
        tooManyCandidates.peakCandidateMeasurementCount = 2
        #expect(throws: DecodingError.self) { try decodedCheckpoint(tooManyCandidates) }
    }

    @Test("decoded no-loss continuity cannot hide recorded evidence loss")
    func decodedNoLossWithLossCountersRejected() throws {
        var fixture = StoredFixture()
        fixture.qualityRejectedMeasurementCount = 1
        #expect(throws: DecodingError.self) { try decodedCheckpoint(fixture) }
    }

    @Test("decoded partial continuity requires a recorded evidence-loss cause")
    func decodedPartialWithoutLossCountersRejected() throws {
        var fixture = StoredFixture()
        fixture.observationContinuity = .partialSelectedSourceEvidence
        #expect(throws: DecodingError.self) { try decodedCheckpoint(fixture) }
    }

    @Test("decoded initial-gap provenance requires an interruption")
    func decodedInitialGapWithoutInterruptionRejected() throws {
        var fixture = StoredFixture()
        fixture.beganAfterKnownObservationGap = true
        fixture.observationContinuity = .partialSelectedSourceEvidence
        fixture.qualityRejectedMeasurementCount = 1
        #expect(throws: DecodingError.self) { try decodedCheckpoint(fixture) }
    }

    @Test("decoded recovered ride requires explicit initial-gap provenance")
    func decodedRecoveredWithoutInitialGapRejected() throws {
        var fixture = StoredFixture()
        fixture.rideContinuity = .recoveredCheckpoint
        fixture.observationContinuity = .partialSelectedSourceEvidence
        fixture.knownInterruptionCount = 1
        #expect(throws: DecodingError.self) { try decodedCheckpoint(fixture) }
    }

    @Test("joining durable peak against another ride fails closed")
    func validationSessionMismatchRejected() throws {
        let durable = try completedPeak()
        #expect(throws: CompletedRidePeakPowerEvidenceError.sessionMismatch) {
            try durable.validate(against: completedRide(sessionID: otherSessionID))
        }
    }

    @Test("joining durable peak against changed ride continuity fails closed")
    func validationContinuityMismatchRejected() throws {
        let durable = try completedPeak()
        #expect(throws: CompletedRidePeakPowerEvidenceError.continuityMismatch) {
            try durable.validate(against: completedRide(continuity: .recoveredCheckpoint))
        }
    }
}
