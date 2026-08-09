import Foundation
import Testing
@testable import NembraCore

@Suite("Battery range currentness owner copy semantics")
struct BatteryRangeCurrentnessOwnerCopyTests {
    @Test("only one copied stream lineage can advance currentness")
    func copiedStreamsCannotForkAuthority() throws {
        let epoch = UUID(uuidString: "92929292-9292-9292-9292-929292929292")!
        var primary = AcceptedBatterySOCStream()
        let first = try #require(primary.accept(
            try verifiedSOC(percent: 80, epoch: epoch, sequence: 1, uptime: 1_000)
        ))
        var copiedHandle = primary

        let second = try #require(primary.accept(
            try verifiedSOC(percent: 79, epoch: epoch, sequence: 2, uptime: 2_000)
        ))

        #expect(first.isCurrent == false)
        #expect(second.isCurrent)
        #expect(second.isCurrent(in: primary.validator))
        #expect(second.isCurrent(in: copiedHandle.validator) == false)

        #expect(throws: BatteryEvidenceStreamValidationError.staleCurrentnessOwner) {
            _ = try copiedHandle.accept(
                verifiedSOC(percent: 78, epoch: epoch, sequence: 3, uptime: 3_000)
            )
        }

        #expect(second.isCurrent)
        #expect(primary.validator.lastAcceptedReceiptIdentity == second.sourceReceiptIdentity)
        #expect(copiedHandle.validator.lastAcceptedReceiptIdentity == first.sourceReceiptIdentity)
    }

    @Test("gap on one copied handle revokes peers but cannot create false currentness")
    func copiedGapRevokesPeersFailClosed() throws {
        let epoch = UUID(uuidString: "93939393-9393-9393-9393-939393939393")!
        var primary = AcceptedBatterySOCStream()
        let first = try #require(primary.accept(
            try verifiedSOC(percent: 80, epoch: epoch, sequence: 1, uptime: 1_000)
        ))
        var copiedHandle = primary

        copiedHandle.markUnobservedInterval()

        #expect(first.isCurrent == false)
        #expect(first.isCurrent(in: primary.validator) == false)
        #expect(first.isCurrent(in: copiedHandle.validator) == false)

        #expect(throws: BatteryEvidenceStreamValidationError.staleCurrentnessOwner) {
            _ = try primary.accept(
                verifiedSOC(percent: 79, epoch: epoch, sequence: 2, uptime: 2_000)
            )
        }

        let recovered = try #require(copiedHandle.accept(
            try verifiedSOC(
                percent: 79,
                epoch: epoch,
                sequence: 2,
                uptime: 2_000,
                continuity: .afterUnobservedInterval
            )
        ))
        #expect(recovered.isCurrent)
        #expect(recovered.isCurrent(in: copiedHandle.validator))
        #expect(recovered.isCurrent(in: primary.validator) == false)
    }

    private func verifiedSOC(
        percent: Double,
        epoch: UUID,
        sequence: UInt64,
        uptime: UInt64,
        continuity: BatteryEvidenceContinuity = .continuous
    ) throws -> BatteryEvidenceObservation {
        try BatteryEvidenceObservation(
            value: .stateOfChargePercent(percent),
            role: .verifiedVehicleMeasurement,
            receiptIdentity: BatteryEvidenceReceiptIdentity(
                acquisitionEpoch: epoch,
                sequenceNumber: sequence
            ),
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: Date(timeIntervalSinceReferenceDate: Double(uptime) / 1_000),
            continuity: continuity
        )
    }
}
