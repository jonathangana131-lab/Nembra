import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive CoreBluetooth uncommitted Horizon recovery diagnostic")
struct PassiveCoreBluetoothUncommittedHorizonRecoveryDiagnosticTests {
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

    @Test("authority loss after Horizon admission but before recorder mutation leaves zero-H draining state")
    @MainActor
    func authorityLossBeforeHorizonMutationIsZeroMutationButStillDraining() async throws {
        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        let fence = PassiveCoreBluetoothArtifactAuthorityFence(authority: authority)
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()

        let ready = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.beginReady(
            queueCutoff: 2,
            processedThrough: 2,
            authorityFence: fence,
            gate: &gate
        )
        let recordedReady = try await ready.recordBoundary(on: recorder)
        let epoch = try recordedReady.markBoundaryRecorded(
            on: &gate,
            lastProcessedQueueSequence: 2
        )
        #expect((await recorder.snapshot()).observationBoundaries.count == 1)

        let horizon = try epoch.beginHorizon(
            queueCutoff: 4,
            processedThrough: 4,
            gate: &gate
        )
        guard case let .drainingHorizon(activeHorizon) = gate.phase else {
            Issue.record("Horizon admission must synchronously enter drainingHorizon.")
            return
        }

        let replacement = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: authority.targetSessionGeneration,
            authorityGeneration: authority.authorityGeneration + 1
        )
        try fence.transition(from: authority, to: replacement)

        await #expect(throws: PassiveCoreBluetoothArtifactAuthorityFence.StateError.authorityChanged(
            expected: authority,
            current: replacement
        )) {
            _ = try await horizon.recordBoundary(on: recorder)
        }

        // Canonical mutation-point authority rejected the H append before the
        // recorder mutation body ran: Ready is still the only durable boundary.
        #expect((await recorder.snapshot()).observationBoundaries.count == 1)

        // Current product truth: unlike Ready, Horizon has no producer-issued
        // zero-mutation rejection/abort path yet. The exact H transaction remains
        // installed and the ordinary reset cannot escape it. This characterization
        // is intentionally a diagnostic for controller/recovery composition, not a
        // claim that the lifecycle is recoverable today.
        #expect(gate.phase == .drainingHorizon(activeHorizon))
        #expect(!gate.isTerminal)
        #expect(gate.permittedDrainUpperBound(firstPending: 5, pendingTail: 5) == nil)
        let resetWhileUncommittedHorizon = gate.resetForNewCaptureSession()
        #expect(!resetWhileUncommittedHorizon)

        // The one-shot mutation permit is consumed by the failed attempt. Replaying
        // the admission cannot silently append H later under a different authority.
        await #expect(throws: PassiveCoreBluetoothObservationBoundaryMutationAttemptError.alreadyAttempted) {
            _ = try await horizon.recordBoundary(on: recorder)
        }
        #expect((await recorder.snapshot()).observationBoundaries.count == 1)
    }
}
