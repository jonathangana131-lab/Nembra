import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment One coordinator field-lock red team")
struct PassiveBluetoothExperimentOneCoordinatorFieldLockTests {
    private typealias Coordinator = PassiveBluetoothExperimentOneCoordinator
    private typealias CoordinatorError = PassiveBluetoothExperimentOneCoordinator.CoordinatorError

    @Test("NO-GO blocks every public procedure-advancing coordinator method without mutation")
    @MainActor
    func noGoBlocksEveryProcedureAdvancement() async throws {
        let coordinator = try Coordinator()
        let initialProgress = coordinator.status.powerCycleProgress

        @MainActor
        func requirePhysicalLock(_ operation: @MainActor () throws -> Void) {
            do {
                try operation()
                Issue.record("expected physical procedure lock")
            } catch let error as CoordinatorError {
                #expect(error == .physicalProcedureLocked)
            } catch {
                Issue.record("unexpected error: \(error)")
            }
        }

        requirePhysicalLock {
            try coordinator.startCurrentPowerCycleWindow()
        }
        requirePhysicalLock {
            _ = try coordinator.finishCurrentPowerCycleWindow()
        }
        requirePhysicalLock {
            try coordinator.confirmCorrelatedTargetAndBeginRediscovery()
        }
        requirePhysicalLock {
            try coordinator.restartPreparedRediscovery()
        }
        requirePhysicalLock {
            try coordinator.connectPreparedCapture()
        }

        do {
            _ = try await coordinator.finalizeObservationHorizon()
            Issue.record("expected physical procedure lock")
        } catch let error as CoordinatorError {
            #expect(error == .physicalProcedureLocked)
        } catch {
            Issue.record("unexpected error: \(error)")
        }

        let status = coordinator.status
        #expect(status.physicalProcedurePermitted == false)
        #expect(status.fieldExecutionStatus == .noGo(.finalComposedBuildNotAuthorized))
        #expect(status.powerCycleProgress == initialProgress)
        #expect(status.bluetoothState == nil)
        #expect(status.connection == .unavailable)
        #expect(status.correlation == .incomplete)
        #expect(status.hasPreparedCaptureAdmission == false)
        #expect(status.isCorrelatedTargetRediscovered == false)
        #expect(status.observationReady == false)
        #expect(status.canFinalizeObservationHorizon == false)
        #expect(status.artifactFinalized == false)
        #expect(status.foregroundIntegrityLost == false)
        #expect(coordinator.powerCycleResult == nil)
        #expect(coordinator.finalizedArtifact == nil)
    }
}
