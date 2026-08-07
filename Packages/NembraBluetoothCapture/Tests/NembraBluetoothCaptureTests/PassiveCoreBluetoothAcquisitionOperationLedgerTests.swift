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
    func restartingAcquisitionRejectsOldGenerationOperations() throws {
        let service = NSObject()
        let oldOperation = PassiveCoreBluetoothAcquisitionOperationLedger.OperationKey.characteristics(
            ObjectIdentifier(service)
        )
        var ledger = PassiveCoreBluetoothAcquisitionOperationLedger()
        ledger.beginTargetSession()
        try ledger.beginAcquisition()
        try ledger.complete(.services, starting: [oldOperation])

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
