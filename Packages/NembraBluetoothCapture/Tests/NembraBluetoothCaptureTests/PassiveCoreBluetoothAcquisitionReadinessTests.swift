import Testing
@testable import NembraBluetoothCapture

struct PassiveCoreBluetoothAcquisitionReadinessTests {
    @Test
    func artifactIsNotReadyUntilEveryFiniteOperationDrains() throws {
        var readiness = PassiveCoreBluetoothAcquisitionReadiness()
        readiness.beginTargetSession()
        #expect(readiness.phase == .awaitingConnection)
        #expect(readiness.isIncomplete)

        readiness.beginConnectionAttempt()
        try readiness.startAcquisition()
        let services = try readiness.beginOperation()
        let characteristics = try readiness.beginOperation()
        #expect(readiness.pendingOperationCount == 2)
        #expect(!readiness.isReady)

        #expect(readiness.completeOperation(services))
        #expect(!readiness.isReady)
        #expect(readiness.completeOperation(characteristics))
        #expect(readiness.isReady)
        #expect(readiness.phase == .ready)
    }

    @Test
    func staleOperationCannotCompleteNewAcquisitionGeneration() throws {
        var readiness = PassiveCoreBluetoothAcquisitionReadiness()
        readiness.beginTargetSession()
        try readiness.startAcquisition()
        let old = try readiness.beginOperation()

        try readiness.startAcquisition()
        let current = try readiness.beginOperation()

        #expect(!readiness.completeOperation(old))
        #expect(!readiness.isReady)
        #expect(readiness.completeOperation(current))
        #expect(readiness.isReady)
    }

    @Test
    func reconnectMakesPreviouslyReadyArtifactPendingAgain() throws {
        var readiness = PassiveCoreBluetoothAcquisitionReadiness()
        readiness.beginTargetSession()
        try readiness.startAcquisition()
        let operation = try readiness.beginOperation()
        #expect(readiness.completeOperation(operation))
        #expect(readiness.isReady)

        readiness.beginConnectionAttempt()
        #expect(readiness.phase == .awaitingConnection)
        #expect(readiness.isIncomplete)
    }
}
