import Foundation
import Testing
@testable import NembraCore

@Suite("Battery receipt wall-clock metadata consistency")
struct BatteryEvidenceReceiptDateConsistencyTests {
    private let epoch = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!

    @Test("same raw receipt cannot rewrite captured wall-clock timestamp")
    func sameReceiptRejectsDifferentDate() throws {
        var validator = BatteryEvidenceStreamValidator()
        let receipt = BatteryEvidenceReceiptIdentity(
            acquisitionEpoch: epoch,
            sequenceNumber: 7
        )

        try validator.accept(
            try observation(
                receipt: receipt,
                field: .stateOfChargePercent,
                date: 1_000
            )
        )

        #expect(throws: BatteryEvidenceStreamValidationError.inconsistentReceiptMetadata) {
            try validator.accept(
                try observation(
                    receipt: receipt,
                    field: .voltageVolts,
                    date: 1_001
                )
            )
        }

        #expect(validator.lastAcceptedReceiptIdentity == receipt)
        #expect(validator.lastAcceptedUptimeNanoseconds == 500)
    }

    @Test("wall clock movement across distinct newer receipts remains legal")
    func distinctReceiptsMayObserveBackwardWallClock() throws {
        var validator = BatteryEvidenceStreamValidator()

        try validator.accept(
            try observation(
                receipt: BatteryEvidenceReceiptIdentity(
                    acquisitionEpoch: epoch,
                    sequenceNumber: 7
                ),
                field: .stateOfChargePercent,
                uptime: 500,
                date: 2_000
            )
        )
        try validator.accept(
            try observation(
                receipt: BatteryEvidenceReceiptIdentity(
                    acquisitionEpoch: epoch,
                    sequenceNumber: 8
                ),
                field: .stateOfChargePercent,
                uptime: 501,
                date: 1_000
            )
        )

        #expect(
            validator.lastAcceptedReceiptIdentity
                == BatteryEvidenceReceiptIdentity(
                    acquisitionEpoch: epoch,
                    sequenceNumber: 8
                )
        )
        #expect(validator.lastAcceptedUptimeNanoseconds == 501)
    }

    private func observation(
        receipt: BatteryEvidenceReceiptIdentity,
        field: BatteryEvidenceField,
        uptime: UInt64 = 500,
        date: TimeInterval
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
            role: .verifiedVehicleMeasurement,
            receiptIdentity: receipt,
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: Date(timeIntervalSinceReferenceDate: date),
            continuity: .continuous
        )
    }
}
