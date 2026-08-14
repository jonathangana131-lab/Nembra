import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive Bluetooth power-cycle series integrity")
struct PassiveBluetoothPowerCycleObservationSeriesIntegrityTests {
    private let scooter = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!

    private func candidate(
        _ id: UUID
    ) -> PassiveBluetoothCandidateObservationSnapshot.Candidate {
        .init(id: id, isConnectable: true)
    }

    @Test("known gap invalidates all prior successful windows")
    func invalidationPreventsSeriesPatching() throws {
        var ledger = PassiveBluetoothPowerCycleObservationLedger(
            minimumWindowDurationNanoseconds: 10
        )

        _ = try ledger.completeWindow(
            phase: .firstPoweredOff,
            startedAtUptimeNanoseconds: 100,
            endedAtUptimeNanoseconds: 110,
            candidates: []
        )
        #expect(ledger.completedReceipts.count == 1)
        #expect(ledger.nextPhase == .firstPoweredOn)

        ledger.invalidate()

        #expect(ledger.isInvalidated)
        #expect(throws: PassiveBluetoothPowerCycleObservationSessionError.seriesInvalidated) {
            try ledger.completeWindow(
                phase: .firstPoweredOn,
                startedAtUptimeNanoseconds: 200,
                endedAtUptimeNanoseconds: 210,
                candidates: [candidate(scooter)]
            )
        }
        #expect(ledger.completedReceipts.count == 1)
        #expect(ledger.completedSnapshots.count == 1)
    }

    @Test("early finish attempt is nonterminal while the same window can continue")
    func tooShortAttemptDoesNotInvalidateSeries() throws {
        var ledger = PassiveBluetoothPowerCycleObservationLedger(
            minimumWindowDurationNanoseconds: 10
        )

        #expect(throws: PassiveBluetoothPowerCycleObservationSessionError.minimumWindowDurationNotReached) {
            try ledger.completeWindow(
                phase: .firstPoweredOff,
                startedAtUptimeNanoseconds: 100,
                endedAtUptimeNanoseconds: 109,
                candidates: []
            )
        }

        #expect(!ledger.isInvalidated)
        #expect(ledger.nextPhase == .firstPoweredOff)
        #expect(ledger.completedSnapshots.isEmpty)

        _ = try ledger.completeWindow(
            phase: .firstPoweredOff,
            startedAtUptimeNanoseconds: 100,
            endedAtUptimeNanoseconds: 110,
            candidates: []
        )
        #expect(ledger.nextPhase == .firstPoweredOn)
    }

    @Test("failed series can never issue a later final correlation")
    func invalidatedSeriesCannotComplete() throws {
        var ledger = PassiveBluetoothPowerCycleObservationLedger(
            minimumWindowDurationNanoseconds: 1
        )

        _ = try ledger.completeWindow(
            phase: .firstPoweredOff,
            startedAtUptimeNanoseconds: 1,
            endedAtUptimeNanoseconds: 2,
            candidates: []
        )
        _ = try ledger.completeWindow(
            phase: .firstPoweredOn,
            startedAtUptimeNanoseconds: 3,
            endedAtUptimeNanoseconds: 4,
            candidates: [candidate(scooter)]
        )

        ledger.invalidate()

        #expect(throws: PassiveBluetoothPowerCycleObservationSessionError.seriesInvalidated) {
            try ledger.completeWindow(
                phase: .secondPoweredOff,
                startedAtUptimeNanoseconds: 5,
                endedAtUptimeNanoseconds: 6,
                candidates: []
            )
        }
        #expect(ledger.completedSnapshots.count == 2)
    }

    @Test("operator phases describe expected procedure rather than inferred hardware state")
    func phasePowerExpectationIsExplicit() {
        #expect(!PassiveBluetoothPowerCycleObservationPhase.firstPoweredOff.operatorExpectedPowerOn)
        #expect(PassiveBluetoothPowerCycleObservationPhase.firstPoweredOn.operatorExpectedPowerOn)
        #expect(!PassiveBluetoothPowerCycleObservationPhase.secondPoweredOff.operatorExpectedPowerOn)
        #expect(PassiveBluetoothPowerCycleObservationPhase.secondPoweredOn.operatorExpectedPowerOn)
    }
}