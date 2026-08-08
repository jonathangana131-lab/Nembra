import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment One canonical ES80 coordinator")
struct PassiveBluetoothExperimentOneCoordinatorCanonicalES80Tests {
    @Test @MainActor
    func packageOwnsControllerAndCanonicalCorrelationProducer() throws {
        let coordinator = try PassiveBluetoothExperimentOneCoordinator()

        let progress = try #require(coordinator.powerCycleObservationSession.progress)
        #expect(progress.phase == .firstPoweredOff)
        #expect(progress.completedWindowCount == 0)
        #expect(coordinator.hasPreparedCaptureAdmission == false)
        #expect(coordinator.preparedCorrelatedTargetIdentifier == nil)
        #expect(coordinator.controller.hasTargetSession == false)
    }
}
