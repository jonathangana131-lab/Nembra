import Testing
@testable import NembraBluetoothCapture

@Suite("Passive Bluetooth Experiment One coordinator")
struct PassiveBluetoothExperimentOneCoordinatorTests {
    typealias Coordinator = PassiveBluetoothExperimentOneCoordinator
    typealias CoordinatorError = PassiveBluetoothExperimentOneCoordinator.CoordinatorError

    @Test("current NO-GO coordinator creates no actionable Experiment One state")
    @MainActor
    func currentNoGoStatus() throws {
        let coordinator = try Coordinator()
        let status = coordinator.status

        #expect(status.physicalProcedurePermitted == false)
        #expect(status.physicalProcedureStatus == .noGo(.finalComposedBuildNotAuthorized))
        #expect(status.correlation == .incomplete)
        #expect(status.isCorrelatedTargetConfirmed == false)
        #expect(status.isCorrelatedTargetRediscovered == false)
        #expect(status.connection == .idle)
        #expect(status.observationReady == false)
        #expect(status.canFinalizeObservationHorizon == false)
        #expect(status.artifactFinalized == false)
        #expect(status.artifactSealedButTransportTeardownFailed == false)
        #expect(status.foregroundIntegrityLost == false)
        #expect(coordinator.finalizedArtifact == nil)
    }

    @Test("NO-GO blocks power-cycle scanning before evidence state advances")
    @MainActor
    func noGoBlocksPowerCycleStart() throws {
        let coordinator = try Coordinator()
        let initialProgress = coordinator.status.powerCycleProgress

        expectCoordinatorFailure(.physicalProcedureLocked) {
            try coordinator.startCurrentPowerCycleWindow()
        }

        #expect(coordinator.status.powerCycleProgress == initialProgress)
        #expect(coordinator.status.correlation == .incomplete)
        #expect(coordinator.status.artifactFinalized == false)
    }

    @Test("NO-GO blocks confirmation, rediscovery, and sealed admission without caller authority")
    @MainActor
    func noGoBlocksProcedureAdvancement() throws {
        let coordinator = try Coordinator()

        expectCoordinatorFailure(.physicalProcedureLocked) {
            try coordinator.confirmCorrelatedTarget()
        }
        expectCoordinatorFailure(.physicalProcedureLocked) {
            try coordinator.startPassiveRediscovery()
        }
        expectCoordinatorFailure(.physicalProcedureLocked) {
            try coordinator.connectRediscoveredCorrelatedTarget()
        }

        let status = coordinator.status
        #expect(status.isCorrelatedTargetConfirmed == false)
        #expect(status.isCorrelatedTargetRediscovered == false)
        #expect(status.connection == .idle)
        #expect(status.observationReady == false)
    }

    @Test("NO-GO blocks terminal Horizon and cannot fabricate a shareable artifact")
    @MainActor
    func noGoBlocksFinalization() async throws {
        let coordinator = try Coordinator()

        do {
            _ = try await coordinator.finalizeObservationHorizon()
            Issue.record("expected physical procedure lock")
        } catch let error as CoordinatorError {
            #expect(error == .physicalProcedureLocked)
        } catch {
            Issue.record("unexpected error: \(error)")
        }

        #expect(coordinator.finalizedArtifact == nil)
        #expect(coordinator.status.artifactFinalized == false)
    }

    @Test("abandonment remains available while NO-GO and never creates authority")
    @MainActor
    func abandonmentIsAlwaysSafe() throws {
        let coordinator = try Coordinator()

        coordinator.abandonExperiment()

        #expect(coordinator.status.physicalProcedurePermitted == false)
        #expect(coordinator.status.correlation == .incomplete)
        #expect(coordinator.status.connection == .idle)
        #expect(coordinator.finalizedArtifact == nil)
    }

    @MainActor
    private func expectCoordinatorFailure(
        _ expected: CoordinatorError,
        operation: () throws -> Void,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        do {
            try operation()
            Issue.record("expected coordinator failure: \(expected)", sourceLocation: sourceLocation)
        } catch let error as CoordinatorError {
            #expect(error == expected, sourceLocation: sourceLocation)
        } catch {
            Issue.record("unexpected error: \(error)", sourceLocation: sourceLocation)
        }
    }
}
