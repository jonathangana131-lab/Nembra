import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

struct PassiveBluetoothStationaryCaptureManifestBuildInstanceTests {
    private let target = "11111111-2222-3333-4444-555555555555"
    private let sessionID = UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!
    private let experimentID = UUID(uuidString: "99999999-8888-7777-6666-555555555555")!
    private let preparedAt = Date(timeIntervalSince1970: 1_750_000_100)
    private let commit = "abcdef0123456789abcdef0123456789abcdef01"
    private let buildIdentifier = "Capture Build V14-abcdef012345"
    private let buildInstanceID = "A1B2C3D4-E5F6-47A8-90BC-DEF123456789"

    @Test
    func currentSchemaBindsExactProducedBuildInstanceWithoutPromotingItToAuthorization() throws {
        let captureJSON = try makeCapture()
        let manifest = try PassiveBluetoothStationaryCaptureManifestBuilder.make(
            captureJSON: captureJSON,
            experimentID: experimentID,
            experimentRecipe: .es80FingerprintV1,
            preparedAt: preparedAt,
            nembraBuildIdentifier: buildIdentifier,
            nembraBuildInstanceID: buildInstanceID,
            nembraBuildCommitSHA: commit,
            selectedPeripheralIdentifier: target,
            setup: defaultSetup()
        )

        #expect(PassiveBluetoothStationaryCaptureManifest.currentSchemaVersion == 3)
        #expect(manifest.schemaVersion == 3)
        #expect(manifest.experimentRecipeID == .es80FingerprintV1)
        #expect(manifest.nembraBuildIdentifier == buildIdentifier)
        #expect(manifest.nembraBuildInstanceID == buildInstanceID.lowercased())
        #expect(manifest.nembraBuildCommitSHA == commit)

        let encoded = try PassiveBluetoothStationaryCaptureManifestJSON.encode(manifest)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["schemaVersion"] as? Int == 3)
        #expect(object["nembraBuildInstanceID"] as? String == buildInstanceID.lowercased())

