import Foundation
import Testing
@testable import NembraCore

@Suite("Battery evidence stream validator")
struct BatteryEvidenceStreamValidatorTests {
    private func observation(
        uptime: UInt64,
        date: TimeInterval = 1_000,
        continuity: BatteryEvidenceContinuity = .continuous,
        role: BatteryEvidenceRole = .verifiedVehicleMeasurement,
        field: BatteryEvidenceField = .stateOfChargePercent
    ) throws -> BatteryEvidenceObservation {
        let value: BatterySemanticValue
        switch field {
        case .stateOfChargePercent:
            value = try BatterySemanticValue.stateOfChargePercent(50)
        case .voltageVolts:
            value = try BatterySemanticValue.voltageVolts(39.8)
        case .currentAmps:
            value = try BatterySemanticValue.currentAmps(3.2)
        case .powerWatts:
            value = try BatterySemanticValue.powerWatts(127)
        case .chargingState:
            value = try BatterySemanticValue.chargingState(false)
        }

        return try BatteryEvidenceObservation(
            value: value,
            role: role,
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: Date(timeIntervalSinceReferenceDate: date),
            continuity: continuity
        )
    }

    @Test("equal uptime is valid for multiple semantic fields from one callback")
    func equalUptimeIsAllowed() throws {
        var validator = BatteryEvidenceStreamValidator()

        try validator.accept(try observation(uptime: 10, field: .stateOfChargePercent))
        try validator.accept(try observation(uptime: 10, field: .voltageVolts))
        try validator.accept(try observation(uptime: 10, field: .currentAmps))

        #expect(validator.lastAcceptedUptimeNanoseconds == 10)
        #expect(!validator.requiresContinuityBoundary)
    }

    @Test("older continuous uptime is rejected without corrupting the baseline")
    func olderContinuousUptimeFailsAtomically() throws {
        var validator = BatteryEvidenceStreamValidator()
        try validator.accept(try observation(uptime: 20))

        var captured: BatteryEvidenceStreamValidationError?
        do {
            try validator.accept(try observation(uptime: 19))
        } catch let error as BatteryEvidenceStreamValidationError {
            captured = error
        }

        #expect(captured == .nonMonotonicUptime)
        #expect(validator.lastAcceptedUptimeNanoseconds == 20)
        #expect(!validator.requiresContinuityBoundary)

        try validator.accept(try observation(uptime: 21))
        #expect(validator.lastAcceptedUptimeNanoseconds == 21)
    }

    @Test("known missed evidence requires an explicit post-gap boundary and retains ordering baseline")
    func markedGapRequiresBoundary() throws {
        var validator = BatteryEvidenceStreamValidator()
        try validator.accept(try observation(uptime: 100))
        validator.markUnobservedInterval()

        #expect(validator.lastAcceptedUptimeNanoseconds == 100)
        #expect(validator.requiresContinuityBoundary)

        var captured: BatteryEvidenceStreamValidationError?
        do {
            try validator.accept(try observation(uptime: 101, continuity: .continuous))
        } catch let error as BatteryEvidenceStreamValidationError {
            captured = error
        }

        #expect(captured == .missingContinuityBoundary)
        #expect(validator.lastAcceptedUptimeNanoseconds == 100)
        #expect(validator.requiresContinuityBoundary)
    }

    @Test("post-gap boundary cannot rewind an existing process uptime epoch")
    func boundaryCannotResetUptimeEpoch() throws {
        var validator = BatteryEvidenceStreamValidator()
        try validator.accept(try observation(uptime: 9_000))
        validator.markUnobservedInterval()

        var captured: BatteryEvidenceStreamValidationError?
        do {
            try validator.accept(
                try observation(uptime: 4, continuity: .afterUnobservedInterval)
            )
        } catch let error as BatteryEvidenceStreamValidationError {
            captured = error
        }

        #expect(captured == .nonMonotonicUptime)
        #expect(validator.lastAcceptedUptimeNanoseconds == 9_000)
        #expect(validator.requiresContinuityBoundary)

        try validator.accept(
            try observation(uptime: 9_001, continuity: .afterUnobservedInterval)
        )
        #expect(validator.lastAcceptedUptimeNanoseconds == 9_001)
        #expect(!validator.requiresContinuityBoundary)

        try validator.accept(try observation(uptime: 9_002))
        #expect(validator.lastAcceptedUptimeNanoseconds == 9_002)
    }

    @Test("explicit conservative boundary still obeys process-local monotonic uptime")
    func explicitBoundaryCannotRewindBaseline() throws {
        var validator = BatteryEvidenceStreamValidator()
        try validator.accept(try observation(uptime: 800))

        var captured: BatteryEvidenceStreamValidationError?
        do {
            try validator.accept(
                try observation(uptime: 2, continuity: .afterUnobservedInterval)
            )
        } catch let error as BatteryEvidenceStreamValidationError {
            captured = error
        }

        #expect(captured == .nonMonotonicUptime)
        #expect(validator.lastAcceptedUptimeNanoseconds == 800)
        #expect(!validator.requiresContinuityBoundary)

        try validator.accept(
            try observation(uptime: 801, continuity: .afterUnobservedInterval)
        )
        #expect(validator.lastAcceptedUptimeNanoseconds == 801)
        #expect(!validator.requiresContinuityBoundary)
    }

    @Test("fresh validator establishes a new process uptime epoch")
    func freshValidatorAcceptsNewEpochBoundary() throws {
        var validator = BatteryEvidenceStreamValidator()

        try validator.accept(
            try observation(uptime: 4, continuity: .afterUnobservedInterval)
        )

        #expect(validator.lastAcceptedUptimeNanoseconds == 4)
        #expect(!validator.requiresContinuityBoundary)
        try validator.accept(try observation(uptime: 5))
        #expect(validator.lastAcceptedUptimeNanoseconds == 5)
    }

    @Test("retained baseline blocks delayed pre-gap evidence after a valid boundary")
    func delayedPreGapEvidenceCannotReenterAfterBoundary() throws {
        var validator = BatteryEvidenceStreamValidator()
        let preGap = try observation(uptime: 900, field: .voltageVolts)

        try validator.accept(preGap)
        validator.markUnobservedInterval()
        try validator.accept(
            try observation(
                uptime: 901,
                continuity: .afterUnobservedInterval,
                field: .stateOfChargePercent
            )
        )

        var captured: BatteryEvidenceStreamValidationError?
        do {
            try validator.accept(preGap)
        } catch let error as BatteryEvidenceStreamValidationError {
            captured = error
        }

        #expect(captured == .nonMonotonicUptime)
        #expect(validator.lastAcceptedUptimeNanoseconds == 901)
        #expect(!validator.requiresContinuityBoundary)
    }

    @Test("wall clock movement never repairs or invalidates monotonic uptime ordering")
    func wallClockIsMetadataOnly() throws {
        var validator = BatteryEvidenceStreamValidator()

        try validator.accept(try observation(uptime: 30, date: 2_000))
        try validator.accept(try observation(uptime: 31, date: 1_000))

        #expect(validator.lastAcceptedUptimeNanoseconds == 31)
    }

    @Test("ordering guard never promotes nonphysical evidence roles")
    func validationDoesNotPromoteTruthRole() throws {
        var validator = BatteryEvidenceStreamValidator()
        let evidence = try observation(
            uptime: 50,
            role: .stockAppCorrelationAnchor
        )

        try validator.accept(evidence)

        #expect(evidence.role == .stockAppCorrelationAnchor)
        #expect(!evidence.isAuthoritativeVehicleMeasurement)
        #expect(!evidence.isAdaptiveRangeSOCEvidence)
    }
}
