import Foundation
import Testing
@testable import NembraCore

@Suite("Peak power evidence")
struct PeakPowerEvidenceTests {
    private func simulatorScope(mode: String? = nil) throws -> ObservedPowerEnvelopeScope {
        try .simulatorQA(vehicleIdentityKey: "sim-es80", confirmedModeKey: mode)
    }

    private func physicalScope(mode: String? = nil) throws -> ObservedPowerEnvelopeScope {
        try .verifiedVehicleIdentity(
            vehicleIdentityKey: "physical-es80-opaque-id",
            confirmedModeKey: mode
        )
    }

    private func simulatorObservation(
        watts: Double,
        sequence: UInt64,
        uptime: UInt64? = nil,
        scope: ObservedPowerEnvelopeScope? = nil,
        eligibility: ObservedPowerEnvelopeLearningEligibility = .measurementOnly
    ) -> ObservedPowerEnvelopeObservation {
        .simulatorQA(
            scope: scope ?? (try! simulatorScope()),
            powerWatts: watts,
            receiptSequenceNumber: sequence,
            observedAtUptimeNanoseconds: uptime ?? sequence,
            learningEligibility: eligibility
        )
    }

    private func physicalObservation(
        watts: Double,
        sequence: UInt64,
        uptime: UInt64? = nil,
        scope: ObservedPowerEnvelopeScope? = nil,
        eligibility: ObservedPowerEnvelopeLearningEligibility = .measurementOnly
    ) -> ObservedPowerEnvelopeObservation {
        .verifiedVehicleMeasurement(
            scope: scope ?? (try! physicalScope()),
            powerWatts: watts,
            receiptSequenceNumber: sequence,
            observedAtUptimeNanoseconds: uptime ?? sequence,
            learningEligibility: eligibility
        )
    }

    @Test("simulator peak preserves explicit simulator authority")
    func simulatorPeakPreservesAuthority() throws {
        let scope = try simulatorScope(mode: "sport")
        var accumulator = try PeakPowerEvidenceAccumulator.simulatorQA(scope: scope)

        let result = accumulator.record(simulatorObservation(
            watts: 612,
            sequence: 1,
            scope: scope
        ))

        guard case let .peakUpdated(measurement) = result else {
            Issue.record("Expected first accepted propulsion sample to establish peak")
            return
        }
        #expect(measurement.powerWatts == 612)
        #expect(measurement.evidenceAuthority == .simulatorQA)
        #expect(measurement.scope == scope)

        let evidence = try #require(accumulator.evidence)
        #expect(evidence.evidenceAuthority == .simulatorQA)
        #expect(evidence.continuity == .noRecordedSelectedSourceEvidenceLoss)
    }

