import Foundation
import Testing
@testable import NembraBluetoothCapture

struct PassiveCoreBluetoothAcquisitionOperationLedgerTests {
    @Test
    func rootDiscoveryCanFanOutWithoutTransientReadyState() throws {
        let serviceA = NSObject()
        let serviceB = NSObject()
        var ledger = PassiveCoreBluetoothAcquisitionOperationLedger()
        ledger.beginTargetSession()
        ledger.beginConnectionAttempt()
        try ledger.beginAcquisition()

        let children: [PassiveCoreBluetoothAcquisitionOperationLedger.OperationKey] = [
            .includedServices(ObjectIdentifier(serviceA)),
            .characteristics(ObjectIdentifier(serviceA)),
            .includedServices(ObjectIdentifier(serviceB)),
            .characteristics(ObjectIdentifier(serviceB))
        ]
        try ledger.complete(.services, starting: children)

        #expect(ledger.phase == .acquiring)
        #expect(ledger.pendingOperationCount == 4)
        #expect(!ledger.isReady)

        for child in children.dropLast() {
            try ledger.complete(child)
            #expect(!ledger.isReady)
        }
        try ledger.complete(try #require(children.last))
        #expect(ledger.isReady)
    }

    @Test
    func readCanAtomicallyTransitionToSubscription() throws {
        let characteristic = NSObject()
        let characteristicID = ObjectIdentifier(characteristic)
        var ledger = PassiveCoreBluetoothAcquisitionOperationLedger()
        ledger.beginTargetSession()
        try ledger.beginAcquisition()
        try ledger.complete(.services, starting: [.read(characteristicID)])

        try ledger.complete(.read(characteristicID), starting: [.subscription(characteristicID)])
        #expect(!ledger.isReady)
        #expect(ledger.isPending(.subscription(characteristicID)))

        try ledger.complete(.subscription(characteristicID))
        #expect(ledger.isReady)
    }

    @Test
    func overlappingAcquisitionDoesNotErasePendingLedgerOperations() throws {
        let service = NSObject()
        let oldOperation = PassiveCoreBluetoothAcquisitionOperationLedger.OperationKey.characteristics(
            ObjectIdentifier(service)
        )
        var ledger = PassiveCoreBluetoothAcquisitionOperationLedger()
        ledger.beginTargetSession()
        try ledger.beginAcquisition()
        try ledger.complete(.services, starting: [oldOperation])

        #expect(throws: PassiveCoreBluetoothAcquisitionReadiness.StateError.acquisitionAlreadyActive) {
            try ledger.beginAcquisition()
        }
        #expect(ledger.isPending(oldOperation))
        #expect(ledger.pendingOperationCount == 1)

        try ledger.complete(oldOperation)
        #expect(ledger.isReady)
        #expect(ledger.pendingOperationCount == 0)
    }

    @Test
    func rejectedSourcePhaseLeavesLedgerUnchanged() throws {
        var ledger = PassiveCoreBluetoothAcquisitionOperationLedger()

        #expect(
            throws: PassiveCoreBluetoothAcquisitionReadiness.StateError.acquisitionNotPermitted(.noTarget)
        ) {
            try ledger.beginAcquisition()
        }
        #expect(ledger.phase == .noTarget)
        #expect(ledger.pendingOperationCount == 0)
        #expect(!ledger.isPending(.services))

        ledger.beginTargetSession()
        ledger.finishWithoutGattAcquisition()
        #expect(
            throws: PassiveCoreBluetoothAcquisitionReadiness.StateError.acquisitionNotPermitted(.terminalWithoutGattAcquisition)
        ) {
            try ledger.beginAcquisition()
        }
        #expect(ledger.phase == .terminalWithoutGattAcquisition)
        #expect(ledger.pendingOperationCount == 0)
        #expect(!ledger.isPending(.services))
    }

    @Test
    func completedLedgerMayStartQuiescentReacquisition() throws {
        var ledger = PassiveCoreBluetoothAcquisitionOperationLedger()
        ledger.beginTargetSession()
        try ledger.beginAcquisition()
        try ledger.complete(.services)
        #expect(ledger.isReady)

        try ledger.beginAcquisition()
        #expect(ledger.phase == .acquiring)
        #expect(ledger.isPending(.services))
        #expect(ledger.pendingOperationCount == 1)
    }

    @Test
    func connectionBoundaryRejectsOldGenerationOperations() throws {
        let service = NSObject()
        let oldOperation = PassiveCoreBluetoothAcquisitionOperationLedger.OperationKey.characteristics(
            ObjectIdentifier(service)
        )
        var ledger = PassiveCoreBluetoothAcquisitionOperationLedger()
        ledger.beginTargetSession()
        try ledger.beginAcquisition()
        try ledger.complete(.services, starting: [oldOperation])

        ledger.beginConnectionAttempt()
        try ledger.beginAcquisition()
        #expect(!ledger.isPending(oldOperation))
        #expect(ledger.isPending(.services))

        #expect(throws: PassiveCoreBluetoothAcquisitionOperationLedger.LedgerError.operationNotPending) {
            try ledger.complete(oldOperation)
        }
        #expect(!ledger.isReady)
    }

    @Test
    func duplicateChildSchedulingFailsBeforeParentCompletion() throws {
        let service = NSObject()
        let child = PassiveCoreBluetoothAcquisitionOperationLedger.OperationKey.characteristics(
            ObjectIdentifier(service)
        )
        var ledger = PassiveCoreBluetoothAcquisitionOperationLedger()
        ledger.beginTargetSession()
        try ledger.beginAcquisition()

        #expect(throws: PassiveCoreBluetoothAcquisitionOperationLedger.LedgerError.operationAlreadyPending) {
            try ledger.complete(.services, starting: [child, child])
        }
        #expect(ledger.isPending(.services))
        #expect(ledger.pendingOperationCount == 1)
        #expect(!ledger.isReady)
    }

    @Test
    func failedConnectionRemainsIncompleteWithoutGattWork() {
        var ledger = PassiveCoreBluetoothAcquisitionOperationLedger()
        ledger.beginTargetSession()
        ledger.beginConnectionAttempt()
        ledger.finishWithoutGattAcquisition()

        #expect(ledger.phase == .terminalWithoutGattAcquisition)
        #expect(ledger.isIncomplete)
        #expect(!ledger.isReady)
        #expect(ledger.pendingOperationCount == 0)
    }
}
