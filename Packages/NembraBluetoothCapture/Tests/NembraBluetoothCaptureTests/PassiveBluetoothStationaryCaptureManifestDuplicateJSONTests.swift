import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

struct PassiveBluetoothStationaryCaptureManifestDuplicateJSONTests {
    private let target = "11111111-2222-3333-4444-555555555555"
    private let sessionID = UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!
    private let startedAt = Date(timeIntervalSince1970: 1_750_000_000)

    @Test
    func topLevelSemanticDuplicateIsRejectedBeforeFoundationDecoding() throws {
        let fixture = try makeFixture()
        let ambiguous = try replacingFirst(
            "\"schemaVersion\":3",
            with: "\"schemaVersion\":3,\"schema\\u0056ersion\":3",
            in: fixture.manifestJSON
        )

        #expect(
            throws: PassiveBluetoothStationaryCaptureManifestError
                .duplicateManifestField("schemaVersion")
        ) {
            _ = try PassiveBluetoothStationaryCaptureManifestJSON.verifyCaptureBinding(
                manifestJSON: ambiguous,
                captureJSON: fixture.captureJSON
            )
        }
    }

    @Test
    func nestedSemanticDuplicatesAreRejectedWithQualifiedPaths() throws {
        let fixture = try makeFixture()
        let cases: [(needle: String, replacement: String, path: String)] = [
            (
                "\"chargerState\":\"disconnected\"",
                "\"chargerState\":\"disconnected\",\"chargerState\":\"disconnected\"",
                "setup.chargerState"
            ),
            (
                "\"selectedPeripheralIdentifier\":\"\(target)\"",
                "\"selectedPeripheralIdentifier\":\"\(target)\",\"selectedPeripheralIdentifier\":\"\(target)\"",
                "sourceArtifact.selectedPeripheralIdentifier"
            ),
            (
                "\"targetValueRecordCount\":1",
                "\"targetValueRecordCount\":1,\"targetValueRecordCount\":1",
                "evidenceSummary.targetValueRecordCount"
            ),
        ]

        for item in cases {
            let ambiguous = try replacingFirst(
                item.needle,
                with: item.replacement,
                in: fixture.manifestJSON
            )
            #expect(
                throws: PassiveBluetoothStationaryCaptureManifestError
                    .duplicateManifestField(item.path)
            ) {
                _ = try PassiveBluetoothStationaryCaptureManifestJSON.verifyCaptureBinding(
                    manifestJSON: ambiguous,
                    captureJSON: fixture.captureJSON
                )
            }
        }
    }

    private func makeFixture() throws -> (captureJSON: Data, manifestJSON: Data) {
        let captureJSON = try makeCapture()
        let manifest = try PassiveBluetoothStationaryCaptureManifestBuilder.make(
            captureJSON: captureJSON,
            experimentID: UUID(uuidString: "99999999-8888-7777-6666-555555555555")!,
            experimentRecipe: .es80FingerprintV1,
            preparedAt: Date(timeIntervalSince1970: 1_750_000_100),
            nembraBuildIdentifier: "Capture Build V14-F1",
            nembraBuildInstanceID: "12345678-1234-1234-1234-123456789abc",
            nembraBuildCommitSHA: "abcdef0123456789abcdef0123456789abcdef01",
            selectedPeripheralIdentifier: target,
            setup: .init(
                chargerState: .disconnected,
                executionContext: .foregroundUnlockedScreenOn,
                stockAppReferenceSetup: .none
            )
        )
        return (
            captureJSON,
            try PassiveBluetoothStationaryCaptureManifestJSON.encode(
                manifest,
                prettyPrinted: false
            )
        )
    }

    private func makeCapture() throws -> Data {
        var session = try PassiveBluetoothCaptureSession(
            id: sessionID,
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
        return try PassiveBluetoothCaptureJSON.encode(session)
    }

    private func replacingFirst(
        _ needle: String,
        with replacement: String,
        in data: Data
    ) throws -> Data {
        var source = String(decoding: data, as: UTF8.self)
        let range = try #require(source.range(of: needle))
        source.replaceSubrange(range, with: replacement)
        return Data(source.utf8)
    }
}
