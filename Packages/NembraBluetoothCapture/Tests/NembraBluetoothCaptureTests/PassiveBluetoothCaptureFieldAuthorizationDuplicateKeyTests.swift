import CryptoKit
import Foundation
import Testing
@testable import NembraBluetoothCapture

struct PassiveBluetoothCaptureFieldAuthorizationDuplicateKeyTests {
    private let buildIdentifier = "Capture Build V14-abcdef012345"
    private let buildInstanceID = "a1b2c3d4-e5f6-47a8-90bc-def123456789"
    private let sourceCommitSHA = "abcdef0123456789abcdef0123456789abcdef01"
    private let executableData = Data("exact signed executable bytes".utf8)
    private let infoPlistData = Data("exact signed Info.plist bytes".utf8)
    private let fieldEvidenceData = Data("exact signed-field evidence bytes".utf8)
    private let retainedIPAData = Data("exact retained IPA bytes".utf8)

    @Test
    func everyEnvelopeAuthorityFieldRejectsDuplicateSemanticKeyBeforeDecoding() throws {
        let fixture = try makeFixture()
        let envelopeObject = try jsonObject(fixture.envelope)

        for field in [
            "schemaVersion",
            "externalBuildRecordBase64",
            "authorizationPayloadBase64",
            "signatureDERBase64",
        ] {
            let duplicated = try insertingDuplicateField(
                field,
                value: try #require(envelopeObject[field]),
                into: fixture.envelope
            )

            #expect(
                throws: PassiveBluetoothCaptureFieldAuthorizationError
                    .duplicateEnvelopeField(field)
            ) {
                _ = try verify(duplicated, fixture: fixture)
            }
        }
    }

    @Test
    func everySchemaV2SignedPayloadFieldRejectsDuplicateSemanticKeyBeforePromotion() throws {
        let fixture = try makeFixture()
        let payloadObject = try jsonObject(fixture.payload)

        for field in [
            "schemaVersion",
            "decision",
            "externalBuildRecordSHA256",
            "signedFieldArtifactEvidenceSHA256",
            "retainedIPASHA256",
        ] {
            let duplicatedPayload = try insertingDuplicateField(
                field,
                value: try #require(payloadObject[field]),
                into: fixture.payload
            )
            let signedEnvelope = try makeEnvelope(
                record: fixture.record,
                payload: duplicatedPayload,
                signingKey: fixture.privateKey
            )

            #expect(
                throws: PassiveBluetoothCaptureFieldAuthorizationError
                    .duplicateAuthorizationPayloadField(field)
            ) {
                _ = try verify(signedEnvelope, fixture: fixture)
            }
        }
    }

    @Test
    func escapeEquivalentSignedPayloadKeyRejectsByDecodedSemanticName() throws {
        let fixture = try makeFixture()
        let canonicalPayload = String(decoding: fixture.payload, as: UTF8.self)
        let escapedDuplicatePayload = Data(
            ("{\"retainedIPA\\u0053HA256\":\"\(sha256Hex(retainedIPAData))\"," +
                canonicalPayload.dropFirst()).utf8
        )
        let signedEnvelope = try makeEnvelope(
            record: fixture.record,
            payload: escapedDuplicatePayload,
            signingKey: fixture.privateKey
        )

        #expect(
            throws: PassiveBluetoothCaptureFieldAuthorizationError
                .duplicateAuthorizationPayloadField("retainedIPASHA256")
        ) {
            _ = try verify(signedEnvelope, fixture: fixture)
        }
    }

    private struct Fixture {
        let privateKey: P256.Signing.PrivateKey
        let runtimeIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity
        let record: Data
        let payload: Data
        let envelope: Data
    }

    private func makeFixture() throws -> Fixture {
        let privateKey = P256.Signing.PrivateKey()
        let runtimeIdentity = try PassiveBluetoothCaptureRuntimeBuildIdentityReader
            .resolveEmbeddedMetadata(
                infoDictionary: [
                    PassiveBluetoothCaptureRuntimeBuildIdentityReader
                        .buildIdentifierInfoDictionaryKey: buildIdentifier,
                    PassiveBluetoothCaptureRuntimeBuildIdentityReader
                        .buildInstanceIDInfoDictionaryKey: buildInstanceID,
                    PassiveBluetoothCaptureRuntimeBuildIdentityReader
                        .sourceCommitSHAInfoDictionaryKey: sourceCommitSHA,
                ],
                executableData: executableData,
                infoPlistData: infoPlistData
            )
        let record = try json([
            "schemaVersion": 3,
            "buildIdentifier": buildIdentifier,
            "buildInstanceID": buildInstanceID,
            "sourceCommitSHA": sourceCommitSHA,
            "executableSHA256": sha256Hex(executableData),
            "infoPlistSHA256": sha256Hex(infoPlistData),
            "experimentRecipeID": "ES80-FINGERPRINT-v1",
            "procedureVersion": "V14",
        ])
        let payload = try json([
            "schemaVersion": 2,
            "decision": "GO",
            "externalBuildRecordSHA256": sha256Hex(record),
            "signedFieldArtifactEvidenceSHA256": sha256Hex(fieldEvidenceData),
            "retainedIPASHA256": sha256Hex(retainedIPAData),
        ])
        let envelope = try makeEnvelope(
            record: record,
            payload: payload,
            signingKey: privateKey
        )
        return Fixture(
            privateKey: privateKey,
            runtimeIdentity: runtimeIdentity,
            record: record,
            payload: payload,
            envelope: envelope
        )
    }

    private func verify(
        _ envelope: Data,
        fixture: Fixture
    ) throws -> PassiveBluetoothCaptureVerifiedFieldAuthorization {
        try PassiveBluetoothCaptureFieldAuthorizationVerifier.verify(
            envelope,
            publicKeyX963Representation: fixture.privateKey.publicKey.x963Representation,
            runtimeBuildIdentity: fixture.runtimeIdentity
        )
    }

    private func makeEnvelope(
        record: Data,
        payload: Data,
        signingKey: P256.Signing.PrivateKey
    ) throws -> Data {
        let signature = try signingKey.signature(for: payload)
        return try json([
            "schemaVersion": 1,
            "externalBuildRecordBase64": record.base64EncodedString(),
            "authorizationPayloadBase64": payload.base64EncodedString(),
            "signatureDERBase64": signature.derRepresentation.base64EncodedString(),
        ])
    }

    private func insertingDuplicateField(
        _ field: String,
        value: Any,
        into objectData: Data
    ) throws -> Data {
        let canonicalObject = String(decoding: objectData, as: UTF8.self)
        guard canonicalObject.first == "{" else {
            throw FixtureError.expectedJSONObject
        }

        let wrappedValue = try JSONSerialization.data(withJSONObject: [value])
        let wrappedValueJSON = String(decoding: wrappedValue, as: UTF8.self)
        guard wrappedValueJSON.first == "[", wrappedValueJSON.last == "]" else {
            throw FixtureError.expectedJSONObject
        }
        let valueJSON = wrappedValueJSON.dropFirst().dropLast()
        return Data(("{\"\(field)\":\(valueJSON)," + canonicalObject.dropFirst()).utf8)
    }

    private func json(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw FixtureError.expectedJSONObject
        }
        return dictionary
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private enum FixtureError: Error {
        case expectedJSONObject
    }
}
