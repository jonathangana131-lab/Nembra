import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

/// Diagnostic-only proof for the committed-Horizon / pre-artifact-freeze partial state.
///
/// The production controller can enter this state after the durable Horizon append and
/// exact queue commit succeed, then fail while awaiting immutable artifact materialization
/// or while revalidating authority before `completeHorizonArtifactFreeze(...)`.
///
/// This suite intentionally does not invent recovery authority. It pins the current
/// truthful state so a successor can add a distinct producer-issued quarantine/recovery
/// transition without misclassifying it as either pre-commit Horizon failure or terminal
/// artifact success.
@Suite("Committed Horizon before artifact freeze diagnostic")
struct PassiveCoreBluetoothCommittedHorizonPreFreezeRecoveryDiagnosticTests {
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

    @Test("committed Horizon with no artifact freeze preserves durable H and has no existing recovery transition")
    @MainActor
    func committedHorizonPreFreezeStateIsFailClosedButStranded() async throws {
        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        let fence = PassiveCoreBluetoothArtifactAuthorityFence(authority: authority)
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()

        let readyAdmission = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.beginReady(
            queueCutoff: 0,
            processedThrough: 0,
            authorityFence: fence,
            gate: &gate
        )
        let recordedReady = try await readyAdmission.recordBoundary(on: recorder)
        let committedReady = try recordedReady.markBoundaryRecorded(
            on: &gate,
            lastProcessedQueueSequence: 0
        )

        let horizonAdmission = try committedReady.beginHorizon(
            queueCutoff: 0,
            processedThrough: 0,
            gate: &gate
        )
        let recordedHorizon = try await horizonAdmission.recordBoundary(on: recorder)
        let committedHorizon = try recordedHorizon.markBoundaryRecorded(
            on: &gate,
            lastProcessedQueueSequence: 0
        )

        let snapshot = await recorder.snapshot()
        #expect(snapshot.observationBoundaries.map(\.kind) == [
            .finiteAcquisitionReady,
            .observationHorizon
        ])

        let activeHorizon = try #require(gate.activeTransaction)
        #expect(gate.phase == .horizonBoundaryRecorded(activeHorizon))
        #expect(!gate.isTerminal)

        // A post-H callback is outside the accepted artifact interval and must remain
        // withheld while the artifact has not been truthfully frozen.
        #expect(gate.permittedDrainUpperBound(firstPending: 1, pendingTail: 1) == nil)
        #expect(!gate.resetForNewCaptureSession())

        // Existing abandonment grammar only covers pre-H / pre-H-commit states.
        // It cannot truthfully relabel this already queue-committed Horizon.
        #expect(throws: PassiveCoreBluetoothObservationBoundaryQueueGate.StateError.invalidTransition) {
            _ = try gate.abortObservationEpoch(committedReady)
        }
        #expect(throws: PassiveCoreBluetoothObservationBoundaryQueueGate.StateError.invalidTransition) {
            _ = try gate.abortRecordedHorizonBeforeGateCommit(recordedHorizon)
        }

        // The only current forward transition is terminal artifact freeze. A caller
        // whose immutable artifact read/validation failed must not invoke it merely
        // to escape the state; doing so would falsely promote failed sealing to success.
        #expect(committedHorizon.authority == authority)
        #expect((await recorder.snapshot()).observationBoundaries.count == 2)
    }
}
