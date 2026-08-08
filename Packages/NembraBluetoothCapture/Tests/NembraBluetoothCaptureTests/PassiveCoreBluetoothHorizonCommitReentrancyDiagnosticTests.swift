import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive CoreBluetooth Horizon append/commit reentrancy diagnostic")
struct PassiveCoreBluetoothHorizonCommitReentrancyDiagnosticTests {
    private let authorityA = PassiveCoreBluetoothArtifactAuthorityContext(
        targetSessionGeneration: 7,
        authorityGeneration: 11
    )

    private let es80 = VehicleIdentity(
        manufacturer: "AOVOPRO",
        model: "ES80",
        displayName: "AOVOPRO ES80",
        protocolFamily: "Tuya / AOVOPRO (hardware validation pending)"
    )

    @Test("durable Horizon append must not remain stranded after authority changes before queue commit")
    @MainActor
    func durableHorizonAppendThenAuthorityAdvanceExposesMissingRecovery() async throws {
        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        let fence = PassiveCoreBluetoothArtifactAuthorityFence(authority: authorityA)
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()

        let ready = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.beginReady(
            queueCutoff: 0,
            processedThrough: 0,
            authorityFence: fence,
            gate: &gate
        )
        let recordedReady = try await ready.recordBoundary(on: recorder)
        let committedReady = try recordedReady.markBoundaryRecorded(
            on: &gate,
            lastProcessedQueueSequence: 0
        )

        let horizon = try committedReady.beginHorizon(
            queueCutoff: 0,
            processedThrough: 0,
            gate: &gate
        )
        let recordedHorizon = try await horizon.recordBoundary(on: recorder)
        let activeHorizon = try #require(gate.activeTransaction)

        let afterAppend = await recorder.snapshot()
        #expect(afterAppend.observationBoundaries.map(\.kind) == [
            .finiteAcquisitionReady,
            .observationHorizon
        ])
        #expect(gate.phase == .drainingHorizon(activeHorizon))

        let authorityB = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: authorityA.targetSessionGeneration,
            authorityGeneration: authorityA.authorityGeneration + 1
        )
        try fence.transition(from: authorityA, to: authorityB)

        #expect(throws: PassiveCoreBluetoothObservationBoundaryQueueGate.StateError.authorityChanged) {
            _ = try recordedHorizon.markBoundaryRecorded(
                on: &gate,
                lastProcessedQueueSequence: 0
            )
        }

        let afterRejectedCommit = await recorder.snapshot()
        #expect(afterRejectedCommit.observationBoundaries.map(\.kind) == [
            .finiteAcquisitionReady,
            .observationHorizon
        ])

        if gate.phase == .drainingHorizon(activeHorizon) {
            Issue.record(
                "BLOCKER: the exact Horizon boundary is already durable, but authority-change rejection leaves the gate permanently stranded in drainingHorizon with no producer-issued recovery/quarantine path."
            )
        }

        #expect(!gate.resetForNewCaptureSession())
    }
}
