import Dispatch
import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive CoreBluetooth boundary transaction composition")
struct PassiveCoreBluetoothObservationBoundaryTransactionDecisionTests {
    private let authorityA = PassiveCoreBluetoothArtifactAuthorityContext(
        targetSessionGeneration: 7,
        authorityGeneration: 11
    )

    private var authorityB: PassiveCoreBluetoothArtifactAuthorityContext {
        PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: authorityA.targetSessionGeneration,
            authorityGeneration: authorityA.authorityGeneration + 1
        )
    }

    private let es80 = VehicleIdentity(
        manufacturer: "AOVOPRO",
        model: "ES80",
        displayName: "AOVOPRO ES80",
        protocolFamily: "Tuya / AOVOPRO (hardware validation pending)"
    )

    private func makeFence() -> PassiveCoreBluetoothArtifactAuthorityFence {
        PassiveCoreBluetoothArtifactAuthorityFence(authority: authorityA)
    }

    @Test("captures one exact Ready admission before the first actor hop")
    @MainActor
    func capturesExactReadyAdmission() throws {
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let fence = makeFence()
        let beforeUptime = DispatchTime.now().uptimeNanoseconds

        let admission = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.captureAndBegin(
            kind: .finiteAcquisitionReady,
            queueCutoff: 12,
            processedThrough: 9,
            authorityFence: fence,
            gate: &gate
        )

        let afterUptime = DispatchTime.now().uptimeNanoseconds
        let active = try #require(gate.activeTransaction)

        #expect(admission.queueKind == .finiteAcquisitionReady)
        #expect(admission.queueCutoff == 12)
        #expect(admission.processedThrough == 9)
        #expect(admission.authority == authorityA)
        #expect(admission.observedAtUptimeNanoseconds >= beforeUptime)
        #expect(admission.observedAtUptimeNanoseconds <= afterUptime)
        #expect(active.boundaryKind == admission.queueKind)
        #expect(active.queueCutoff == admission.queueCutoff)
        #expect(active.authority == admission.authority)
    }

    @Test("malformed recorder frontier fails before queue-gate mutation")
    @MainActor
    func malformedFrontierIsAtomic() {
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let original = gate

        do {
            _ = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.captureAndBegin(
                kind: .finiteAcquisitionReady,
                queueCutoff: 4,
                processedThrough: 5,
                authorityFence: makeFence(),
                gate: &gate
            )
            Issue.record("A recorder frontier beyond the queue cutoff must fail closed.")
        } catch let error as PassiveCoreBluetoothObservationBoundaryDecision.StateError {
            #expect(error == .processedFrontierBeyondCutoff)
        } catch {
            Issue.record("Unexpected admission error: \(error)")
        }

        #expect(gate == original)
    }

    @Test("recorder hop preserves exact clocks and the same sealed Ready transaction")
    @MainActor
    func recordsAndCommitsExactReadyAdmission() async throws {
        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let fence = makeFence()
        let ready = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.captureAndBegin(
            kind: .finiteAcquisitionReady,
            queueCutoff: 0,
            processedThrough: 0,
            authorityFence: fence,
            gate: &gate
        )

        try await ready.recordBoundary(on: recorder)
        try ready.markBoundaryRecorded(
            on: &gate,
            lastProcessedQueueSequence: 0
        )

        let session = await recorder.snapshot()
        let boundary = try #require(session.observationBoundaries.first)
        #expect(session.observationBoundaries.count == 1)
        #expect(boundary.kind == .finiteAcquisitionReady)
        #expect(boundary.recordSequenceWatermark == 0)
        #expect(boundary.observedAtUptimeNanoseconds == ready.observedAtUptimeNanoseconds)
        #expect(boundary.observedAtDate == ready.observedAtDate)
        #expect(gate.phase == .observing)
    }

    @Test("authority transition before recorder delivery executes zero stale boundary mutation")
    @MainActor
    func revokedAdmissionCannotMutateRecorder() async throws {
        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let fence = makeFence()
        let ready = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.captureAndBegin(
            kind: .finiteAcquisitionReady,
            queueCutoff: 0,
            processedThrough: 0,
            authorityFence: fence,
            gate: &gate
        )

        try fence.transition(from: authorityA, to: authorityB)

        do {
            try await ready.recordBoundary(on: recorder)
            Issue.record("A revoked Ready admission must not append durable boundary evidence.")
        } catch let error as PassiveCoreBluetoothArtifactAuthorityFence.StateError {
            #expect(
                error == .authorityChanged(
                    expected: authorityA,
                    current: authorityB
                )
            )
        } catch {
            Issue.record("Unexpected authority-fence error: \(error)")
        }

        let session = await recorder.snapshot()
        #expect(session.observationBoundaries.isEmpty)
        guard case let .drainingReady(active) = gate.phase else {
            Issue.record("Rejected stale recorder mutation must leave the exact admitted Ready unresolved.")
            return
        }
        #expect(active.queueCutoff == ready.queueCutoff)
        #expect(active.authority == ready.authority)
    }

    @Test("authority transition after recorder append prevents stale queue commit")
    @MainActor
    func revokedAdmissionCannotCommitQueueTransaction() async throws {
        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let fence = makeFence()
        let ready = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.captureAndBegin(
            kind: .finiteAcquisitionReady,
            queueCutoff: 0,
            processedThrough: 0,
            authorityFence: fence,
            gate: &gate
        )

        try await ready.recordBoundary(on: recorder)
        try fence.transition(from: authorityA, to: authorityB)

        do {
            try ready.markBoundaryRecorded(
                on: &gate,
                lastProcessedQueueSequence: 0
            )
            Issue.record("A revoked admission must not commit its queue transaction under newer authority.")
        } catch let error as PassiveCoreBluetoothObservationBoundaryQueueGate.StateError {
            #expect(error == .authorityChanged)
        } catch {
            Issue.record("Unexpected queue-gate error: \(error)")
        }

        guard case let .drainingReady(active) = gate.phase else {
            Issue.record("Rejected stale queue commit must keep the original Ready transaction unresolved.")
            return
        }
        #expect(active.authority == authorityA)
    }

    @Test("Horizon admission remains bound to the Ready authority and exact processed prefix")
    @MainActor
    func bindsHorizonToReadyEpoch() throws {
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let fence = makeFence()
        let ready = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.captureAndBegin(
            kind: .finiteAcquisitionReady,
            queueCutoff: 4,
            processedThrough: 4,
            authorityFence: fence,
            gate: &gate
        )
        try ready.markBoundaryRecorded(
            on: &gate,
            lastProcessedQueueSequence: 4
        )

        let horizon = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.captureAndBegin(
            kind: .observationHorizon,
            queueCutoff: 7,
            processedThrough: 5,
            authorityFence: fence,
            gate: &gate
        )

        let active = try #require(gate.activeTransaction)
        #expect(horizon.queueKind == .observationHorizon)
        #expect(horizon.queueCutoff == 7)
        #expect(horizon.processedThrough == 5)
        #expect(horizon.authority == ready.authority)
        #expect(active.authority == ready.authority)
        #expect(active.queueCutoff == horizon.queueCutoff)
    }

    @Test("terminal completion is impossible before the sealed Horizon boundary commits")
    @MainActor
    func prematureHorizonFreezeFailsClosed() throws {
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let fence = makeFence()
        let ready = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.captureAndBegin(
            kind: .finiteAcquisitionReady,
            queueCutoff: 3,
            processedThrough: 3,
            authorityFence: fence,
            gate: &gate
        )
        try ready.markBoundaryRecorded(
            on: &gate,
            lastProcessedQueueSequence: 3
        )
        let horizon = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.captureAndBegin(
            kind: .observationHorizon,
            queueCutoff: 5,
            processedThrough: 4,
            authorityFence: fence,
            gate: &gate
        )

        do {
            try horizon.completeHorizonArtifactFreeze(on: &gate)
            Issue.record("Horizon cannot become terminal before its durable boundary commits.")
        } catch let error as PassiveCoreBluetoothObservationBoundaryQueueGate.StateError {
            #expect(error == .horizonArtifactNotReady)
        } catch {
            Issue.record("Unexpected queue-gate error: \(error)")
        }

        #expect(gate.activeTransaction?.queueCutoff == horizon.queueCutoff)
        #expect(gate.activeTransaction?.authority == horizon.authority)
    }

    @Test("exact Horizon transaction reaches terminal only after prefix commit")
    @MainActor
    func completesExactHorizonTransaction() throws {
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let fence = makeFence()
        let ready = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.captureAndBegin(
            kind: .finiteAcquisitionReady,
            queueCutoff: 2,
            processedThrough: 2,
            authorityFence: fence,
            gate: &gate
        )
        try ready.markBoundaryRecorded(
            on: &gate,
            lastProcessedQueueSequence: 2
        )
        let horizon = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.captureAndBegin(
            kind: .observationHorizon,
            queueCutoff: 6,
            processedThrough: 4,
            authorityFence: fence,
            gate: &gate
        )
        try horizon.markBoundaryRecorded(
            on: &gate,
            lastProcessedQueueSequence: 6
        )
        try horizon.completeHorizonArtifactFreeze(on: &gate)

        #expect(gate.isTerminal)
        #expect(gate.terminalQueueCutoff == 6)
        #expect(gate.shouldDiscardQueuedEvidenceAfterTerminalHorizon(
            queueSequence: 7,
            authority: authorityA
        ))
    }
}