    @Test("accumulator construction rejects scope authority mismatch")
    func constructionRejectsScopeAuthorityMismatch() throws {
        #expect(throws: PeakPowerEvidenceAccumulatorError.scopeAuthorityMismatch(
            expected: .simulatorQA,
            actual: .verifiedVehicleIdentity
        )) {
            try PeakPowerEvidenceAccumulator.simulatorQA(scope: physicalScope())
        }

        #expect(throws: PeakPowerEvidenceAccumulatorError.scopeAuthorityMismatch(
            expected: .verifiedVehicleIdentity,
            actual: .simulatorQA
        )) {
            try PeakPowerEvidenceAccumulator.verifiedVehicleMeasurements(scope: simulatorScope())
        }
    }

    @Test("simulator evidence cannot enter a verified physical peak stream")
    func authorityMismatchDoesNotConsumePhysicalChronology() throws {
        let scope = try physicalScope()
        var accumulator = try PeakPowerEvidenceAccumulator.verifiedVehicleMeasurements(scope: scope)

        #expect(accumulator.record(.simulatorQA(
            scope: scope,
            powerWatts: 900,
            receiptSequenceNumber: 50,
            observedAtUptimeNanoseconds: 50,
            learningEligibility: .measurementOnly
        )) == .rejected(.evidenceAuthorityMismatch(
            expected: .verifiedVehicleMeasurement,
            actual: .simulatorQA
        )))

        guard case let .peakUpdated(measurement) = accumulator.record(physicalObservation(
            watts: 500,
            sequence: 1,
            scope: scope
        )) else {
            Issue.record("Authority mismatch must not consume verified-stream chronology")
            return
        }
        #expect(measurement.powerWatts == 500)
        #expect(measurement.evidenceAuthority == .verifiedVehicleMeasurement)
    }

    @Test("cross vehicle and confirmed-mode mismatch fail before chronology")
    func scopeMismatchDoesNotConsumeChronology() throws {
        let sport = try physicalScope(mode: "sport")
        let eco = try physicalScope(mode: "eco")
        var accumulator = try PeakPowerEvidenceAccumulator.verifiedVehicleMeasurements(scope: sport)

        #expect(accumulator.record(physicalObservation(
            watts: 900,
            sequence: 99,
            scope: eco
        )) == .rejected(.scopeMismatch(expected: sport, actual: eco)))

        guard case .peakUpdated = accumulator.record(physicalObservation(
            watts: 500,
            sequence: 1,
            scope: sport
        )) else {
            Issue.record("Scope mismatch must not consume selected-stream chronology")
            return
        }
    }

    @Test("highest accepted nonnegative measurement wins without display interpolation")
    func highestAcceptedMeasurementWins() throws {
        let scope = try simulatorScope()
        var accumulator = try PeakPowerEvidenceAccumulator.simulatorQA(scope: scope)

        guard case .peakUpdated = accumulator.record(simulatorObservation(watts: 410, sequence: 1)) else {
            Issue.record("Expected initial peak")
            return
        }
        #expect(accumulator.record(simulatorObservation(watts: 390, sequence: 2)) == .acceptedWithoutPeakChange)
        guard case let .peakUpdated(raised) = accumulator.record(simulatorObservation(watts: 525, sequence: 3)) else {
            Issue.record("Expected stronger accepted observation to raise peak")
            return
        }
        #expect(raised.powerWatts == 525)

        let evidence = try #require(accumulator.evidence)
        #expect(evidence.peak.powerWatts == 525)
        #expect(evidence.acceptedMeasurementCount == 3)
        #expect(evidence.peakCandidateMeasurementCount == 3)
    }

    @Test("measurement-only evidence can still be a real observed peak")
    func envelopeLearningEligibilityDoesNotRewriteMeasurementTruth() throws {
        var accumulator = try PeakPowerEvidenceAccumulator.simulatorQA(scope: simulatorScope())

        guard case let .peakUpdated(measurement) = accumulator.record(simulatorObservation(
            watts: 640,
            sequence: 1,
            eligibility: .measurementOnly
        )) else {
            Issue.record("Calibration eligibility must not erase legitimate measurement evidence")
            return
        }
        #expect(measurement.powerWatts == 640)
    }

    @Test("finite negative power remains accepted but never becomes propulsion peak")
    func negativePowerIsAcceptedWithoutPositivePeak() throws {
        var accumulator = try PeakPowerEvidenceAccumulator.simulatorQA(scope: simulatorScope())

        #expect(accumulator.record(simulatorObservation(watts: -120, sequence: 1)) == .acceptedWithoutPeakChange)
        #expect(accumulator.evidence == nil)

        guard case .peakUpdated = accumulator.record(simulatorObservation(watts: 0, sequence: 2)) else {
            Issue.record("Observed zero may establish a truthful zero propulsion peak")
            return
        }
        let evidence = try #require(accumulator.evidence)
        #expect(evidence.peak.powerWatts == 0)
        #expect(evidence.acceptedMeasurementCount == 2)
        #expect(evidence.peakCandidateMeasurementCount == 1)
    }

    @Test("equal uptime ticks are ordered by immutable receipt sequence")
    func equalUptimeUsesSequenceTieBreaker() throws {
        var accumulator = try PeakPowerEvidenceAccumulator.simulatorQA(scope: simulatorScope())

        guard case .peakUpdated = accumulator.record(simulatorObservation(
            watts: 500,
            sequence: 1,
            uptime: 100
        )) else {
            Issue.record("Expected first peak")
            return
        }
        guard case .peakUpdated = accumulator.record(simulatorObservation(
            watts: 510,
            sequence: 2,
            uptime: 100
        )) else {
            Issue.record("Equal uptime with newer sequence must remain valid")
            return
        }
    }

    @Test("backward uptime consumes fresh callback identity without lowering time floor")
    func rejectedUptimeConsumesSequence() throws {
        var accumulator = try PeakPowerEvidenceAccumulator.simulatorQA(scope: simulatorScope())

        _ = accumulator.record(simulatorObservation(watts: 500, sequence: 10, uptime: 100))
        #expect(accumulator.record(simulatorObservation(
            watts: 520,
            sequence: 12,
            uptime: 99
        )) == .rejected(.nonIncreasingObservationTimestamp))
        #expect(accumulator.record(simulatorObservation(
            watts: 510,
            sequence: 11,
            uptime: 100
        )) == .rejected(.nonIncreasingObservationSequence))
        #expect(accumulator.record(simulatorObservation(
            watts: 520,
            sequence: 12,
            uptime: 100
        )) == .rejected(.nonIncreasingObservationSequence))

        guard case let .peakUpdated(recovered) = accumulator.record(simulatorObservation(
            watts: 540,
            sequence: 13,
            uptime: 100
        )) else {
            Issue.record("A genuinely newer receipt may recover at the preserved uptime floor")
            return
        }
        #expect(recovered.powerWatts == 540)
        #expect(accumulator.evidence?.continuity == .partialSelectedSourceEvidence)
    }

    @Test("fresh invalid numeric evidence closes chronology to delayed callbacks")
    func invalidNumericEvidenceConsumesSequence() throws {
        var accumulator = try PeakPowerEvidenceAccumulator.simulatorQA(scope: simulatorScope())

        _ = accumulator.record(simulatorObservation(watts: 500, sequence: 1, uptime: 100))
        #expect(accumulator.record(simulatorObservation(
            watts: .infinity,
            sequence: 3,
            uptime: 300
        )) == .rejected(.invalidPowerWatts))
        #expect(accumulator.record(simulatorObservation(
            watts: 510,
            sequence: 2,
            uptime: 200
        )) == .rejected(.nonIncreasingObservationSequence))

        let evidence = try #require(accumulator.evidence)
        #expect(evidence.peak.powerWatts == 500)
        #expect(evidence.qualityRejectedMeasurementCount == 2)
        #expect(evidence.continuity == .partialSelectedSourceEvidence)
    }

    @Test("reset preserves monotonic uptime floor and rejected receipt identity")
    func resetPreservesUptimeReplayFloor() throws {
        var accumulator = try PeakPowerEvidenceAccumulator.simulatorQA(scope: simulatorScope())
        _ = accumulator.record(simulatorObservation(
            watts: 700,
            sequence: 50,
            uptime: 500
        ))

        accumulator.reset()

        #expect(accumulator.record(simulatorObservation(
            watts: 900,
            sequence: 51,
            uptime: 499
        )) == .rejected(.nonIncreasingObservationTimestamp))

        // The rejected newer receipt remains consumed; reset did not reopen the
        // stream and a caller cannot rewrite that callback with cleaner metadata.
        #expect(accumulator.record(simulatorObservation(
            watts: 900,
            sequence: 51,
            uptime: 500
        )) == .rejected(.nonIncreasingObservationSequence))

        guard case let .peakUpdated(measurement) = accumulator.record(simulatorObservation(
            watts: 320,
            sequence: 52,
            uptime: 500
        )) else {
            Issue.record("A genuinely newer receipt may recover at the preserved uptime floor")
            return
        }
        #expect(measurement.powerWatts == 320)

        let evidence = try #require(accumulator.evidence)
        #expect(evidence.qualityRejectedMeasurementCount == 2)
        #expect(evidence.continuity == .partialSelectedSourceEvidence)
    }

    @Test("known interruptions preserve observed peak but mark continuity partial")
    func interruptionPreservesPeakWithPartialContinuity() throws {
        var accumulator = try PeakPowerEvidenceAccumulator.simulatorQA(scope: simulatorScope())
        _ = accumulator.record(simulatorObservation(watts: 580, sequence: 1))

        accumulator.recordInterruption(.vehicleConnectionLost)
        accumulator.recordInterruption(.observationStreamRestarted)

        let evidence = try #require(accumulator.evidence)
        #expect(evidence.peak.powerWatts == 580)
        #expect(evidence.knownInterruptionCount == 2)
        #expect(evidence.continuity == .partialSelectedSourceEvidence)
    }

    @Test("reset clears peak window but never reopens selected-stream replay chronology")
    func resetPreservesReplayProtection() throws {
        let scope = try simulatorScope(mode: "drive")
        var accumulator = try PeakPowerEvidenceAccumulator.simulatorQA(scope: scope)
        _ = accumulator.record(simulatorObservation(
            watts: 700,
            sequence: 50,
            uptime: 500,
            scope: scope
        ))
        accumulator.recordInterruption(.sourceUnavailable)

        accumulator.reset()

        #expect(accumulator.scope == scope)
        #expect(accumulator.evidenceAuthority == .simulatorQA)
        #expect(accumulator.evidence == nil)

        // Product accumulation restarted, but the selected source stream did not
        // gain a new acquisition-generation identity. A delayed pre-reset callback
        // therefore remains replay and must not be allowed to establish a new peak.
        #expect(accumulator.record(simulatorObservation(
            watts: 900,
            sequence: 10,
            uptime: 100,
            scope: scope
        )) == .rejected(.nonIncreasingObservationSequence))
        #expect(accumulator.evidence == nil)

        // A genuinely newer immutable receipt may establish the new product peak.
        guard case let .peakUpdated(measurement) = accumulator.record(simulatorObservation(
            watts: 300,
            sequence: 51,
            uptime: 500,
            scope: scope
        )) else {
            Issue.record("Reset must preserve replay guards while allowing genuinely newer evidence")
            return
        }
        #expect(measurement.powerWatts == 300)

        let evidence = try #require(accumulator.evidence)
        #expect(evidence.acceptedMeasurementCount == 1)
        #expect(evidence.peakCandidateMeasurementCount == 1)
        #expect(evidence.qualityRejectedMeasurementCount == 1)
        #expect(evidence.continuity == .partialSelectedSourceEvidence)
    }
}
