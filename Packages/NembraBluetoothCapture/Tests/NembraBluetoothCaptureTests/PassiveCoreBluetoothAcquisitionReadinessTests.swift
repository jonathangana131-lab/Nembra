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
    func overlappingAcquisitionCannotDiscardPendingOperations() throws {
        var readiness = PassiveCoreBluetoothAcquisitionReadiness()
        readiness.beginTargetSession()
        try readiness.startAcquisition()
        let pending = try readiness.beginOperation()

        #expect(throws: PassiveCoreBluetoothAcquisitionReadiness.StateError.acquisitionAlreadyActive) {
            try readiness.startAcquisition()
        }
        #expect(readiness.phase == .acquiring)
        #expect(readiness.pendingOperationCount == 1)
        #expect(readiness.completeOperation(pending))
        #expect(readiness.isReady)
    }

    @Test
    func staleOperationCannotCompleteAfterLegitimateConnectionBoundary() throws {
        var readiness = PassiveCoreBluetoothAcquisitionReadiness()
        readiness.beginTargetSession()
        try readiness.startAcquisition()
        let old = try readiness.beginOperation()

        readiness.beginConnectionAttempt()
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

    @Test
    func terminalConnectionWithoutGattAcquisitionRemainsIncomplete() {
        var readiness = PassiveCoreBluetoothAcquisitionReadiness()
        readiness.beginTargetSession()
        readiness.beginConnectionAttempt()
        readiness.finishWithoutGattAcquisition()

        #expect(readiness.phase == .terminalWithoutGattAcquisition)
        #expect(readiness.isIncomplete)
        #expect(!readiness.isReady)
        #expect(readiness.pendingOperationCount == 0)
    }

    @Test
    func parentOperationTransitionsAtomicallyToChildOperations() throws {
        var readiness = PassiveCoreBluetoothAcquisitionReadiness()
        readiness.beginTargetSession()
        try readiness.startAcquisition()
        let parent = try readiness.beginOperation()

        let startedChildren = try readiness.completeOperation(
            parent,
            startingChildOperations: 2
        )
        let children = try #require(startedChildren)

        #expect(children.count == 2)
        #expect(readiness.phase == .acquiring)
        #expect(readiness.pendingOperationCount == 2)
        #expect(!readiness.isReady)

        let completedFirst = readiness.completeOperation(children[0])
        #expect(completedFirst)
        #expect(!readiness.isReady)
        let completedSecond = readiness.completeOperation(children[1])
        #expect(completedSecond)
        #expect(readiness.isReady)
    }

    @Test
    func staleParentCannotSpawnChildrenAfterLegitimateConnectionBoundary() throws {
        var readiness = PassiveCoreBluetoothAcquisitionReadiness()
        readiness.beginTargetSession()
        try readiness.startAcquisition()
        let oldParent = try readiness.beginOperation()

        readiness.beginConnectionAttempt()
        try readiness.startAcquisition()
        let current = try readiness.beginOperation()

        let staleChildren = try readiness.completeOperation(
            oldParent,
            startingChildOperations: 2
        )
        #expect(staleChildren == nil)
        #expect(readiness.pendingOperationCount == 1)
        #expect(!readiness.isReady)

        let completedCurrent = readiness.completeOperation(current)
        #expect(completedCurrent)
        #expect(readiness.isReady)
    }
}
