import Testing
@testable import NembraBluetoothCapture

struct PassiveBluetoothPowerCycleWindowDurationAssessmentTests {
    private let tenSeconds: UInt64 = 10_000_000_000

    @Test("short producer policy cannot masquerade as the ten-second experiment policy")
    func shortProducerMinimumFailsDownstreamTenSecondAssessment() throws {
        let result = try makeResult(windowDurationNanoseconds: 5_000_000_000)

        let assessment = PassiveBluetoothPowerCycleWindowDurationAssessment.assess(
            result: result,
            minimumWindowDurationNanoseconds: tenSeconds
        )

        #expect(assessment.status == .insufficientDuration)
        #expect(!assessment.isDurationSufficient)
        #expect(assessment.minimumRequiredWindowDurationNanoseconds == tenSeconds)
        #expect(assessment.observedWindowDurationsNanoseconds == Array(repeating: 5_000_000_000, count: 4))
        #expect(assessment.insufficientPhases == PassiveBluetoothPowerCycleObservationPhase.allCases)
    }

    @Test("all four exact ten-second receipt windows satisfy the explicit policy")
    func exactTenSecondWindowsAreSufficient() throws {
        let result = try makeResult(windowDurationNanoseconds: tenSeconds)

        let assessment = PassiveBluetoothPowerCycleWindowDurationAssessment.assess(
            result: result,
            minimumWindowDurationNanoseconds: tenSeconds
        )

        #expect(assessment.status == .sufficient)
        #expect(assessment.isDurationSufficient)
        #expect(assessment.minimumRequiredWindowDurationNanoseconds == tenSeconds)
        #expect(assessment.observedWindowDurationsNanoseconds == Array(repeating: tenSeconds, count: 4))
        #expect(assessment.insufficientPhases.isEmpty)
    }

    @Test("zero required duration fails closed")
    func zeroRequiredMinimumIsInvalid() throws {
        let result = try makeResult(windowDurationNanoseconds: tenSeconds)

        let assessment = PassiveBluetoothPowerCycleWindowDurationAssessment.assess(
            result: result,
            minimumWindowDurationNanoseconds: 0
        )

        #expect(assessment.status == .invalidMinimumDuration)
        #expect(!assessment.isDurationSufficient)
        #expect(assessment.observedWindowDurationsNanoseconds.isEmpty)
        #expect(assessment.insufficientPhases.isEmpty)
    }

    @Test("receipt sequences must remain bound to the snapshots that earned correlation")
    func receiptSnapshotSequenceMismatchFailsClosed() throws {
        let result = try makeResult(windowDurationNanoseconds: tenSeconds)
        var windows = result.windows
        let original = windows[0]
        windows[0] = PassiveBluetoothPowerCycleObservationWindowReceipt(
            phase: original.phase,
            windowSequence: windows[1].windowSequence,
            startedAtUptimeNanoseconds: original.startedAtUptimeNanoseconds,
            endedAtUptimeNanoseconds: original.endedAtUptimeNanoseconds,
            observedCandidateCount: original.observedCandidateCount
        )
        let mismatched = PassiveBluetoothPowerCycleObservationResult(
            windows: windows,
            observationSnapshots: result.observationSnapshots,
            correlation: result.correlation
        )

        let assessment = PassiveBluetoothPowerCycleWindowDurationAssessment.assess(
            result: mismatched,
            minimumWindowDurationNanoseconds: tenSeconds
        )

        #expect(assessment.status == .resultProvenanceMismatch)
        #expect(!assessment.isDurationSufficient)
        #expect(assessment.observedWindowDurationsNanoseconds.isEmpty)
    }

    @Test("backwards receipt clock fails closed without underflow")
    func nonMonotonicReceiptClockFailsClosed() throws {
        let result = try makeResult(windowDurationNanoseconds: tenSeconds)
        var windows = result.windows
        let original = windows[2]
        windows[2] = PassiveBluetoothPowerCycleObservationWindowReceipt(
            phase: original.phase,
            windowSequence: original.windowSequence,
            startedAtUptimeNanoseconds: original.endedAtUptimeNanoseconds + 1,
            endedAtUptimeNanoseconds: original.endedAtUptimeNanoseconds,
            observedCandidateCount: original.observedCandidateCount
        )
        let malformed = PassiveBluetoothPowerCycleObservationResult(
            windows: windows,
            observationSnapshots: result.observationSnapshots,
            correlation: result.correlation
        )

        let assessment = PassiveBluetoothPowerCycleWindowDurationAssessment.assess(
            result: malformed,
            minimumWindowDurationNanoseconds: tenSeconds
        )

        #expect(assessment.status == .nonMonotonicWindowClock)
        #expect(!assessment.isDurationSufficient)
        #expect(assessment.observedWindowDurationsNanoseconds.isEmpty)
    }

    private func makeResult(
        windowDurationNanoseconds: UInt64
    ) throws -> PassiveBluetoothPowerCycleObservationResult {
        var ledger = PassiveBluetoothPowerCycleObservationLedger(
            minimumWindowDurationNanoseconds: 1
        )
        var startedAtUptimeNanoseconds: UInt64 = 1_000
        var finalResult: PassiveBluetoothPowerCycleObservationResult?

        for phase in PassiveBluetoothPowerCycleObservationPhase.allCases {
            let endedAtUptimeNanoseconds = startedAtUptimeNanoseconds + windowDurationNanoseconds
            finalResult = try ledger.completeWindow(
                phase: phase,
                startedAtUptimeNanoseconds: startedAtUptimeNanoseconds,
                endedAtUptimeNanoseconds: endedAtUptimeNanoseconds,
                candidates: []
            )
            startedAtUptimeNanoseconds = endedAtUptimeNanoseconds + 1_000
        }

        return try #require(finalResult)
    }
}
