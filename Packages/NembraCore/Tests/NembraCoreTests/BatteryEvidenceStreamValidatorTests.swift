import Foundation
import Testing
@testable import NembraCore

@Suite("Battery evidence stream validator")
struct BatteryEvidenceStreamValidatorTests {
    private let epoch = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let nextEpoch = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    private func receipt(sequence: UInt64, epoch: UUID? = nil) -> BatteryEvidenceReceiptIdentity {
        BatteryEvidenceReceiptIdentity(
            acquisitionEpoch: epoch ?? self.epoch,
            sequenceNumber: sequence
        )
    }

    private func observation(
        sequence: UInt64,
        uptime: UInt64,
        epoch: UUID? = nil,
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
            receiptIdentity: receipt(sequence: sequence, epoch: epoch),
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: Date(timeIntervalSinceReferenceDate: date),
            continuity: continuity
        )
    }

    @Test("same receipt allows sibling semantic fields at one uptime")
    func sameReceiptAllowsSiblingFields() throws {
        var validator = BatteryEvidenceStreamValidator()

        try validator.accept(try observation(sequence: 1, uptime: 10, field: .stateOfChargePercent))
        try validator.accept(try observation(sequence: 1, uptime: 10, field: .voltageVolts))
        try validator.accept(try observation(sequence: 1, uptime: 10, field: .currentAmps))

        #expect(validator.lastAcceptedReceiptIdentity == receipt(sequence: 1))
        #expect(validator.lastSeenReceiptIdentity == receipt(sequence: 1))
        #expect(validator.lastAcceptedUptimeNanoseconds == 10)
        #expect(!validator.requiresContinuityBoundary)
    }

    @Test("distinct higher receipt at equal uptime remains a distinct callback")
    func equalUptimeDistinctReceiptIsAllowed() throws {
        var validator = BatteryEvidenceStreamValidator()

        try validator.accept(try observation(sequence: 1, uptime: 10))
        try validator.accept(try observation(sequence: 2, uptime: 10))

        #expect(validator.lastAcceptedReceiptIdentity == receipt(sequence: 2))
        #expect(validator.lastSeenReceiptIdentity == receipt(sequence: 2))
        #expect(validator.lastAcceptedUptimeNanoseconds == 10)
    }

    @Test("older receipt is rejected even when its uptime looks newer")
    func staleReceiptFailsAtomically() throws {
        var validator = BatteryEvidenceStreamValidator()
        try validator.accept(try observation(sequence: 20, uptime: 20))

        var captured: BatteryEvidenceStreamValidationError?
        do {
            try validator.accept(try observation(sequence: 19, uptime: 200))
        } catch let error as BatteryEvidenceStreamValidationError {
            captured = error
        }

        #expect(captured == .staleReceiptIdentity)
        #expect(validator.lastAcceptedReceiptIdentity == receipt(sequence: 20))
        #expect(validator.lastSeenReceiptIdentity == receipt(sequence: 20))
        #expect(validator.lastAcceptedUptimeNanoseconds == 20)
        #expect(!validator.requiresContinuityBoundary)

        try validator.accept(try observation(sequence: 21, uptime: 21))
        #expect(validator.lastAcceptedReceiptIdentity == receipt(sequence: 21))
        #expect(validator.lastSeenReceiptIdentity == receipt(sequence: 21))
    }

    @Test("rejected newer receipt consumes callback chronology and cannot be rewritten")
    func rejectedNewerReceiptConsumesChronology() throws {
        var validator = BatteryEvidenceStreamValidator()
        try validator.accept(try observation(sequence: 20, uptime: 200))

        #expect(throws: BatteryEvidenceStreamValidationError.nonMonotonicUptime) {
            try validator.accept(try observation(sequence: 22, uptime: 199))
        }

        #expect(validator.lastAcceptedReceiptIdentity == receipt(sequence: 20))
        #expect(validator.lastSeenReceiptIdentity == receipt(sequence: 22))
        #expect(validator.lastAcceptedUptimeNanoseconds == 200)

        #expect(throws: BatteryEvidenceStreamValidationError.staleReceiptIdentity) {
            try validator.accept(try observation(sequence: 21, uptime: 201))
        }
        #expect(throws: BatteryEvidenceStreamValidationError.inconsistentReceiptMetadata) {
            try validator.accept(try observation(sequence: 22, uptime: 200))
        }

        try validator.accept(try observation(sequence: 23, uptime: 200))
        #expect(validator.lastAcceptedReceiptIdentity == receipt(sequence: 23))
        #expect(validator.lastSeenReceiptIdentity == receipt(sequence: 23))
    }

    @Test("known missed evidence requires a genuinely newer explicit boundary")
    func markedGapRequiresNewerBoundary() throws {
        var validator = BatteryEvidenceStreamValidator()
        try validator.accept(try observation(sequence: 100, uptime: 1_000))
        validator.markUnobservedInterval()

        #expect(validator.lastAcceptedReceiptIdentity == receipt(sequence: 100))
        #expect(validator.lastSeenReceiptIdentity == receipt(sequence: 100))
        #expect(validator.lastAcceptedUptimeNanoseconds == 1_000)
        #expect(validator.requiresContinuityBoundary)

        #expect(throws: BatteryEvidenceStreamValidationError.missingContinuityBoundary) {
            try validator.accept(try observation(sequence: 101, uptime: 1_000))
        }
        #expect(validator.lastAcceptedReceiptIdentity == receipt(sequence: 100))
        #expect(validator.lastSeenReceiptIdentity == receipt(sequence: 101))
        #expect(validator.requiresContinuityBoundary)

        #expect(throws: BatteryEvidenceStreamValidationError.staleReceiptIdentity) {
            try validator.accept(
                try observation(
                    sequence: 100,
                    uptime: 1_000,
                    continuity: .afterUnobservedInterval
                )
            )
        }
        #expect(throws: BatteryEvidenceStreamValidationError.inconsistentReceiptMetadata) {
            try validator.accept(
                try observation(
                    sequence: 101,
                    uptime: 1_000,
                    continuity: .afterUnobservedInterval
                )
            )
        }

        try validator.accept(
            try observation(
                sequence: 102,
                uptime: 1_000,
                continuity: .afterUnobservedInterval
            )
        )
        #expect(validator.lastAcceptedReceiptIdentity == receipt(sequence: 102))
        #expect(validator.lastSeenReceiptIdentity == receipt(sequence: 102))
        #expect(validator.lastAcceptedUptimeNanoseconds == 1_000)
        #expect(!validator.requiresContinuityBoundary)
    }

    @Test("lower-uptime boundary failure consumes that receipt but preserves pending gap")
    func lowerUptimeBoundaryConsumesReceiptAndPreservesGap() throws {
        var validator = BatteryEvidenceStreamValidator()
        try validator.accept(try observation(sequence: 10, uptime: 9_000))
        validator.markUnobservedInterval()

        #expect(throws: BatteryEvidenceStreamValidationError.nonMonotonicUptime) {
            try validator.accept(
                try observation(
                    sequence: 11,
                    uptime: 4,
                    continuity: .afterUnobservedInterval
                )
            )
        }

        #expect(validator.lastAcceptedReceiptIdentity == receipt(sequence: 10))
        #expect(validator.lastSeenReceiptIdentity == receipt(sequence: 11))
        #expect(validator.lastAcceptedUptimeNanoseconds == 9_000)
        #expect(validator.requiresContinuityBoundary)

        #expect(throws: BatteryEvidenceStreamValidationError.inconsistentReceiptMetadata) {
            try validator.accept(
                try observation(
                    sequence: 11,
                    uptime: 9_000,
                    continuity: .afterUnobservedInterval
                )
            )
        }

        try validator.accept(
            try observation(
                sequence: 12,
                uptime: 9_000,
                continuity: .afterUnobservedInterval
            )
        )
        #expect(validator.lastAcceptedReceiptIdentity == receipt(sequence: 12))
        #expect(validator.lastSeenReceiptIdentity == receipt(sequence: 12))
        #expect(!validator.requiresContinuityBoundary)
    }

    @Test("same receipt siblings must preserve receipt uptime and continuity metadata")
    func sameReceiptMetadataMustMatch() throws {
        var validator = BatteryEvidenceStreamValidator()
        try validator.accept(try observation(sequence: 1, uptime: 50))

        #expect(throws: BatteryEvidenceStreamValidationError.inconsistentReceiptMetadata) {
            try validator.accept(try observation(sequence: 1, uptime: 51, field: .voltageVolts))
        }
        #expect(throws: BatteryEvidenceStreamValidationError.inconsistentReceiptMetadata) {
            try validator.accept(
                try observation(
                    sequence: 1,
                    uptime: 50,
                    continuity: .afterUnobservedInterval,
                    field: .voltageVolts
                )
            )
        }

        #expect(validator.lastAcceptedReceiptIdentity == receipt(sequence: 1))
        #expect(validator.lastSeenReceiptIdentity == receipt(sequence: 1))
        #expect(validator.lastAcceptedUptimeNanoseconds == 50)
        #expect(!validator.requiresContinuityBoundary)
    }

    @Test("same boundary receipt may carry several sibling fields")
    func sameBoundaryReceiptAllowsSiblingFields() throws {
        var validator = BatteryEvidenceStreamValidator()
        try validator.accept(try observation(sequence: 1, uptime: 10))
        validator.markUnobservedInterval()

        try validator.accept(
            try observation(
                sequence: 2,
                uptime: 10,
                continuity: .afterUnobservedInterval,
                field: .stateOfChargePercent
            )
        )
        try validator.accept(
            try observation(
                sequence: 2,
                uptime: 10,
                continuity: .afterUnobservedInterval,
                field: .voltageVolts
            )
        )

        #expect(validator.lastAcceptedReceiptIdentity == receipt(sequence: 2))
        #expect(validator.lastSeenReceiptIdentity == receipt(sequence: 2))
        #expect(!validator.requiresContinuityBoundary)
    }

    @Test("different acquisition epoch requires a fresh validator")
    func differentEpochRequiresFreshValidator() throws {
        var validator = BatteryEvidenceStreamValidator()
        try validator.accept(try observation(sequence: 90, uptime: 9_000))

        #expect(throws: BatteryEvidenceStreamValidationError.acquisitionEpochChanged) {
            try validator.accept(
                try observation(sequence: 1, uptime: 4, epoch: nextEpoch)
            )
        }
        #expect(validator.lastAcceptedReceiptIdentity == receipt(sequence: 90))
        #expect(validator.lastSeenReceiptIdentity == receipt(sequence: 90))
        #expect(validator.lastAcceptedUptimeNanoseconds == 9_000)

        var freshValidator = BatteryEvidenceStreamValidator()
        try freshValidator.accept(
            try observation(
                sequence: 1,
                uptime: 4,
                epoch: nextEpoch,
                continuity: .afterUnobservedInterval
            )
        )
        #expect(
            freshValidator.lastAcceptedReceiptIdentity
                == receipt(sequence: 1, epoch: nextEpoch)
        )
        #expect(
            freshValidator.lastSeenReceiptIdentity
                == receipt(sequence: 1, epoch: nextEpoch)
        )
        #expect(freshValidator.lastAcceptedUptimeNanoseconds == 4)
    }

    @Test("retained receipt baseline blocks delayed pre-gap replay even at equal uptime")
    func delayedPreGapEvidenceCannotReenterAfterBoundary() throws {
        var validator = BatteryEvidenceStreamValidator()
        let preGap = try observation(sequence: 40, uptime: 900, field: .voltageVolts)

        try validator.accept(preGap)
        validator.markUnobservedInterval()
        try validator.accept(
            try observation(
                sequence: 41,
                uptime: 900,
                continuity: .afterUnobservedInterval,
                field: .stateOfChargePercent
            )
        )

        #expect(throws: BatteryEvidenceStreamValidationError.staleReceiptIdentity) {
            try validator.accept(preGap)
        }
        #expect(validator.lastAcceptedReceiptIdentity == receipt(sequence: 41))
        #expect(validator.lastSeenReceiptIdentity == receipt(sequence: 41))
        #expect(validator.lastAcceptedUptimeNanoseconds == 900)
        #expect(!validator.requiresContinuityBoundary)
    }

    @Test("generic imported observation cannot enter a live ordered stream without receipt identity")
    func missingReceiptIdentityFailsClosed() throws {
        var validator = BatteryEvidenceStreamValidator()
        let importedLike = try BatteryEvidenceObservation.nonAuthoritative(
            value: BatterySemanticValue.stateOfChargePercent(50),
            role: .simulationFixture,
            receivedAtUptimeNanoseconds: 10,
            receivedAtDate: Date(timeIntervalSinceReferenceDate: 1_000)
        )

        #expect(importedLike.receiptIdentity == nil)
        #expect(throws: BatteryEvidenceStreamValidationError.missingReceiptIdentity) {
            try validator.accept(importedLike)
        }
        #expect(validator.lastAcceptedReceiptIdentity == nil)
        #expect(validator.lastSeenReceiptIdentity == nil)
        #expect(validator.lastAcceptedUptimeNanoseconds == nil)
    }

    @Test("wall clock movement never repairs or invalidates receipt ordering")
    func wallClockIsMetadataOnly() throws {
        var validator = BatteryEvidenceStreamValidator()

        try validator.accept(try observation(sequence: 30, uptime: 30, date: 2_000))
        try validator.accept(try observation(sequence: 31, uptime: 31, date: 1_000))

        #expect(validator.lastAcceptedReceiptIdentity == receipt(sequence: 31))
        #expect(validator.lastSeenReceiptIdentity == receipt(sequence: 31))
        #expect(validator.lastAcceptedUptimeNanoseconds == 31)
    }

    @Test("ordering guard never promotes nonphysical evidence roles")
    func validationDoesNotPromoteTruthRole() throws {
        var validator = BatteryEvidenceStreamValidator()
        let evidence = try observation(
            sequence: 50,
            uptime: 50,
            role: .stockAppCorrelationAnchor
        )

        try validator.accept(evidence)

        #expect(evidence.role == .stockAppCorrelationAnchor)
        #expect(!evidence.isAuthoritativeVehicleMeasurement)
        #expect(!evidence.isAdaptiveRangeSOCEvidence)
    }
}
