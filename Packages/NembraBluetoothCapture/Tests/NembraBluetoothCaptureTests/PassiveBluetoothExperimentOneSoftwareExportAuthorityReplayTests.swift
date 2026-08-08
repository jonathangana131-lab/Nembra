import Foundation
import Testing
@testable import NembraBluetoothCapture

struct PassiveBluetoothExperimentOneSoftwareExportAuthorityReplayTests {
    private let target = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    @Test
    func decoderMustNotMintMissingProducerAuthorityForUntrustedCorrelationWindows() throws {
        let captureJSON = try makeCapture()
        let manifest = try PassiveBluetoothStationaryCaptureManifestBuilder.make(
            captureJSON: captureJSON,
            experimentID: UUID(uuidString: "99999999-8888-7777-6666-555555555555")!,
            experimentRecipe: .es80FingerprintV1,
            preparedAt: Date(timeIntervalSince1970: 1_750_000_100),
            nembraBuildIdentifier: "Capture Build V14-abcdef012345",
            nembraBuildInstanceID: "a1b2c3d4-e5f6-47a8-90bc-def123456789",
            nembraBuildCommitSHA: "abcdef0123456789abcdef0123456789abcdef01",
            selectedPeripheralIdentifier: target.uuidString,
            setup: .init(
                chargerState: .disconnected,
                executionContext: .foregroundUnlockedScreenOn,
                stockAppReferenceSetup: .none
            )
        )
        let manifestJSON = try PassiveBluetoothStationaryCaptureManifestJSON.encode(
            manifest,
            prettyPrinted: false
        )

        let wire: [String: Any] = [
            "schemaVersion": 1,
            "experimentRecipeID": PassiveBluetoothExperimentRecipeID.es80FingerprintV1.rawValue,
            "captureJSONBase64": captureJSON.base64EncodedString(),
            "stationaryManifestJSONBase64": manifestJSON.base64EncodedString(),
            "correlationWindows": [
                window(phase: 0, sequence: 1, candidates: []),
                window(phase: 1, sequence: 2, candidates: [target]),
                window(phase: 2, sequence: 3, candidates: []),
                window(phase: 3, sequence: 4, candidates: [target]),
            ],
            "build": [
                "buildIdentifier": "Capture Build V14-abcdef012345",
                "buildInstanceID": "a1b2c3d4-e5f6-47a8-90bc-def123456789",
                "sourceCommitSHA": "abcdef0123456789abcdef0123456789abcdef01",
                "executableSHA256": String(repeating: "a", count: 64),
            ],
        ]
        let forged = try JSONSerialization.data(withJSONObject: wire, options: [.sortedKeys])

        // A durable export that omitted the package-issued observation-series identity has no basis
        // for proving these four catalogs came from one producer life. The current decoder creates
        // one fresh identity and therefore upgrades this caller-assembled wire into valid correlation.
        // This diagnostic stays RED until the wire preserves the original series identity and decode
        // rejects missing/mixed authority instead of synthesizing it.
        #expect(throws: PassiveBluetoothExperimentOneSoftwareExportError.correlationEvidenceInvalid) {
            _ = try PassiveBluetoothExperimentOneSoftwareExportCodec.decodeAndVerify(forged)
        }
    }

    private func window(phase: Int, sequence: UInt64, candidates: [UUID]) -> [String: Any] {
        [
            "phase": phase,
            "windowSequence": sequence,
            "startedAtUptimeNanoseconds": sequence * 100,
            "endedAtUptimeNanoseconds": sequence * 100 + 50,
            "candidates": candidates.map {
                [
                    "peripheralIdentifier": $0.uuidString,
                    "isConnectable": true,
                ] as [String: Any]
            },
        ]
    }

    private func makeCapture() throws -> Data {
        var session = try PassiveBluetoothCaptureSession(
            id: UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!,
            vehicleIdentity: .init(
                manufacturer: "AOVOPRO",
                model: "ES80",
                displayName: "AOVOPRO ES80",
                protocolFamily: "unverified-tuya"
            ),
            startedAt: Date(timeIntervalSince1970: 1_750_000_000)
        )
        try session.append(
            .service(try PassiveBluetoothServiceObservation(
                peripheralIdentifier: target.uuidString,
                serviceUUID: "FFE0",
                isPrimary: true
            )),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 1,
            receivedAtDate: Date(timeIntervalSince1970: 1_750_000_001)
        )
        try session.append(
            .value(try PassiveBluetoothValueObservation(
                peripheralIdentifier: target.uuidString,
                serviceUUID: "FFE0",
                characteristicUUID: "FFE1",
                origin: .subscriptionUpdate,
                payload: Data([0x01, 0x02])
            )),
            sequenceNumber: 2,
            receivedAtUptimeNanoseconds: 2,
            receivedAtDate: Date(timeIntervalSince1970: 1_750_000_002)
        )
        return try PassiveBluetoothCaptureJSON.encode(session)
    }
}
