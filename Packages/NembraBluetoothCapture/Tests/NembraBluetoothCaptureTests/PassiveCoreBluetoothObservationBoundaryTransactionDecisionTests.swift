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

    private func makeRecorder() throws -> PassiveCoreBluetoothCaptureRecorder {
        try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )
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

    @Test("successful recorder mutation is required before the queue boundary can commit")
    @MainActor
    func recorderProofPrecedesQueueCommit() async throws {
        let recorder = try makeRecorder()
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let fence = makeFence()
        let ready = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.captureAndBegin(
            kind: .finiteAcquisitionReady,
            queueCutoff: 0,
            processedThrough: 0,
            authorityFence: fence,
            gate: &gate
        )

        let recorded = try await ready.recordBoundary(on: recorder)
        let committed = try recorded.markBoundaryRecorded(
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
        #expect(recorded.observedAtUptimeNanoseconds == ready.observedAtUptimeNanoseconds)
        #expect(recorded.observedAtDate == ready.observedAtDate)
        #expect(committed.queueKind == .finiteAcquisitionReady)
        #expect(committed.queueCutoff == ready.queueCutoff)
        #expect(committed.authority == ready.authority)
        #expect(gate.phase == .observing)
    }

    @Test("authority transition before recorder delivery executes zero stale boundary mutation")
    @MainActor
    func revokedAdmissionCannotMutateRecorder() async throws {
        let recorder = try makeRecorder()
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
            _ = try await ready.recordBoundary(on: recorder)
            Issue.record("A revoked Ready admission must not produce a RecordedBoundary token.")
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

    @Test("authority transition after recorder append rejects stale queue commit without erasing evidence")
    @MainActor
    func revokedRecordedBoundaryCannotCommitQueueTransaction() async throws {
        let recorder = try makeRecorder()
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let fence = makeFence()
        let ready = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.captureAndBegin(
            kind: .finiteAcquisitionReady,
            queueCutoff: 0,
            processedThrough: 0,
            authorityFence: fence,
            gate: &gate
        )

        let recorded = try await ready.recordBoundary(on: recorder)
        try fence.transition(from: authorityA, to: authorityB)

        do {
            _ = try recorded.markBoundaryRecorded(
                on: &gate,
                lastProcessedQueueSequence: 0
            )
            Issue.record("A revoked recorded boundary must not commit its queue transaction under newer authority.")
        } catch let error as PassiveCoreBluetoothObservationBoundaryQueueGate.StateError {
            #expect(error == .authorityChanged)
        } catch {
            Issue.record("Unexpected queue-gate error: \(error)")
        }

        let session = await recorder.snapshot()
        #expect(session.observationBoundaries.count == 1)
        guard case let .drainingReady(active) = gate.phase else {
            Issue.record("Rejected stale queue commit must keep the original Ready transaction unresolved.")
            return
        }
        #expect(active.authority == authorityA)
    }

    @Test("committed Ready cannot masquerade as a completed Horizon freeze")
    @MainActor
    func readyCannotCompleteHorizonFreeze() async throws {
        let recorder = try makeRecorder()
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let fence = makeFence()
        let ready = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.captureAndBegin(
            kind: .finiteAcquisitionReady,
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

        do {
            try committedReady.completeHorizonArtifactFreeze(on: &gate)
            Issue.record("A committed Ready boundary must not be accepted as a Horizon artifact freeze.")
        } catch let error as PassiveCoreBluetoothObservationBoundaryQueueGate.StateError {
            #expect(error == .horizonArtifactNotReady)
        } catch {
            Issue.record("Unexpected queue-gate error: \(error)")
        }

        #expect(gate.phase == .observing)
    }

    @Test("Horizon admission remains bound to committed Ready authority and processed prefix")
    @MainActor
    func bindsHorizonToCommittedReadyEpoch() async throws {
        let recorder = try makeRecorder()
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let fence = makeFence()
        let ready = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.captureAndBegin(
            kind: .finiteAcquisitionReady,
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
        #expect(horizon.authority == committedReady.authority)
        #expect(active.authority == committedReady.authority)
        #expect(active.queueCutoff == horizon.queueCutoff)
    }

    @Test("exact quiet Horizon reaches terminal only after recorder proof and queue commit")
    @MainActor
    func completesExactQuietHorizonTransaction() async throws {
        let recorder = try makeRecorder()
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let fence = makeFence()

        let ready = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.captureAndBegin(
            kind: .finiteAcquisitionReady,
            queueCutoff: 0,
            processedThrough: 0,
            authorityFence: fence,
            gate: &gate
        )
        let recordedReady = try await ready.recordBoundary(on: recorder)
        _ = try recordedReady.markBoundaryRecorded(
            on: &gate,
            lastProcessedQueueSequence: 0
        )

        let horizon = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.captureAndBegin(
            kind: .observationHorizon,
            queueCutoff: 0,
            processedThrough: 0,
            authorityFence: fence,
            gate: &gate
        )
        let recordedHorizon = try await horizon.recordBoundary(on: recorder)
        let committedHorizon = try recordedHorizon.markBoundaryRecorded(
            on: &gate,
            lastProcessedQueueSequence: 0
        )
        try committedHorizon.completeHorizonArtifactFreeze(on: &gate)

        let session = await recorder.snapshot()
        #expect(session.observationBoundaries.map(\.kind) == [
            .finiteAcquisitionReady,
            .observationHorizon
        ])
        #expect(gate.isTerminal)
        #expect(gate.terminalQueueCutoff == 0)
        #expect(gate.shouldDiscardQueuedEvidenceAfterTerminalHorizon(
            queueSequence: 1,
            authority: authorityA
        ))
    }
}
