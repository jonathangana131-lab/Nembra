import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive CoreBluetooth unrecorded Horizon recovery")
struct PassiveCoreBluetoothUnrecordedHorizonRecoveryTests {
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

    @Test("Horizon admission that fails before recorder mutation has an exact recovery path")
    @MainActor
    func admittedButUnrecordedHorizonCannotStrandLifecycle() async throws {
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
        let committedReady = try recordedReady.markBoundaryRecorded(
            on: &gate,
            lastProcessedQueueSequence: 2
        )

        _ = try committedReady.beginHorizon(
            queueCutoff: 4,
            processedThrough: 2,
            gate: &gate
        )

        // No Horizon recorder mutation has happened. The immutable recorder truth is
        // still exactly one Ready boundary, while the gate has already left observing.
        #expect((await recorder.snapshot()).observationBoundaries.count == 1)
        #expect(!gate.isTerminal)

        // The pre-H committed-Ready abort authority is deliberately not valid once
        // Horizon admission has started, and ordinary reset cannot erase the open
        // transaction. #488's recorded-H recovery is also inapplicable because there
        // is no producer-issued RecordedHorizonBoundary token yet.
        #expect(throws: PassiveCoreBluetoothObservationBoundaryQueueGate.StateError.invalidTransition) {
            _ = try gate.abortObservationEpoch(committedReady)
        }
        let resetWhileHorizonUnrecorded = gate.resetForNewCaptureSession()
        #expect(!resetWhileHorizonUnrecorded)

        Issue.record(
            "Horizon admission can enter drainingHorizon before any durable H mutation, but the current typestate has no producer-issued recovery authority for that exact zero-H-mutation state."
        )
    }
}
