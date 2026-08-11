import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive CoreBluetooth Horizon minimum-duration gate")
struct PassiveCoreBluetoothObservationHorizonMinimumDurationGateTests {
    private typealias DurationGate = PassiveCoreBluetoothObservationHorizonMinimumDurationGate
    private typealias BoundaryGate = PassiveCoreBluetoothObservationBoundaryQueueGate

    private let authority = PassiveCoreBluetoothArtifactAuthorityContext(
        targetSessionGeneration: 7,
        authorityGeneration: 11
    )

    private let es80 = VehicleIdentity(
        manufacturer: "AOVOPRO",
        model: "ES80",
        displayName: "AOVOPRO ES80",
        protocolFamily: "Tuya / AOVOPRO (hardware validation pending)"
    )

    @Test("Experiment One minimum comes from the sealed capture policy")
    func fixedExperimentOneMinimum() {
        #expect(
            DurationGate.experimentOneMinimumDurationNanoseconds
                == PassiveBluetoothExperimentOneCapturePolicy
                    .minimumPostReadyObservationDurationNanoseconds
        )
        #expect(DurationGate.experimentOneMinimumDurationNanoseconds == 60_000_000_000)
    }

    @Test("one nanosecond before minimum remains ineligible")
    func justBeforeMinimumFailsClosed() {
        let ready: UInt64 = 1_000
        let minimum = DurationGate.experimentOneMinimumDurationNanoseconds
        let observed = ready + minimum - 1

        #expect(
            DurationGate.evaluate(
                readyAtUptimeNanoseconds: ready,
                observedAtUptimeNanoseconds: observed,
                minimumDurationNanoseconds: minimum
            ) == .waiting(required: minimum, observed: minimum - 1, remaining: 1)
        )
    }

    @Test("exact minimum is eligible without requiring an extra tick")
    func exactMinimumIsEligible() {
        let ready: UInt64 = 42
        let minimum = DurationGate.experimentOneMinimumDurationNanoseconds
        let observed = ready + minimum

        #expect(
            DurationGate.evaluate(
                readyAtUptimeNanoseconds: ready,
                observedAtUptimeNanoseconds: observed,
                minimumDurationNanoseconds: minimum
            ) == .eligible(required: minimum, observed: minimum)
        )
    }

    @Test("monotonic clock regression fails closed before subtraction")
    func regressedClockFailsClosed() {
        #expect(
            DurationGate.evaluate(
                readyAtUptimeNanoseconds: 100,
                observedAtUptimeNanoseconds: 99,
                minimumDurationNanoseconds: 60
            ) == .monotonicClockRegressed(ready: 100, observed: 99)
        )
    }

    @Test("zero minimum cannot silently authorize Horizon")
    func zeroMinimumFailsClosed() {
        #expect(
            DurationGate.evaluate(
                readyAtUptimeNanoseconds: 100,
                observedAtUptimeNanoseconds: 100,
                minimumDurationNanoseconds: 0
            ) == .invalidMinimumDuration
        )
    }

    @Test("near UInt64 maximum uses subtraction without overflow")
    func nearMaximumClockValuesRemainSafe() {
        let ready = UInt64.max - 10
        let observed = UInt64.max

        #expect(
            DurationGate.evaluate(
                readyAtUptimeNanoseconds: ready,
                observedAtUptimeNanoseconds: observed,
                minimumDurationNanoseconds: 11
            ) == .waiting(required: 11, observed: 10, remaining: 1)
        )
    }

    @Test("fresh committed Ready cannot mint trusted Horizon permit immediately")
    @MainActor
    func freshReadyFailsBeforeAnyHorizonLifecycleMutation() async throws {
        var fixture = try await committedReadyFixture()

        let status = DurationGate.currentExperimentOneStatus(for: fixture.epoch)
        guard case let .waiting(required, observed, remaining) = status else {
            Issue.record("fresh committed Ready unexpectedly reached the 60-second Horizon threshold")
            return
        }
        #expect(required == DurationGate.experimentOneMinimumDurationNanoseconds)
        #expect(observed < required)
        #expect(remaining == required - observed)

        do {
            _ = try DurationGate.authorizeExperimentOneHorizon(for: fixture.epoch)
            Issue.record("fresh committed Ready unexpectedly minted Horizon mutation authority")
        } catch let error as DurationGate.StateError {
            switch error {
            case let .minimumObservationDurationNotReached(required, observed):
                #expect(required == DurationGate.experimentOneMinimumDurationNanoseconds)
                #expect(observed < required)
            case .monotonicClockRegressed:
                Issue.record("system monotonic clock unexpectedly regressed during the fresh-Ready test")
            }
        }

        #expect(fixture.gate.phase == .observing)
        #expect(fixture.gate.activeTransaction == nil)
        #expect(!fixture.gate.isTerminal)

        // Keep the local gate mutable so this regression also proves the failed
        // authorization did not consume/reset lifecycle state through value copying.
        let resetWhileObserving = fixture.gate.resetForNewCaptureSession()
        #expect(!resetWhileObserving)
        #expect(fixture.gate.phase == .observing)
    }

    @MainActor
    private func committedReadyFixture() async throws -> (
        gate: BoundaryGate,
        epoch: PassiveCoreBluetoothObservationBoundaryTransactionDecision.CommittedReadyEpoch
    ) {
        var gate = BoundaryGate()
        let fence = PassiveCoreBluetoothArtifactAuthorityFence(authority: authority)
        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        let ready = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.beginReady(
            queueCutoff: 0,
            processedThrough: 0,
            authorityFence: fence,
            gate: &gate
        )
        let recordedReady = try await ready.recordBoundary(on: recorder)
        let epoch = try recordedReady.markBoundaryRecorded(
            on: &gate,
            lastProcessedQueueSequence: 0
        )
        return (gate, epoch)
    }
}
