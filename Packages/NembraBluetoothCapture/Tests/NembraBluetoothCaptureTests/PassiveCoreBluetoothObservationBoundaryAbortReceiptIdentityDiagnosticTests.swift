import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive CoreBluetooth abort receipt identity diagnostic")
struct PassiveCoreBluetoothObservationBoundaryAbortReceiptIdentityDiagnosticTests {
    private typealias Gate = PassiveCoreBluetoothObservationBoundaryQueueGate
    private typealias Decision = PassiveCoreBluetoothObservationBoundaryTransactionDecision
    private typealias Retirement = PassiveCoreBluetoothAbortedObservationQueueRetirement

    private struct Fixture {
        let recorder: PassiveCoreBluetoothCaptureRecorder
        let epoch: Decision.CommittedReadyEpoch
    }

    private struct PendingEvent: Equatable {
        let queueSequence: UInt64
        let authority: PassiveCoreBluetoothArtifactAuthorityContext
    }

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

    @Test("abort receipt retains exact transaction identity through retirement and recovery")
    @MainActor
    func foreignEqualScalarAbortReceiptCannotRecoverCurrentGate() async throws {
        var gateA = Gate()
        let fixtureA = try await committedReady(on: &gateA)
        var gateB = Gate()
        let fixtureB = try await committedReady(on: &gateB)

        #expect(fixtureA.epoch.authority == fixtureB.epoch.authority)
        #expect(fixtureA.epoch.queueCutoff == fixtureB.epoch.queueCutoff)
        #expect(fixtureA.epoch.transactionRevision == fixtureB.epoch.transactionRevision)
        #expect(fixtureA.epoch.transactionIdentity != fixtureB.epoch.transactionIdentity)

        let abortA = try gateA.abortObservationEpoch(fixtureA.epoch)
        let abortB = try gateB.abortObservationEpoch(fixtureB.epoch)

        // Required invariant: converting a producer-issued transaction into an abort
        // receipt must not erase the exact issuance identity that distinguished A/B.
        #expect(abortA != abortB)

        var pendingA: [PendingEvent] = []
        let retirementA = try Retirement.retire(
            from: &pendingA,
            currentLastEnqueuedEventSequence: fixtureA.epoch.queueCutoff,
            currentSettledQueueSequence: fixtureA.epoch.queueCutoff,
            drainIsIdle: true,
            abortedGate: gateA,
            identity: {
                .init(queueSequence: $0.queueSequence, authority: $0.authority)
            }
        )

        let recoveryError = captureStateError {
            try gateB.completeAbortedObservationRecovery(
                retirementA,
                currentLastEnqueuedEventSequence: fixtureB.epoch.queueCutoff,
                freshTargetSessionGeneration: authority.targetSessionGeneration + 1
            )
        }

        #expect(recoveryError == .abortRetirementReceiptMismatch)
        #expect(gateB.phase == .abortQuarantined(abortB))
        #expect(gateB.isAbortQuarantined)
    }

    @MainActor
    private func committedReady(on gate: inout Gate) async throws -> Fixture {
        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        let fence = PassiveCoreBluetoothArtifactAuthorityFence(authority: authority)
        let admission = try Decision.beginReady(
            queueCutoff: 4,
            processedThrough: 4,
            authorityFence: fence,
            gate: &gate
        )
        let recorded = try await admission.recordBoundary(on: recorder)
        let epoch = try recorded.markBoundaryRecorded(
            on: &gate,
            lastProcessedQueueSequence: 4
        )
        return Fixture(recorder: recorder, epoch: epoch)
    }

    private func captureStateError(
        _ operation: () throws -> Void
    ) -> Gate.StateError? {
        do {
            try operation()
            return nil
        } catch let error as Gate.StateError {
            return error
        } catch {
            return nil
        }
    }
}
