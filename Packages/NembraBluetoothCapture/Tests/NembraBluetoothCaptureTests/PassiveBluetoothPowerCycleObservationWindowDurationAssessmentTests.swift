import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive Bluetooth power-cycle window duration policy")
struct PassiveBluetoothPowerCycleObservationWindowDurationAssessmentTests {
    private func completedResult(
        producerMinimumNanoseconds: UInt64,
        observedDurationNanoseconds: UInt64
    ) throws -> PassiveBluetoothPowerCycleObservationResult {
        var ledger = PassiveBluetoothPowerCycleObservationLedger(
            minimumWindowDurationNanoseconds: producerMinimumNanoseconds
        )
        var completed: PassiveBluetoothPowerCycleObservationResult?

        for (index, phase) in PassiveBluetoothPowerCycleObservationPhase.allCases.enumerated() {
            let start = UInt64(index + 1) * 100_000_000_000
            completed = try ledger.completeWindow(
                phase: phase,
                startedAtUptimeNanoseconds: start,
                endedAtUptimeNanoseconds: start + observedDurationNanoseconds,
                candidates: []
            )
        }

        return try #require(completed)
    }

    @Test("short producer policy cannot masquerade as ten-second experiment evidence")
    func shortWindowsFailTenSecondPolicy() throws {
        let result = try completedResult(
            producerMinimumNanoseconds: 1_000_000_000,
            observedDurationNanoseconds: 2_000_000_000
        )

        let assessment = PassiveBluetoothPowerCycleObservationWindowDurationAssessment.assess(
            result: result,
            minimumDurationNanoseconds: 10_000_000_000
        )

        #expect(assessment.status == .insufficientDuration)
        #expect(!assessment.isDurationSufficient)
        #expect(assessment.observationResult == result)
        #expect(assessment.minimumRequiredDurationNanoseconds == 10_000_000_000)
        #expect(assessment.windows.map(\.observedDurationNanoseconds) == [
            2_000_000_000,
            2_000_000_000,
            2_000_000_000,
            2_000_000_000
        ])
    }

    @Test("all four ten-second receipt windows satisfy ten-second policy")
    func tenSecondWindowsPassTenSecondPolicy() throws {
        let result = try completedResult(
            producerMinimumNanoseconds: 1,
            observedDurationNanoseconds: 10_000_000_000
        )

        let assessment = PassiveBluetoothPowerCycleObservationWindowDurationAssessment.assess(
            result: result,
            minimumDurationNanoseconds: 10_000_000_000
        )

        #expect(assessment.status == .sufficient)
        #expect(assessment.isDurationSufficient)
        #expect(assessment.observationResult == result)
        #expect(assessment.windows.map(\.phase) == PassiveBluetoothPowerCycleObservationPhase.allCases)
        #expect(assessment.windows.map { $0.windowSequence.rawValue } == [1, 2, 3, 4])
    }

    @Test("self-consistent renumbering cannot impersonate one package-issued four-window life")
    func selfConsistentRenumberingFailsClosed() throws {
        let original = try completedResult(
            producerMinimumNanoseconds: 1,
            observedDurationNanoseconds: 10_000_000_000
        )
        let renumberedSequences: [UInt64] = [10, 20, 30, 40]

        let windows = zip(original.windows, renumberedSequences).map { receipt, rawSequence in
            PassiveBluetoothPowerCycleObservationWindowReceipt(
                phase: receipt.phase,
                windowSequence: .init(rawValue: rawSequence),
                startedAtUptimeNanoseconds: receipt.startedAtUptimeNanoseconds,
                endedAtUptimeNanoseconds: receipt.endedAtUptimeNanoseconds,
                observedCandidateCount: receipt.observedCandidateCount
            )
        }
        let snapshots = try zip(original.observationSnapshots, renumberedSequences).map {
            snapshot, rawSequence in
            try PassiveBluetoothCandidateObservationSnapshot(
                observationSeriesIdentity: snapshot.observationSeriesIdentity,
                windowSequence: .init(rawValue: rawSequence),
                candidates: snapshot.candidates
            )
        }
        let correlation = PassiveBluetoothPowerCycleTargetCorrelation.assess(
            firstOff: snapshots[0],
            firstOn: snapshots[1],
            secondOff: snapshots[2],
            secondOn: snapshots[3]
        )
        let renumbered = PassiveBluetoothPowerCycleObservationResult(
            windows: windows,
            observationSnapshots: snapshots,
            correlation: correlation
        )

        let assessment = PassiveBluetoothPowerCycleObservationWindowDurationAssessment.assess(
            result: renumbered,
            minimumDurationNanoseconds: 10_000_000_000
        )

        #expect(assessment.status == .invalidWindowSet)
        #expect(!assessment.isDurationSufficient)
        #expect(assessment.observationResult == renumbered)
        #expect(assessment.windows.isEmpty)
    }

    @Test("assessment remains bound to the exact package-issued observation result")
    func assessmentCannotLoseItsSourceResult() throws {
        let first = try completedResult(
            producerMinimumNanoseconds: 1,
            observedDurationNanoseconds: 10_000_000_000
        )
        let second = try completedResult(
            producerMinimumNanoseconds: 1,
            observedDurationNanoseconds: 10_000_000_000
        )

        let firstAssessment = PassiveBluetoothPowerCycleObservationWindowDurationAssessment.assess(
            result: first,
            minimumDurationNanoseconds: 10_000_000_000
        )
        let secondAssessment = PassiveBluetoothPowerCycleObservationWindowDurationAssessment.assess(
            result: second,
            minimumDurationNanoseconds: 10_000_000_000
        )

        #expect(first != second)
        #expect(firstAssessment.observationResult == first)
        #expect(secondAssessment.observationResult == second)
        #expect(firstAssessment != secondAssessment)
    }

    @Test("zero required minimum fails closed")
    func zeroMinimumCannotPass() throws {
        let result = try completedResult(
            producerMinimumNanoseconds: 1,
            observedDurationNanoseconds: 10
        )

        let assessment = PassiveBluetoothPowerCycleObservationWindowDurationAssessment.assess(
            result: result,
            minimumDurationNanoseconds: 0
        )

        #expect(assessment.status == .invalidMinimumDuration)
        #expect(!assessment.isDurationSufficient)
        #expect(assessment.observationResult == result)
        #expect(assessment.minimumRequiredDurationNanoseconds == 0)
        #expect(assessment.windows.isEmpty)
    }
}