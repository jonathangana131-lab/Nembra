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
        let controller = try ForegroundCoreBluetoothCaptureController(
            vehicleIdentity: VehicleProfile.aovoproES80.identity
        )

        #expect(throws: PassiveBluetoothExperimentOneControllerSession.SessionError.captureRediscoveryNotPrepared) {
            try session.connectReacquiredTarget(using: controller)
        }
    }
}
