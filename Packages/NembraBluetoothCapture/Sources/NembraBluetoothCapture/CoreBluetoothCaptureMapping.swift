@preconcurrency import CoreBluetooth
import Foundation
import NembraCore

/// Lossless, non-command projection from CoreBluetooth observations into
/// Nembra's platform-neutral passive capture evidence.
///
/// This type deliberately has no characteristic write API. Discovering that a
/// characteristic advertises write capability is evidence only and does not
/// authorize a motorized-hardware command.
public enum CoreBluetoothCaptureMapping {
    public static func advertisement(
        peripheralIdentifier: UUID,
        advertisementData: [String: Any],
        rssi: NSNumber
    ) throws -> PassiveBluetoothAdvertisementObservation {
        let serviceData = (advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data]) ?? [:]

        return try PassiveBluetoothAdvertisementObservation(
            peripheralIdentifier: peripheralIdentifier.uuidString,
            localName: advertisementData[CBAdvertisementDataLocalNameKey] as? String,
            rssi: normalizedRSSI(rssi),
            isConnectable: (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue,
            manufacturerData: advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
            serviceUUIDs: uuidStrings(advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]),
            overflowServiceUUIDs: uuidStrings(advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID]),
            solicitedServiceUUIDs: uuidStrings(advertisementData[CBAdvertisementDataSolicitedServiceUUIDsKey] as? [CBUUID]),
            serviceData: Dictionary(
                uniqueKeysWithValues: serviceData.map { key, value in
                    (normalizedUUID(key), value)
                }
            ),
            txPowerLevel: (advertisementData[CBAdvertisementDataTxPowerLevelKey] as? NSNumber)?.intValue
        )
    }

    public static func connection(
        peripheralIdentifier: UUID,
        state: PassiveBluetoothConnectionState,
        platformEventTimestamp: TimeInterval? = nil,
        isReconnecting: Bool? = nil,
        error: Error? = nil
    ) throws -> PassiveBluetoothConnectionObservation {
        try PassiveBluetoothConnectionObservation(
            peripheralIdentifier: peripheralIdentifier.uuidString,
            state: state,
            platformEventTimestamp: platformEventTimestamp,
            isReconnecting: isReconnecting,
            error: try errorObservation(error)
        )
    }

    public static func service(
        peripheralIdentifier: UUID,
        service: CBService
    ) throws -> PassiveBluetoothServiceObservation {
        try PassiveBluetoothServiceObservation(
            peripheralIdentifier: peripheralIdentifier.uuidString,
            serviceUUID: normalizedUUID(service.uuid),
            isPrimary: service.isPrimary
        )
    }

    public static func includedService(
        peripheralIdentifier: UUID,
        parentService: CBService,
        includedService: CBService
    ) throws -> PassiveBluetoothIncludedServiceObservation {
        try PassiveBluetoothIncludedServiceObservation(
            peripheralIdentifier: peripheralIdentifier.uuidString,
            parentServiceUUID: normalizedUUID(parentService.uuid),
            includedServiceUUID: normalizedUUID(includedService.uuid),
            includedServiceIsPrimary: includedService.isPrimary
        )
    }

    public static func characteristic(
        peripheralIdentifier: UUID,
        characteristic: CBCharacteristic
    ) throws -> PassiveBluetoothCharacteristicObservation {
        let service = try requiredService(for: characteristic)

        return try PassiveBluetoothCharacteristicObservation(
            peripheralIdentifier: peripheralIdentifier.uuidString,
            serviceUUID: normalizedUUID(service.uuid),
            characteristicUUID: normalizedUUID(characteristic.uuid),
            properties: characteristicProperties(characteristic.properties)
        )
    }

    public static func descriptor(
        peripheralIdentifier: UUID,
        descriptor: CBDescriptor
    ) throws -> PassiveBluetoothDescriptorObservation {
        guard let characteristic = descriptor.characteristic else {
            throw CoreBluetoothCaptureMappingError.descriptorMissingCharacteristic
        }
        let service = try requiredService(for: characteristic)

        return try PassiveBluetoothDescriptorObservation(
            peripheralIdentifier: peripheralIdentifier.uuidString,
            serviceUUID: normalizedUUID(service.uuid),
            characteristicUUID: normalizedUUID(characteristic.uuid),
            descriptorUUID: normalizedUUID(descriptor.uuid)
        )
    }

    public static func subscription(
        peripheralIdentifier: UUID,
        characteristic: CBCharacteristic,
        requestedEnabled: Bool?,
        error: Error? = nil
    ) throws -> PassiveBluetoothSubscriptionObservation {
        let service = try requiredService(for: characteristic)

        return try PassiveBluetoothSubscriptionObservation(
            peripheralIdentifier: peripheralIdentifier.uuidString,
            serviceUUID: normalizedUUID(service.uuid),
            characteristicUUID: normalizedUUID(characteristic.uuid),
            requestedEnabled: requestedEnabled,
            resultingIsNotifying: characteristic.isNotifying,
            error: try errorObservation(error)
        )
    }

    public static func value(
        peripheralIdentifier: UUID,
        characteristic: CBCharacteristic,
        origin: PassiveBluetoothValueOrigin,
        payload: Data
    ) throws -> PassiveBluetoothValueObservation {
        let service = try requiredService(for: characteristic)

        return try PassiveBluetoothValueObservation(
            peripheralIdentifier: peripheralIdentifier.uuidString,
            serviceUUID: normalizedUUID(service.uuid),
            characteristicUUID: normalizedUUID(characteristic.uuid),
            origin: origin,
            payload: payload
        )
    }

    public static func errorObservation(_ error: Error?) throws -> PassiveBluetoothErrorObservation? {
        guard let error else { return nil }
        let nsError = error as NSError
        return try PassiveBluetoothErrorObservation(
            domain: nsError.domain,
            code: nsError.code
        )
    }

    public static func characteristicProperties(
        _ properties: CBCharacteristicProperties
    ) -> Set<PassiveBluetoothCharacteristicProperty> {
        var result: Set<PassiveBluetoothCharacteristicProperty> = []

        if properties.contains(.broadcast) { result.insert(.broadcast) }
        if properties.contains(.read) { result.insert(.read) }
        if properties.contains(.writeWithoutResponse) { result.insert(.writeWithoutResponse) }
        if properties.contains(.write) { result.insert(.write) }
        if properties.contains(.notify) { result.insert(.notify) }
        if properties.contains(.indicate) { result.insert(.indicate) }
        if properties.contains(.authenticatedSignedWrites) { result.insert(.authenticatedSignedWrites) }
        if properties.contains(.extendedProperties) { result.insert(.extendedProperties) }
        if properties.contains(.notifyEncryptionRequired) { result.insert(.notifyEncryptionRequired) }
        if properties.contains(.indicateEncryptionRequired) { result.insert(.indicateEncryptionRequired) }

        return result
    }

    /// CoreBluetooth's UUID string representation is retained rather than
    /// expanding 16-bit UUIDs into a guessed 128-bit form. Uppercasing makes
    /// capture diffs stable without changing the identifier's semantics.
    public static func normalizedUUID(_ uuid: CBUUID) -> String {
        uuid.uuidString.uppercased()
    }

    private static func normalizedRSSI(_ rssi: NSNumber) -> Int? {
        let value = rssi.intValue
        return value == 127 ? nil : value
    }

    private static func uuidStrings(_ uuids: [CBUUID]?) -> [String] {
        (uuids ?? []).map(normalizedUUID)
    }

    private static func requiredService(for characteristic: CBCharacteristic) throws -> CBService {
        guard let service = characteristic.service else {
            throw CoreBluetoothCaptureMappingError.characteristicMissingService
        }
        return service
    }
}

public enum CoreBluetoothCaptureMappingError: Error, Equatable, Sendable {
    case characteristicMissingService
    case descriptorMissingCharacteristic
}
