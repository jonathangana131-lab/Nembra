import Dispatch
import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive CoreBluetooth boundary transaction decision")
struct PassiveCoreBluetoothObservationBoundaryTransactionDecisionTests {
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

    @Test("captures one pre-await decision and opens the exact matching ready transaction")
    @MainActor
    func capturesAndBeginsExactReadyTransaction() throws {
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let beforeUptime = DispatchTime.now().uptimeNanoseconds

        let admission = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.captureAndBegin(
            kind: .finiteAcquisitionReady,
            queueCutoff: 12,
            processedThrough: 9,
            authority: authority,
            gate: &gate
        )

        let afterUptime = DispatchTime.now().uptimeNanoseconds

        #expect(admission.queueKind == .finiteAcquisitionReady)
        #expect(admission.queueCutoff == 12)
        #expect(admission.processedThrough == 9)
        #expect(admission.authority == authority)
        #expect(admission.transaction.boundaryKind == admission.decision.queueKind)
        #expect(admission.transaction.queueCutoff == admission.decision.queueCutoff)
        #expect(admission.transaction.authority == admission.decision.authority)
        #expect(admission.decision.observedAtUptimeNanoseconds >= beforeUptime)
        #expect(admission.decision.observedAtUptimeNanoseconds <= afterUptime)
        #expect(gate.activeTransaction == admission.transaction)
    }

    @Test("malformed processed frontier fails before mutating the gate")
    @MainActor
    func malformedDecisionIsAtomic() {
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let original = gate

        do {
            _ = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.captureAndBegin(
                kind: .finiteAcquisitionReady,
                queueCutoff: 4,
                processedThrough: 5,
                authority: authority,
                gate: &gate
            )
            Issue.record("A decision whose recorder frontier exceeds its queue cutoff must fail closed.")
        } catch let error as PassiveCoreBluetoothObservationBoundaryDecision.StateError {
            #expect(error == .processedFrontierBeyondCutoff)
        } catch {
            Issue.record("Unexpected boundary-decision error: \(error)")
        }

        #expect(gate == original)
    }

    @Test("gate transition rejection leaves the prior lifecycle state unchanged")
    @MainActor
    func rejectedGateTransitionIsAtomic() {
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let original = gate

        do {
            _ = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.captureAndBegin(
                kind: .observationHorizon,
                queueCutoff: 0,
                processedThrough: 0,
                authority: authority,
                gate: &gate
            )
            Issue.record("Horizon cannot begin before Ready establishes the observation epoch.")
        } catch let error as PassiveCoreBluetoothObservationBoundaryQueueGate.StateError {
            #expect(error == .invalidTransition)
        } catch {
            Issue.record("Unexpected queue-gate error: \(error)")
        }

        #expect(gate == original)
    }

    @Test("horizon admission retains the exact ready authority and processed frontier")
    @MainActor
    func bindsHorizonToReadyEpoch() throws {
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let ready = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.captureAndBegin(
            kind: .finiteAcquisitionReady,
            queueCutoff: 4,
            processedThrough: 4,
            authority: authority,
            gate: &gate
        )
        try ready.markBoundaryRecorded(
            on: &gate,
            lastProcessedQueueSequence: 4,
            currentAuthority: authority
        )

        let horizon = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.captureAndBegin(
            kind: .observationHorizon,
            queueCutoff: 7,
            processedThrough: 5,
            authority: authority,
            gate: &gate
        )

        #expect(horizon.queueKind == .observationHorizon)
        #expect(horizon.queueCutoff == 7)
        #expect(horizon.processedThrough == 5)
        #expect(horizon.transaction.authority == ready.transaction.authority)
        #expect(gate.activeTransaction == horizon.transaction)
    }

    @Test("recorder hop preserves the exact sealed decision clocks and commits the same transaction")
    @MainActor
    func recordsAndCommitsSameSealedDecision() async throws {
        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let ready = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.captureAndBegin(
            kind: .finiteAcquisitionReady,
            queueCutoff: 0,
            processedThrough: 0,
            authority: authority,
            gate: &gate
        )

        try await ready.recordBoundary(on: recorder)
        try ready.markBoundaryRecorded(
            on: &gate,
            lastProcessedQueueSequence: 0,
            currentAuthority: authority
        )

        let session = await recorder.snapshot()
        let boundary = try #require(session.observationBoundaries.first)
        #expect(session.observationBoundaries.count == 1)
        #expect(boundary.kind == .finiteAcquisitionReady)
        #expect(boundary.recordSequenceWatermark == 0)
        #expect(boundary.observedAtUptimeNanoseconds == ready.decision.observedAtUptimeNanoseconds)
        #expect(boundary.observedAtDate == ready.decision.observedAtDate)
        #expect(gate.phase == .observing)
    }

    @Test("terminal helper cannot bless a horizon before its boundary is recorded")
    @MainActor
    func prematureTerminalFreezeFailsClosed() throws {
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let ready = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.captureAndBegin(
            kind: .finiteAcquisitionReady,
            queueCutoff: 3,
            processedThrough: 3,
            authority: authority,
            gate: &gate
        )
        try ready.markBoundaryRecorded(
            on: &gate,
            lastProcessedQueueSequence: 3,
            currentAuthority: authority
        )
        let horizon = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.captureAndBegin(
            kind: .observationHorizon,
            queueCutoff: 5,
            processedThrough: 4,
            authority: authority,
            gate: &gate
        )

        do {
            try horizon.completeHorizonArtifactFreeze(
                on: &gate,
                currentAuthority: authority
            )
            Issue.record("A horizon cannot become terminal before its durable boundary is recorded.")
        } catch let error as PassiveCoreBluetoothObservationBoundaryQueueGate.StateError {
            #expect(error == .horizonArtifactNotReady)
        } catch {
            Issue.record("Unexpected queue-gate error: \(error)")
        }

        #expect(gate.activeTransaction == horizon.transaction)
    }

    @Test("terminal helper advances only the sealed horizon transaction after exact-prefix commit")
    @MainActor
    func completesExactHorizonTransaction() throws {
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let ready = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.captureAndBegin(
            kind: .finiteAcquisitionReady,
            queueCutoff: 2,
            processedThrough: 2,
            authority: authority,
            gate: &gate
        )
        try ready.markBoundaryRecorded(
            on: &gate,
            lastProcessedQueueSequence: 2,
            currentAuthority: authority
        )
        let horizon = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.captureAndBegin(
            kind: .observationHorizon,
            queueCutoff: 6,
            processedThrough: 4,
            authority: authority,
            gate: &gate
        )
        try horizon.markBoundaryRecorded(
            on: &gate,
            lastProcessedQueueSequence: 6,
            currentAuthority: authority
        )
        try horizon.completeHorizonArtifactFreeze(
            on: &gate,
            currentAuthority: authority
        )

        #expect(gate.isTerminal)
        #expect(gate.terminalQueueCutoff == 6)
        #expect(gate.shouldDiscardQueuedEvidenceAfterTerminalHorizon(
            queueSequence: 7,
            authority: authority
        ))
    }
}
