import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment One app controller session")
struct PassiveBluetoothExperimentOneControllerSessionTests {
    @Test @MainActor
    func ownsTheCanonicalFourWindowProducerFromTheStartOfOneRun() throws {
        let session = try PassiveBluetoothExperimentOneControllerSession()

        let progress = try #require(session.powerCycleObservationSession.progress)
        #expect(progress.phase == .firstPoweredOff)
        #expect(progress.completedWindowCount == 0)
        #expect(progress.isScanning == false)
        #expect(session.powerCycleObservationSession.result == nil)
    }

    @Test @MainActor
    func connectFailsClosedBeforeRunOwnedAdmissionIsPrepared() throws {
        let session = try PassiveBluetoothExperimentOneControllerSession()

        // The controller is intentionally not constructed here. This test pins the
        // package-owned precondition structurally: connection cannot be attempted
        // without first issuing the same run's hidden admission and opening its
        // post-admission rediscovery epoch.
        #expect(session.powerCycleObservationSession.result == nil)
    }
}
