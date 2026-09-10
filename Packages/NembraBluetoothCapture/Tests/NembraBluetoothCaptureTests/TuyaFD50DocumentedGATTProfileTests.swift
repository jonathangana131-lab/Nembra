import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya documented FD50 GATT profile")
struct TuyaFD50DocumentedGATTProfileTests {
    @Test("documented FD50 notify tuple matches without minting physical authority")
    func documentedNotifyTupleIsProvenanceOnly() {
        #expect(TuyaFD50DocumentedGATTProfile.matchesNotify(
            serviceUUID: "fd50",
            characteristicUUID: "00000002-0000-1001-8001-00805f9b07d0"
        ))

        #expect(!TuyaFD50DocumentedGATTProfile.authorizesAuthentication)
        #expect(!TuyaFD50DocumentedGATTProfile.authorizesRawNotifyCustody)
        #expect(!TuyaFD50DocumentedGATTProfile.authorizesTelemetrySemantics)
        #expect(!TuyaFD50DocumentedGATTProfile.authorizesControlWrites)
    }

    @Test("write or read characteristics cannot masquerade as notify provenance")
    func nonNotifyCharacteristicsAreRejected() {
        #expect(!TuyaFD50DocumentedGATTProfile.matchesNotify(
            serviceUUID: TuyaFD50DocumentedGATTProfile.serviceUUID,
            characteristicUUID: TuyaFD50DocumentedGATTProfile.writeCharacteristicUUID
        ))
        #expect(!TuyaFD50DocumentedGATTProfile.matchesNotify(
            serviceUUID: TuyaFD50DocumentedGATTProfile.serviceUUID,
            characteristicUUID: TuyaFD50DocumentedGATTProfile.readCharacteristicUUID
        ))
        #expect(!TuyaFD50DocumentedGATTProfile.matchesNotify(
            serviceUUID: "FFFF",
            characteristicUUID: TuyaFD50DocumentedGATTProfile.notifyCharacteristicUUID
        ))
    }
}
