import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

struct PassiveBluetoothStationaryCaptureManifestStockReferenceSymmetryTests {
    @Test
    func declaredStockAppReferenceRequiresAtLeastOneImmutableMarker() throws {
        let target = "11111111-2222-3333-4444-555555555555"
        let startedAt = Date(timeIntervalSince1970: 1_750_000_000)
        var session = try PassiveBluetoothCaptureSession(
            id: UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!,
            vehicleIdentity: VehicleIdentity(
                manufacturer: "AOVOPRO",
                model: "ES80",
                displayName: "AOVOPRO ES80",
                protocolFamily: "unverified-tuya"
            ),
            startedAt: startedAt
        )

        try session.append(
            .service(try PassiveBluetoothServiceObservation(
                peripheralIdentifier: target,
                serviceUUID: "FFE0",
                isPrimary: true
            )),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 1,
            receivedAtDate: startedAt.addingTimeInterval(1)
        )
        try session.append(
            .characteristic(try PassiveBluetoothCharacteristicObservation(
                peripheralIdentifier: target,
                serviceUUID: "FFE0",
                characteristicUUID: "FFE1",
                properties: [.notify]
            )),
            sequenceNumber: 2,
            receivedAtUptimeNanoseconds: 2,
            receivedAtDate: startedAt.addingTimeInterval(2)
        )
        try session.append(
            .value(try PassiveBluetoothValueObservation(
                peripheralIdentifier: target,
                serviceUUID: "FFE0",
                characteristicUUID: "FFE1",
                origin: .subscriptionUpdate,
                payload: Data([0x01, 0x02])
            )),
            sequenceNumber: 3,
            receivedAtUptimeNanoseconds: 3,
            receivedAtDate: startedAt.addingTimeInterval(3)
        )

        let captureJSON = try PassiveBluetoothCaptureJSON.encode(session)
        let setup = PassiveBluetoothStationaryCaptureSetup(
            chargerState: .disconnected,
            executionContext: .foregroundUnlockedScreenOn,
            stockAppReferenceSetup: .sameDeviceBeforeCapture
        )

        do {
            _ = try PassiveBluetoothStationaryCaptureManifestBuilder.make(
                captureJSON: captureJSON,
                preparedAt: startedAt.addingTimeInterval(100),
                nembraBuildCommitSHA: "ABCDEF0123456789ABCDEF0123456789ABCDEF01",
                selectedPeripheralIdentifier: target,
                setup: setup
            )
            Issue.record(
                "A declared non-none stock-app reference with zero immutable stock-app markers must fail closed"
            )
        } catch {
            #expect(
                String(describing: error).contains("stockAppReferenceDeclaredWithoutMarkers"),
                "The manifest should expose the dedicated symmetric stock-reference evidence error"
            )
        }
    }
}
