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
            rssi: rssi.intValue,
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

    public static func characteristic(
        peripheralIdentifier: UUID,
        characteristic: CBCharacteristic
    ) throws -> PassiveBluetoothCharacteristicObservation {
        guard let service = characteristic.service else {
            throw CoreBluetoothCaptureMappingError.characteristicMissingService
        }

        return try PassiveBluetoothCharacteristicObservation(
            peripheralIdentifier: peripheralIdentifier.uuidString,
            serviceUUID: normalizedUUID(service.uuid),
            characteristicUUID: normalizedUUID(characteristic.uuid),
            properties: characteristicProperties(characteristic.properties)
        )
    }

    public static func value(
        peripheralIdentifier: UUID,
        characteristic: CBCharacteristic,
        origin: PassiveBluetoothValueOrigin,
        payload: Data
    ) throws -> PassiveBluetoothValueObservation {
        guard let service = characteristic.service else {
            throw CoreBluetoothCaptureMappingError.characteristicMissingService
        }

        return try PassiveBluetoothValueObservation(
            peripheralIdentifier: peripheralIdentifier.uuidString,
            serviceUUID: normalizedUUID(service.uuid),
            characteristicUUID: normalizedUUID(characteristic.uuid),
            origin: origin,
            payload: payload
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

    private static func uuidStrings(_ uuids: [CBUUID]?) -> [String] {
        (uuids ?? []).map(normalizedUUID)
    }
}

public enum CoreBluetoothCaptureMappingError: Error, Equatable, Sendable {
    case characteristicMissingService
}
