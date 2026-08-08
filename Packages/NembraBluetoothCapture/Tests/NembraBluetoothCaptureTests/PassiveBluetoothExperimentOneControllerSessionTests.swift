import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment One app controller session")
struct PassiveBluetoothExperimentOneControllerSessionTests {
    @Test @MainActor
    func ownsCanonicalFourWindowProducerAndPrivateControllerFromOneOwner() throws {
        let session = try PassiveBluetoothExperimentOneControllerSession()

        let progress = try #require(session.powerCycleObservationSession.progress)
        #expect(progress.phase == .firstPoweredOff)
        #expect(progress.completedWindowCount == 0)
        #expect(progress.isScanning == false)
        #expect(session.powerCycleObservationSession.result == nil)
        #expect(session.hasTargetSession == false)
        #expect(session.hasCompleteTargetEvidence == false)
        #expect(session.canFinalizeObservationHorizon == false)
    }

    @Test @MainActor
    func connectFailsClosedBeforeRunOwnedAdmissionIsPrepared() throws {
        let session = try PassiveBluetoothExperimentOneControllerSession()

        #expect(
            throws: PassiveBluetoothExperimentOneControllerSession.SessionError
                .captureRediscoveryNotPrepared
        ) {
            try session.connectReacquiredTarget()
        }
        #expect(session.hasTargetSession == false)
    }

    @Test @MainActor
    func preCaptureRestartReplacesTheWholeExperimentOneProducer() throws {
        let session = try PassiveBluetoothExperimentOneControllerSession()
        let firstProducer = session.powerCycleObservationSession

        try session.restartExperimentOne()

        let secondProducer = session.powerCycleObservationSession
        #expect(firstProducer !== secondProducer)
        let progress = try #require(secondProducer.progress)
        #expect(progress.phase == .firstPoweredOff)
        #expect(progress.completedWindowCount == 0)
        #expect(secondProducer.result == nil)
        #expect(session.hasTargetSession == false)
    }
}
