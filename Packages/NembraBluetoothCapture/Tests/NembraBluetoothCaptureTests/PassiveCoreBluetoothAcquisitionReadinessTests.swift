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

        let completedServices = readiness.completeOperation(services)
        #expect(completedServices)
        #expect(!readiness.isReady)
        let completedCharacteristics = readiness.completeOperation(characteristics)
        #expect(completedCharacteristics)
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

        let completedStale = readiness.completeOperation(old)
        #expect(!completedStale)
        #expect(!readiness.isReady)
        let completedCurrent = readiness.completeOperation(current)
        #expect(completedCurrent)
        #expect(readiness.isReady)
    }

    @Test
    func reconnectMakesPreviouslyReadyArtifactPendingAgain() throws {
        var readiness = PassiveCoreBluetoothAcquisitionReadiness()
        readiness.beginTargetSession()
        try readiness.startAcquisition()
        let operation = try readiness.beginOperation()
        let completed = readiness.completeOperation(operation)
        #expect(completed)
        #expect(readiness.isReady)

        readiness.beginConnectionAttempt()
        #expect(readiness.phase == .awaitingConnection)
        #expect(readiness.isIncomplete)
    }
}