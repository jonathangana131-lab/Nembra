import Foundation

/// Fail-closed instance registry for GATT evidence whose durable schema uses UUID
/// paths but does not encode CoreBluetooth object-instance identity.
///
/// If two distinct CoreBluetooth objects would collapse onto the same durable
/// UUID path in one acquisition generation, the capture must stop rather than
/// export ambiguous topology/provenance.
struct PassiveCoreBluetoothGATTIdentityRegistry {
    enum RegistryError: Swift.Error, Equatable {
        case duplicateServiceUUID(String)
        case duplicateCharacteristicPath(serviceUUID: String, characteristicUUID: String)
        case duplicateDescriptorPath(serviceUUID: String, characteristicUUID: String, descriptorUUID: String)
    }

    private struct CharacteristicPath: Hashable {
        let serviceUUID: String
        let characteristicUUID: String
    }

    private struct DescriptorPath: Hashable {
        let serviceUUID: String
        let characteristicUUID: String
        let descriptorUUID: String
    }

    private var serviceInstancesByUUID: [String: ObjectIdentifier] = [:]
    private var characteristicInstancesByPath: [CharacteristicPath: ObjectIdentifier] = [:]
    private var descriptorInstancesByPath: [DescriptorPath: ObjectIdentifier] = [:]

    mutating func reset() {
        serviceInstancesByUUID.removeAll()
        characteristicInstancesByPath.removeAll()
        descriptorInstancesByPath.removeAll()
    }

    mutating func registerService(uuid: String, instance: AnyObject) throws {
        let instanceIdentifier = ObjectIdentifier(instance)
        if let existing = serviceInstancesByUUID[uuid], existing != instanceIdentifier {
            throw RegistryError.duplicateServiceUUID(uuid)
        }
        serviceInstancesByUUID[uuid] = instanceIdentifier
    }

    mutating func registerCharacteristic(
        serviceUUID: String,
        characteristicUUID: String,
        instance: AnyObject
    ) throws {
        let path = CharacteristicPath(
            serviceUUID: serviceUUID,
            characteristicUUID: characteristicUUID
        )
        let instanceIdentifier = ObjectIdentifier(instance)
        if let existing = characteristicInstancesByPath[path], existing != instanceIdentifier {
            throw RegistryError.duplicateCharacteristicPath(
                serviceUUID: serviceUUID,
                characteristicUUID: characteristicUUID
            )
        }
        characteristicInstancesByPath[path] = instanceIdentifier
    }

    mutating func registerDescriptor(
        serviceUUID: String,
        characteristicUUID: String,
        descriptorUUID: String,
        instance: AnyObject
    ) throws {
        let path = DescriptorPath(
            serviceUUID: serviceUUID,
            characteristicUUID: characteristicUUID,
            descriptorUUID: descriptorUUID
        )
        let instanceIdentifier = ObjectIdentifier(instance)
        if let existing = descriptorInstancesByPath[path], existing != instanceIdentifier {
            throw RegistryError.duplicateDescriptorPath(
                serviceUUID: serviceUUID,
                characteristicUUID: characteristicUUID,
                descriptorUUID: descriptorUUID
            )
        }
        descriptorInstancesByPath[path] = instanceIdentifier
    }

    func containsService(uuid: String, instance: AnyObject) -> Bool {
        serviceInstancesByUUID[uuid] == ObjectIdentifier(instance)
    }

    func containsCharacteristic(
        serviceUUID: String,
        characteristicUUID: String,
        instance: AnyObject
    ) -> Bool {
        characteristicInstancesByPath[
            CharacteristicPath(
                serviceUUID: serviceUUID,
                characteristicUUID: characteristicUUID
            )
        ] == ObjectIdentifier(instance)
    }
}
