import Foundation
import Testing
@testable import NembraCore

@Suite("Battery receipt rejected-callback chronology recovery")
struct BatteryEvidenceReceiptChronologyRecoveryTests {
    private let epoch = UUID(uuidString: "ABABABAB-ABAB-ABAB-ABAB-ABABABABABAB")!

    private func observation(
        sequence: UInt64,
        uptime: UInt64,
        continuity: BatteryEvidenceContinuity = .continuous
    ) throws -> BatteryEvidenceObservation {
        try BatteryEvidenceObservation(
            value: BatterySemanticValue.stateOfChargePercent(50),
            role: .verifiedVehicleMeasurement,
            receiptIdentity: BatteryEvidenceReceiptIdentity(
                acquisitionEpoch: epoch,
                sequenceNumber: sequence
            ),
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: Date(timeIntervalSinceReferenceDate: 1_000),
            continuity: continuity
        )
    }

    private func receipt(_ sequence: UInt64) -> BatteryEvidenceReceiptIdentity {
        BatteryEvidenceReceiptIdentity(
            acquisitionEpoch: epoch,
            sequenceNumber: sequence
        )
    }

    @Test("rejected missing-boundary callback raises the future seen uptime floor")
    func rejectedMissingBoundaryRaisesSeenUptimeFloor() throws {
        var validator = BatteryEvidenceStreamValidator()
        try validator.accept(try observation(sequence: 20, uptime: 200))
        validator.markUnobservedInterval()

        #expect(throws: BatteryEvidenceStreamValidationError.missingContinuityBoundary) {
            try validator.accept(try observation(sequence: 21, uptime: 300))
        }
        #expect(validator.lastAcceptedReceiptIdentity == receipt(20))
        #expect(validator.lastSeenReceiptIdentity == receipt(21))
        #expect(validator.requiresContinuityBoundary)

        #expect(throws: BatteryEvidenceStreamValidationError.nonMonotonicUptime) {
            try validator.accept(
                try observation(
                    sequence: 22,
                    uptime: 250,
                    continuity: .afterUnobservedInterval
                )
            )
        }
        #expect(validator.lastAcceptedReceiptIdentity == receipt(20))
        #expect(validator.lastSeenReceiptIdentity == receipt(22))
        #expect(validator.requiresContinuityBoundary)

        // A second newer receipt still cannot use an uptime below the earlier 300 ns
        // callback. Rejected callbacks consume sequence identity without lowering time.
        #expect(throws: BatteryEvidenceStreamValidationError.nonMonotonicUptime) {
            try validator.accept(
                try observation(
                    sequence: 23,
                    uptime: 275,
                    continuity: .afterUnobservedInterval
                )
            )
        }
        #expect(validator.lastSeenReceiptIdentity == receipt(23))
        #expect(validator.requiresContinuityBoundary)

        try validator.accept(
            try observation(
                sequence: 24,
                uptime: 300,
                continuity: .afterUnobservedInterval
            )
        )
        #expect(validator.lastAcceptedReceiptIdentity == receipt(24))
        #expect(validator.lastSeenReceiptIdentity == receipt(24))
        #expect(validator.lastAcceptedUptimeNanoseconds == 300)
        #expect(!validator.requiresContinuityBoundary)
    }

    @Test("a callback rejected below the existing uptime floor cannot lower that floor")
    func rejectedBackwardCallbackCannotLowerUptimeFloor() throws {
        var validator = BatteryEvidenceStreamValidator()
        try validator.accept(try observation(sequence: 40, uptime: 400))

        #expect(throws: BatteryEvidenceStreamValidationError.nonMonotonicUptime) {
            try validator.accept(try observation(sequence: 41, uptime: 399))
        }
        #expect(validator.lastAcceptedReceiptIdentity == receipt(40))
        #expect(validator.lastSeenReceiptIdentity == receipt(41))

        try validator.accept(try observation(sequence: 42, uptime: 400))
        #expect(validator.lastAcceptedReceiptIdentity == receipt(42))
        #expect(validator.lastSeenReceiptIdentity == receipt(42))
        #expect(validator.lastAcceptedUptimeNanoseconds == 400)
    }

    @Test("a rejected raw receipt cannot be rewritten into accepted evidence")
    func rejectedReceiptMetadataIsImmutable() throws {
        var validator = BatteryEvidenceStreamValidator()
        try validator.accept(try observation(sequence: 60, uptime: 600))
        validator.markUnobservedInterval()

        #expect(throws: BatteryEvidenceStreamValidationError.missingContinuityBoundary) {
            try validator.accept(try observation(sequence: 61, uptime: 601))
        }

        #expect(throws: BatteryEvidenceStreamValidationError.inconsistentReceiptMetadata) {
            try validator.accept(
                try observation(
                    sequence: 61,
                    uptime: 601,
                    continuity: .afterUnobservedInterval
                )
            )
        }
        #expect(validator.lastAcceptedReceiptIdentity == receipt(60))
        #expect(validator.lastSeenReceiptIdentity == receipt(61))
        #expect(validator.requiresContinuityBoundary)

        try validator.accept(
            try observation(
                sequence: 62,
                uptime: 602,
                continuity: .afterUnobservedInterval
            )
        )
        #expect(validator.lastAcceptedReceiptIdentity == receipt(62))
        #expect(!validator.requiresContinuityBoundary)
    }
}
