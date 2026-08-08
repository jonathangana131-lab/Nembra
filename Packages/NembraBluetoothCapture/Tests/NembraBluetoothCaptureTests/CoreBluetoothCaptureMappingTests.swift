@preconcurrency import CoreBluetooth
import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("CoreBluetooth capture mapping")
struct CoreBluetoothCaptureMappingTests {
    @Test("advertisement mapping preserves every standard field used by Nembra")
    func advertisementMapping() throws {
        let peripheralID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let serviceDataUUID = CBUUID(string: "FD50")
        let advertisement: [String: Any] = [
            CBAdvertisementDataLocalNameKey: "ES80-test",
            CBAdvertisementDataIsConnectable: NSNumber(value: true),
            CBAdvertisementDataManufacturerDataKey: Data([0xD0, 0x07, 0x01, 0x02]),
            CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: "FD50")],
            CBAdvertisementDataOverflowServiceUUIDsKey: [CBUUID(string: "A201")],
            CBAdvertisementDataSolicitedServiceUUIDsKey: [CBUUID(string: "1910")],
            CBAdvertisementDataServiceDataKey: [serviceDataUUID: Data([0x41, 0xAA])],
            CBAdvertisementDataTxPowerLevelKey: NSNumber(value: -8)
        ]

        let mapped = try CoreBluetoothCaptureMapping.advertisement(
            peripheralIdentifier: peripheralID,
            advertisementData: advertisement,
            rssi: NSNumber(value: -52)
        )

        #expect(mapped.peripheralIdentifier == peripheralID.uuidString)
        #expect(mapped.localName == "ES80-test")
        #expect(mapped.rssi == -52)
        #expect(mapped.isConnectable == true)
        #expect(mapped.manufacturerData == Data([0xD0, 0x07, 0x01, 0x02]))
        #expect(mapped.serviceUUIDs == ["FD50"])
        #expect(mapped.overflowServiceUUIDs == ["A201"])
        #expect(mapped.solicitedServiceUUIDs == ["1910"])
        #expect(mapped.serviceData == ["FD50": Data([0x41, 0xAA])])
        #expect(mapped.txPowerLevel == -8)
    }

    @Test("advertisement mapping keeps absent fields and unavailable RSSI absent")
    func absentAdvertisementFields() throws {
        let mapped = try CoreBluetoothCaptureMapping.advertisement(
            peripheralIdentifier: UUID(),
            advertisementData: [:],
            rssi: NSNumber(value: 127)
        )

        #expect(mapped.localName == nil)
        #expect(mapped.rssi == nil)
        #expect(mapped.isConnectable == nil)
        #expect(mapped.manufacturerData == nil)
        #expect(mapped.serviceUUIDs.isEmpty)
        #expect(mapped.overflowServiceUUIDs.isEmpty)
        #expect(mapped.solicitedServiceUUIDs.isEmpty)
        #expect(mapped.serviceData.isEmpty)
        #expect(mapped.txPowerLevel == nil)
    }

    @Test("connection mapping preserves stable error and disconnect platform metadata")
    func connectionMapping() throws {
        let peripheralID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let error = NSError(domain: "CBErrorDomain", code: 7)

        let mapped = try CoreBluetoothCaptureMapping.connection(
            peripheralIdentifier: peripheralID,
            state: .disconnected,
            platformEventTimestamp: 1234.5,
            isReconnecting: true,
            error: error
        )
        let expectedError = try PassiveBluetoothErrorObservation(domain: "CBErrorDomain", code: 7)

        #expect(mapped.peripheralIdentifier == peripheralID.uuidString)
        #expect(mapped.state == .disconnected)
        #expect(mapped.platformEventTimestamp == 1234.5)
        #expect(mapped.isReconnecting == true)
        #expect(mapped.error == expectedError)
    }

    @Test("error mapping keeps absence absent and NSError domain/code stable")
    func errorMapping() throws {
        let absent = try CoreBluetoothCaptureMapping.errorObservation(nil)
        let mapped = try CoreBluetoothCaptureMapping.errorObservation(
            NSError(domain: "example.transport", code: -42)
        )
        let expected = try PassiveBluetoothErrorObservation(domain: "example.transport", code: -42)

        #expect(absent == nil)
        #expect(mapped == expected)
    }

    @Test("characteristic property mapping preserves read write notify indicate and security metadata")
    func characteristicProperties() {
        let properties: CBCharacteristicProperties = [
            .broadcast,
            .read,
            .writeWithoutResponse,
            .write,
            .notify,
            .indicate,
            .authenticatedSignedWrites,
            .extendedProperties,
            .notifyEncryptionRequired,
            .indicateEncryptionRequired
        ]

        #expect(
            CoreBluetoothCaptureMapping.characteristicProperties(properties)
                == Set(PassiveBluetoothCharacteristicProperty.allCases)
        )
    }

    @Test("service characteristic included-service and descriptor mappings preserve GATT topology")
    func gattDiscoveryMapping() throws {
        let peripheralID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let service = CBMutableService(type: CBUUID(string: "A201"), primary: false)
        let includedService = CBMutableService(type: CBUUID(string: "180A"), primary: true)
        let characteristic = CBMutableCharacteristic(
            type: CBUUID(string: "2B10"),
            properties: [.notify, .read],
            value: nil,
            permissions: [.readable]
        )
        let descriptor = CBMutableDescriptor(
            type: CBUUID(string: CBUUIDCharacteristicUserDescriptionString),
            value: "telemetry"
        )
        characteristic.descriptors = [descriptor]
        service.characteristics = [characteristic]
        service.includedServices = [includedService]

        let mappedService = try CoreBluetoothCaptureMapping.service(
            peripheralIdentifier: peripheralID,
            service: service
        )
        let mappedIncludedService = try CoreBluetoothCaptureMapping.includedService(
            peripheralIdentifier: peripheralID,
            parentService: service,
            includedService: includedService
        )
        let mappedCharacteristic = try CoreBluetoothCaptureMapping.characteristic(
            peripheralIdentifier: peripheralID,
            characteristic: characteristic
        )
        let mappedDescriptor = try CoreBluetoothCaptureMapping.descriptor(
            peripheralIdentifier: peripheralID,
            descriptor: descriptor
        )

        #expect(mappedService.peripheralIdentifier == peripheralID.uuidString)
        #expect(mappedService.serviceUUID == "A201")
        #expect(mappedService.isPrimary == false)
        #expect(mappedIncludedService.parentServiceUUID == "A201")
        #expect(mappedIncludedService.includedServiceUUID == "180A")
        #expect(mappedIncludedService.includedServiceIsPrimary == true)
        #expect(mappedCharacteristic.serviceUUID == "A201")
        #expect(mappedCharacteristic.characteristicUUID == "2B10")
        #expect(mappedCharacteristic.properties == [.notify, .read])
        #expect(mappedDescriptor.serviceUUID == "A201")
        #expect(mappedDescriptor.characteristicUUID == "2B10")
        #expect(mappedDescriptor.descriptorUUID == CBUUIDCharacteristicUserDescriptionString.uppercased())
    }

    @Test("subscription mapping preserves requested state without treating it as protocol acknowledgement")
    func subscriptionMapping() throws {
        let peripheralID = UUID()
        let service = CBMutableService(type: CBUUID(string: "FD50"), primary: true)
        let characteristic = CBMutableCharacteristic(
            type: CBUUID(string: "00000002-0000-1001-8001-00805F9B07D0"),
            properties: [.notify],
            value: nil,
            permissions: []
        )
        service.characteristics = [characteristic]

        let mapped = try CoreBluetoothCaptureMapping.subscription(
            peripheralIdentifier: peripheralID,
            characteristic: characteristic,
            requestedEnabled: true,
            error: nil
        )

        #expect(mapped.peripheralIdentifier == peripheralID.uuidString)
        #expect(mapped.serviceUUID == "FD50")
        #expect(mapped.characteristicUUID == "00000002-0000-1001-8001-00805F9B07D0")
        #expect(mapped.requestedEnabled == true)
        #expect(mapped.resultingIsNotifying == characteristic.isNotifying)
        #expect(mapped.error == nil)
    }

    @Test("value mapping preserves raw bytes without interpreting Tuya framing")
    func rawValueMapping() throws {
        let service = CBMutableService(type: CBUUID(string: "FD50"), primary: true)
        let characteristic = CBMutableCharacteristic(
            type: CBUUID(string: "00000002-0000-1001-8001-00805F9B07D0"),
            properties: [.notify],
            value: nil,
            permissions: []
        )
        service.characteristics = [characteristic]
        let payload = Data([0x00, 0x21, 0x20, 0xDE, 0xAD, 0xBE, 0xEF])

        let mapped = try CoreBluetoothCaptureMapping.value(
            peripheralIdentifier: UUID(),
            characteristic: characteristic,
            origin: .subscriptionUpdate,
            payload: payload
        )

        #expect(mapped.serviceUUID == "FD50")
        #expect(mapped.characteristicUUID == "00000002-0000-1001-8001-00805F9B07D0")
        #expect(mapped.origin == .subscriptionUpdate)
        #expect(mapped.payload == payload)
    }
}