        let verified = try PassiveBluetoothStationaryCaptureManifestJSON.verifyCaptureBinding(
            manifestJSON: encoded,
            captureJSON: captureJSON
        )
        #expect(verified == manifest)
    }

    @Test
    func buildInstanceGrammarMatchesRuntimeRendezvousAndDoesNotTrimOperatorInput() throws {
        let captureJSON = try makeCapture()
        let padded = " \(buildInstanceID) "

        #expect(
            throws: PassiveBluetoothStationaryCaptureManifestError.invalidBuildInstanceID(padded)
        ) {
            _ = try makeCurrentManifest(captureJSON: captureJSON, buildInstanceID: padded)
        }

        let malformed = "a1b2c3d4-e5f6-47a8-90bc-def12345678g"
        #expect(
            throws: PassiveBluetoothStationaryCaptureManifestError.invalidBuildInstanceID(malformed)
        ) {
            _ = try makeCurrentManifest(captureJSON: captureJSON, buildInstanceID: malformed)
        }
    }

    @Test
    func legacyV2RemainsReadableWithoutInventingBuildInstance() throws {
        let captureJSON = try makeCapture()
        let legacyV2 = try PassiveBluetoothStationaryCaptureManifestBuilder.make(
            captureJSON: captureJSON,
            experimentID: experimentID,
            experimentRecipe: .es80FingerprintV1,
            preparedAt: preparedAt,
            nembraBuildIdentifier: buildIdentifier,
            nembraBuildCommitSHA: commit,
            selectedPeripheralIdentifier: target,
            setup: defaultSetup()
        )
        #expect(legacyV2.schemaVersion == 2)
        #expect(legacyV2.nembraBuildInstanceID == nil)

        let legacyJSON = try PassiveBluetoothStationaryCaptureManifestJSON.encode(legacyV2)
        let verified = try PassiveBluetoothStationaryCaptureManifestJSON.verifyCaptureBinding(
            manifestJSON: legacyJSON,
            captureJSON: captureJSON
        )
        #expect(verified.schemaVersion == 2)
        #expect(verified.nembraBuildInstanceID == nil)

        var smuggled = try #require(JSONSerialization.jsonObject(with: legacyJSON) as? [String: Any])
        smuggled["nembraBuildInstanceID"] = buildInstanceID.lowercased()
        let smuggledJSON = try JSONSerialization.data(withJSONObject: smuggled, options: [.sortedKeys])
        #expect(
            throws: PassiveBluetoothStationaryCaptureManifestError
                .unexpectedManifestField("nembraBuildInstanceID")
        ) {
            _ = try PassiveBluetoothStationaryCaptureManifestJSON.verifyCaptureBinding(
                manifestJSON: smuggledJSON,
                captureJSON: captureJSON
            )
        }
    }

    @Test
    func legacyV1AlsoRemainsExplicitlyWithoutBuildInstance() throws {
        let captureJSON = try makeCapture()
        let legacyV2 = try PassiveBluetoothStationaryCaptureManifestBuilder.make(
            captureJSON: captureJSON,
            experimentID: experimentID,
            experimentRecipe: .es80FingerprintV1,
            preparedAt: preparedAt,
            nembraBuildIdentifier: buildIdentifier,
            nembraBuildCommitSHA: commit,
            selectedPeripheralIdentifier: target,
            setup: defaultSetup()
        )
        let v2JSON = try PassiveBluetoothStationaryCaptureManifestJSON.encode(legacyV2)
        var object = try #require(JSONSerialization.jsonObject(with: v2JSON) as? [String: Any])
        object["schemaVersion"] = 1
        object.removeValue(forKey: "experimentRecipeID")
        object.removeValue(forKey: "nembraBuildIdentifier")
        let v1JSON = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        let verified = try PassiveBluetoothStationaryCaptureManifestJSON.verifyCaptureBinding(
            manifestJSON: v1JSON,
            captureJSON: captureJSON
        )
        #expect(verified.schemaVersion == 1)
        #expect(verified.experimentRecipeID == nil)
        #expect(verified.nembraBuildIdentifier == nil)
        #expect(verified.nembraBuildInstanceID == nil)
    }

    @Test
    func schemaV3RequiresBuildInstanceFieldAndRejectsUnknownFields() throws {
        let captureJSON = try makeCapture()
        let current = try makeCurrentManifest(captureJSON: captureJSON, buildInstanceID: buildInstanceID)
        let currentJSON = try PassiveBluetoothStationaryCaptureManifestJSON.encode(current)

        var missing = try #require(JSONSerialization.jsonObject(with: currentJSON) as? [String: Any])
        missing.removeValue(forKey: "nembraBuildInstanceID")
        let missingJSON = try JSONSerialization.data(withJSONObject: missing, options: [.sortedKeys])
        #expect(throws: DecodingError.self) {
            _ = try PassiveBluetoothStationaryCaptureManifestJSON.verifyCaptureBinding(
                manifestJSON: missingJSON,
                captureJSON: captureJSON
            )
        }

        var unknown = try #require(JSONSerialization.jsonObject(with: currentJSON) as? [String: Any])
        unknown["fieldAuthorized"] = true
        let unknownJSON = try JSONSerialization.data(withJSONObject: unknown, options: [.sortedKeys])
        #expect(
            throws: PassiveBluetoothStationaryCaptureManifestError
                .unexpectedManifestField("fieldAuthorized")
        ) {
            _ = try PassiveBluetoothStationaryCaptureManifestJSON.verifyCaptureBinding(
                manifestJSON: unknownJSON,
                captureJSON: captureJSON
            )
        }
    }

    private func makeCurrentManifest(
        captureJSON: Data,
        buildInstanceID: String
    ) throws -> PassiveBluetoothStationaryCaptureManifest {
        try PassiveBluetoothStationaryCaptureManifestBuilder.make(
            captureJSON: captureJSON,
            experimentID: experimentID,
            experimentRecipe: .es80FingerprintV1,
            preparedAt: preparedAt,
            nembraBuildIdentifier: buildIdentifier,
            nembraBuildInstanceID: buildInstanceID,
            nembraBuildCommitSHA: commit,
            selectedPeripheralIdentifier: target,
            setup: defaultSetup()
        )
    }

    private func defaultSetup() -> PassiveBluetoothStationaryCaptureSetup {
        .init(
            chargerState: .disconnected,
            executionContext: .foregroundUnlockedScreenOn,
            stockAppReferenceSetup: .none
        )
    }

    private func makeCapture() throws -> Data {
        var session = try PassiveBluetoothCaptureSession(
            id: sessionID,
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
                peripheralIdentifier: target,
                serviceUUID: "FFE0",
                isPrimary: true
            )),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 1,
            receivedAtDate: Date(timeIntervalSince1970: 1_750_000_001)
        )
        try session.append(
            .value(try PassiveBluetoothValueObservation(
                peripheralIdentifier: target,
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