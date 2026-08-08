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

        do {
            try session.connectReacquiredTarget(using: controller)
            Issue.record("Connection must not start before this run prepares its hidden capture admission")
        } catch let error as PassiveBluetoothExperimentOneControllerSession.SessionError {
            #expect(error == .captureRediscoveryNotPrepared)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
