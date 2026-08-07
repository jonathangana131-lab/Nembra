import Foundation
import Testing
@testable import NembraBluetoothCapture

struct PassiveCoreBluetoothGATTIdentityRegistryTests {
    @Test
    func sameServiceObjectMayBeObservedAgainButDuplicateUUIDInstanceFails() throws {
        let first = NSObject()
        let duplicate = NSObject()
        var registry = PassiveCoreBluetoothGATTIdentityRegistry()

        try registry.registerService(uuid: "FD50", instance: first)
        try registry.registerService(uuid: "FD50", instance: first)

        #expect(throws: PassiveCoreBluetoothGATTIdentityRegistry.RegistryError.duplicateServiceUUID("FD50")) {
            try registry.registerService(uuid: "FD50", instance: duplicate)
        }
    }

    @Test
    func duplicateCharacteristicPathFailsButSameCharacteristicUUIDInDifferentServiceIsAllowed() throws {
        let first = NSObject()
        let duplicate = NSObject()
        let otherService = NSObject()
        var registry = PassiveCoreBluetoothGATTIdentityRegistry()

        try registry.registerCharacteristic(
            serviceUUID: "FD50",
            characteristicUUID: "0001",
            instance: first
        )
        try registry.registerCharacteristic(
            serviceUUID: "A201",
            characteristicUUID: "0001",
            instance: otherService
        )

        #expect(throws: PassiveCoreBluetoothGATTIdentityRegistry.RegistryError.duplicateCharacteristicPath(
            serviceUUID: "FD50",
            characteristicUUID: "0001"
        )) {
            try registry.registerCharacteristic(
                serviceUUID: "FD50",
                characteristicUUID: "0001",
                instance: duplicate
            )
        }
    }

    @Test
    func registryResetAllowsNewCoreBluetoothInstancesForNewAcquisitionGeneration() throws {
        let old = NSObject()
        let fresh = NSObject()
        var registry = PassiveCoreBluetoothGATTIdentityRegistry()

        try registry.registerService(uuid: "FD50", instance: old)
        registry.reset()
        try registry.registerService(uuid: "FD50", instance: fresh)
    }
}
