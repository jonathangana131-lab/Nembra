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

    private var nextSessionAuthority: PassiveCoreBluetoothArtifactAuthorityContext {
        PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: authorityA.targetSessionGeneration + 1,
            authorityGeneration: 1
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

        let admission = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.beginReady(
            queueCutoff: 12,
            processedThrough: 9,
            authorityFence: fence,
            gate: &gate
        )

        let afterUptime = DispatchTime.now().uptimeNanoseconds
        let active = try #require(gate.activeTransaction)

        #expect(admission.queueCutoff == 12)
        #expect(admission.processedThrough == 9)
        #expect(admission.authority == authorityA)
        #expect(admission.observedAtUptimeNanoseconds >= beforeUptime)
        #expect(admission.observedAtUptimeNanoseconds <= afterUptime)
        #expect(active.boundaryKind == .finiteAcquisitionReady)
        #expect(active.queueCutoff == admission.queueCutoff)
        #expect(active.authority == admission.authority)
    }

    @Test("malformed recorder frontier fails before queue-gate mutation")
    @MainActor
    func malformedFrontierIsAtomic() {
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let original = gate

        do {
            _ = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.beginReady(
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

    @Test("successful Ready recorder mutation and queue commit mint the Horizon-capable epoch proof")
    @MainActor
    func recorderProofPrecedesReadyEpoch() async throws {
        let recorder = try makeRecorder()
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let fence = makeFence()
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

        let session = await recorder.snapshot()
        let boundary = try #require(session.observationBoundaries.first)
        #expect(session.observationBoundaries.count == 1)
        #expect(boundary.kind == .finiteAcquisitionReady)
        #expect(boundary.recordSequenceWatermark == 0)
        #expect(boundary.observedAtUptimeNanoseconds == ready.observedAtUptimeNanoseconds)
        #expect(boundary.observedAtDate == ready.observedAtDate)
        #expect(recordedReady.observedAtUptimeNanoseconds == ready.observedAtUptimeNanoseconds)
        #expect(committedReady.observedAtUptimeNanoseconds == ready.observedAtUptimeNanoseconds)
        #expect(committedReady.observedAtDate == ready.observedAtDate)
        #expect(committedReady.queueCutoff == ready.queueCutoff)
        #expect(committedReady.authority == ready.authority)
        #expect(gate.phase == .observing)
    }

    @Test("authority transition before Ready recorder delivery produces no epoch proof or durable boundary")
    @MainActor
    func revokedReadyCannotMutateRecorder() async throws {
        let recorder = try makeRecorder()
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let fence = makeFence()
        let ready = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.beginReady(
            queueCutoff: 0,
            processedThrough: 0,
            authorityFence: fence,
            gate: &gate
        )

        try fence.transition(from: authorityA, to: authorityB)

        do {
            _ = try await ready.recordBoundary(on: recorder)
            Issue.record("A revoked Ready admission must not produce a RecordedReadyBoundary token.")
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
            Issue.record("Rejected stale Ready recorder mutation must leave its exact transaction unresolved.")
            return
        }
        #expect(active.queueCutoff == ready.queueCutoff)
        #expect(active.authority == ready.authority)
    }

    @Test("authority transition after Ready append rejects stale queue commit without erasing evidence")
    @MainActor
    func revokedRecordedReadyCannotMintEpoch() async throws {
        let recorder = try makeRecorder()
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let fence = makeFence()
        let ready = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.beginReady(
            queueCutoff: 0,
            processedThrough: 0,
            authorityFence: fence,
            gate: &gate
        )

        let recordedReady = try await ready.recordBoundary(on: recorder)
        try fence.transition(from: authorityA, to: authorityB)

        do {
            _ = try recordedReady.markBoundaryRecorded(
                on: &gate,
                lastProcessedQueueSequence: 0
            )
            Issue.record("A revoked recorded Ready must not mint a committed Ready epoch.")
        } catch let error as PassiveCoreBluetoothObservationBoundaryQueueGate.StateError {
            #expect(error == .authorityChanged)
        } catch {
            Issue.record("Unexpected queue-gate error: \(error)")
        }

        let session = await recorder.snapshot()
        #expect(session.observationBoundaries.count == 1)
        guard case let .drainingReady(active) = gate.phase else {
            Issue.record("Rejected stale Ready queue commit must keep the original transaction unresolved.")
            return
        }
        #expect(active.authority == authorityA)
    }

    @Test("equal-valued second fence cannot substitute for the fence that committed Ready")
    @MainActor
    func horizonCannotSwitchAuthorityStores() async throws {
        let recorder = try makeRecorder()
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let canonicalFence = makeFence()
        let equalButDistinctFence = makeFence()

        let ready = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.beginReady(
            queueCutoff: 0,
            processedThrough: 0,
            authorityFence: canonicalFence,
            gate: &gate
        )
        let recordedReady = try await ready.recordBoundary(on: recorder)
        let committedReady = try recordedReady.markBoundaryRecorded(
            on: &gate,
            lastProcessedQueueSequence: 0
        )

        #expect(equalButDistinctFence.currentAuthority == authorityA)
        try canonicalFence.transition(from: authorityA, to: authorityB)
        #expect(equalButDistinctFence.currentAuthority == authorityA)

        do {
            _ = try committedReady.beginHorizon(
                queueCutoff: 0,
                processedThrough: 0,
                gate: &gate
            )
            Issue.record("Horizon must inherit the committed Ready fence identity, not an equal-valued second store.")
        } catch let error as PassiveCoreBluetoothArtifactAuthorityFence.StateError {
            #expect(
                error == .authorityChanged(
                    expected: authorityA,
                    current: authorityB
                )
            )
        } catch {
            Issue.record("Unexpected Horizon admission error: \(error)")
        }

        #expect(gate.phase == .observing)
    }

    @Test("retired Ready epoch cannot follow the canonical fence into a fresh lifecycle")
    @MainActor
    func retiredReadyEpochCannotMintLaterHorizon() async throws {
        let oldRecorder = try makeRecorder()
        var oldGate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let fence = makeFence()

        let oldReady = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.beginReady(
            queueCutoff: 0,
            processedThrough: 0,
            authorityFence: fence,
            gate: &oldGate
        )
        let oldRecordedReady = try await oldReady.recordBoundary(on: oldRecorder)
        let oldCommittedReady = try oldRecordedReady.markBoundaryRecorded(
            on: &oldGate,
            lastProcessedQueueSequence: 0
        )

        try fence.transition(from: authorityA, to: nextSessionAuthority)

        let freshRecorder = try makeRecorder()
        var freshGate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let freshReady = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.beginReady(
            queueCutoff: 0,
            processedThrough: 0,
            authorityFence: fence,
            gate: &freshGate
        )
        let freshRecordedReady = try await freshReady.recordBoundary(on: freshRecorder)
        let freshCommittedReady = try freshRecordedReady.markBoundaryRecorded(
            on: &freshGate,
            lastProcessedQueueSequence: 0
        )

        #expect(freshCommittedReady.authority == nextSessionAuthority)
        do {
            _ = try oldCommittedReady.beginHorizon(
                queueCutoff: 0,
                processedThrough: 0,
                gate: &freshGate
            )
            Issue.record("A retired Ready epoch must never inherit a later lifecycle's current authority.")
        } catch let error as PassiveCoreBluetoothArtifactAuthorityFence.StateError {
            #expect(
                error == .authorityChanged(
                    expected: authorityA,
                    current: nextSessionAuthority
                )
            )
        } catch {
            Issue.record("Unexpected stale-epoch error: \(error)")
        }
        #expect(freshGate.phase == .observing)

        let freshHorizon = try freshCommittedReady.beginHorizon(
            queueCutoff: 0,
            processedThrough: 0,
            gate: &freshGate
        )
        #expect(freshHorizon.authority == nextSessionAuthority)
        #expect(freshGate.activeTransaction?.authority == nextSessionAuthority)
    }

    @Test("Horizon admission inherits committed Ready authority and processed-prefix constraints")
    @MainActor
    func horizonInheritsCommittedReadyEpoch() async throws {
        let recorder = try makeRecorder()
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let fence = makeFence()

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
            queueCutoff: 7,
            processedThrough: 5,
            gate: &gate
        )

        let active = try #require(gate.activeTransaction)
        #expect(horizon.queueCutoff == 7)
        #expect(horizon.processedThrough == 5)
        #expect(horizon.authority == committedReady.authority)
        #expect(active.boundaryKind == .observationHorizon)
        #expect(active.authority == committedReady.authority)
        #expect(active.queueCutoff == horizon.queueCutoff)
    }

    @Test("exact quiet Horizon reaches terminal only after recorder proof and queue commit")
    @MainActor
    func completesExactQuietHorizonTransaction() async throws {
        let recorder = try makeRecorder()
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let fence = makeFence()

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
