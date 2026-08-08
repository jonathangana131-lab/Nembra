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
        #expect(registry.containsService(uuid: "FD50", instance: first))

        do {
            try registry.registerService(uuid: "FD50", instance: duplicate)
            Issue.record("Expected duplicate service UUID instance to fail closed")
        } catch let error as PassiveCoreBluetoothGATTIdentityRegistry.RegistryError {
            #expect(error == .duplicateServiceUUID("FD50"))
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

        do {
            try registry.registerCharacteristic(
                serviceUUID: "FD50",
                characteristicUUID: "0001",
                instance: duplicate
            )
            Issue.record("Expected duplicate characteristic UUID path to fail closed")
        } catch let error as PassiveCoreBluetoothGATTIdentityRegistry.RegistryError {
            #expect(error == .duplicateCharacteristicPath(
                serviceUUID: "FD50",
                characteristicUUID: "0001"
            ))
        }
    }

    @Test
    func duplicateDescriptorPathFailsButSameDescriptorUUIDInDifferentCharacteristicIsAllowed() throws {
        let first = NSObject()
        let duplicate = NSObject()
        let otherCharacteristic = NSObject()
        var registry = PassiveCoreBluetoothGATTIdentityRegistry()

        try registry.registerDescriptor(
            serviceUUID: "FD50",
            characteristicUUID: "0001",
            descriptorUUID: "2904",
            instance: first
        )
        try registry.registerDescriptor(
            serviceUUID: "FD50",
            characteristicUUID: "0001",
            descriptorUUID: "2904",
            instance: first
        )
        try registry.registerDescriptor(
            serviceUUID: "FD50",
            characteristicUUID: "0002",
            descriptorUUID: "2904",
            instance: otherCharacteristic
        )

        do {
            try registry.registerDescriptor(
                serviceUUID: "FD50",
                characteristicUUID: "0001",
                descriptorUUID: "2904",
                instance: duplicate
            )
            Issue.record("Expected duplicate descriptor UUID path to fail closed")
        } catch let error as PassiveCoreBluetoothGATTIdentityRegistry.RegistryError {
            #expect(error == .duplicateDescriptorPath(
                serviceUUID: "FD50",
                characteristicUUID: "0001",
                descriptorUUID: "2904"
            ))
        }
    }

    @Test
    func registryResetAllowsNewCoreBluetoothInstancesForNewAcquisitionGeneration() throws {
        let old = NSObject()
        let fresh = NSObject()
        var registry = PassiveCoreBluetoothGATTIdentityRegistry()

        try registry.registerService(uuid: "FD50", instance: old)
        #expect(registry.containsService(uuid: "FD50", instance: old))
        registry.reset()
        #expect(!registry.containsService(uuid: "FD50", instance: old))
        try registry.registerService(uuid: "FD50", instance: fresh)
        #expect(registry.containsService(uuid: "FD50", instance: fresh))
    }
}