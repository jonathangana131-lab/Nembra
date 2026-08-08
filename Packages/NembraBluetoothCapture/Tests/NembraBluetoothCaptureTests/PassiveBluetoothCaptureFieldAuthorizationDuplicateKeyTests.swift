import CryptoKit
import Foundation
import Testing
@testable import NembraBluetoothCapture

struct PassiveBluetoothCaptureFieldAuthorizationDuplicateKeyTests {
    private let buildIdentifier = "Capture Build V14-abcdef012345"
    private let alternateBuildIdentifier = "Capture Build V14-fedcba543210"
    private let buildInstanceID = "a1b2c3d4-e5f6-47a8-90bc-def123456789"
    private let sourceCommitSHA = "abcdef0123456789abcdef0123456789abcdef01"
    private let executableData = Data("exact signed executable bytes".utf8)
    private let infoPlistData = Data("exact signed Info.plist bytes".utf8)
    private let fieldEvidenceData = Data("exact retained signed-field evidence bytes".utf8)
    private let retainedIPAData = Data("exact retained signed IPA bytes".utf8)

    @Test
    func everyEnvelopeAuthorityMemberRejectsDuplicateSemanticKey() throws {
        let fixture = try makeFixture()
        let object = try jsonObject(fixture.envelope)

        for field in [
            "schemaVersion",
            "externalBuildRecordBase64",
            "authorizationPayloadBase64",
            "signatureDERBase64",
        ] {
            let duplicated = try insertingDuplicateField(
                field,
                value: try #require(object[field]),
                into: fixture.envelope
            )
            #expect(
                throws: PassiveBluetoothCaptureFieldAuthorizationError.duplicateEnvelopeField(field)
            ) {
                _ = try PassiveBluetoothCaptureFieldAuthorizationVerifier.verify(
                    duplicated,
                    publicKeyX963Representation: fixture.privateKey.publicKey.x963Representation,
                    runtimeBuildIdentity: fixture.runtimeIdentity
                )
            }
        }
    }

    @Test
    func everySignedPayloadAuthorityMemberRejectsDuplicateSemanticKey() throws {
        let fixture = try makeFixture()
        let object = try jsonObject(fixture.payload)

        for field in [
            "schemaVersion",
            "decision",
            "externalBuildRecordSHA256",
            "signedFieldArtifactEvidenceSHA256",
            "retainedIPASHA256",
        ] {
            let duplicatedPayload = try insertingDuplicateField(
                field,
                value: try #require(object[field]),
                into: fixture.payload
            )
            let envelope = try makeEnvelope(
                record: fixture.record,
                payload: duplicatedPayload,
                signingKey: fixture.privateKey
            )

            #expect(
                throws: PassiveBluetoothCaptureFieldAuthorizationError
                    .duplicateAuthorizationPayloadField(field)
            ) {
                _ = try PassiveBluetoothCaptureFieldAuthorizationVerifier.verify(
                    envelope,
                    publicKeyX963Representation: fixture.privateKey.publicKey.x963Representation,
                    runtimeBuildIdentity: fixture.runtimeIdentity
                )
            }
        }
    }

    @Test
    func escapeEquivalentSignedDecisionKeyIsStillDuplicate() throws {
        let fixture = try makeFixture()
        let canonicalPayload = String(decoding: fixture.payload, as: UTF8.self)
        let escapedDuplicatePayload = Data(
            ("{\"decisio\\u006e\":\"NO_GO\"," + canonicalPayload.dropFirst()).utf8
        )
        let envelope = try makeEnvelope(
            record: fixture.record,
            payload: escapedDuplicatePayload,
            signingKey: fixture.privateKey
        )

        #expect(
            throws: PassiveBluetoothCaptureFieldAuthorizationError
                .duplicateAuthorizationPayloadField("decision")
        ) {
            _ = try PassiveBluetoothCaptureFieldAuthorizationVerifier.verify(
                envelope,
                publicKeyX963Representation: fixture.privateKey.publicKey.x963Representation,
                runtimeBuildIdentity: fixture.runtimeIdentity
            )
        }
    }

    @Test
    func everyExternalBuildRecordMemberRejectsDuplicateSemanticKey() throws {
        let record = try json(baseRecordObject())
        let object = try jsonObject(record)

        for field in [
            "schemaVersion",
            "buildIdentifier",
            "buildInstanceID",
            "sourceCommitSHA",
            "executableSHA256",
            "infoPlistSHA256",
            "experimentRecipeID",
            "procedureVersion",
        ] {
            let duplicated = try insertingDuplicateField(
                field,
                value: try #require(object[field]),
                into: record
            )
            #expect(throws: PassiveBluetoothCaptureExternalBuildRecordError.duplicateField(field)) {
                _ = try PassiveBluetoothCaptureExternalBuildRecordJSON.decodeDeclaration(duplicated)
            }
        }
    }

    @Test
    func escapeEquivalentExternalBuildRecordKeyIsStillDuplicate() throws {
        let record = try json(baseRecordObject())
        let canonicalRecord = String(decoding: record, as: UTF8.self)
        let duplicated = Data(
            ("{\"buildIdentifie\\u0072\":\"\(alternateBuildIdentifier)\"," + canonicalRecord.dropFirst()).utf8
        )

        #expect(
            throws: PassiveBluetoothCaptureExternalBuildRecordError.duplicateField("buildIdentifier")
        ) {
            _ = try PassiveBluetoothCaptureExternalBuildRecordJSON.decodeDeclaration(duplicated)
        }
    }

    @Test
    func validSignatureCannotPromoteAmbiguousExternalBuildRecordBytes() throws {
        let signingKey = P256.Signing.PrivateKey()
        let runtimeIdentity = try makeRuntimeIdentity()

        var reviewerRecordObject = baseRecordObject()
        reviewerRecordObject["buildIdentifier"] = alternateBuildIdentifier
        let reviewerRecord = try json(reviewerRecordObject)
        let ambiguousRecord = try insertingDuplicateField(
            "buildIdentifier",
            value: buildIdentifier,
            into: reviewerRecord
        )

        let payload = try json(baseAuthorizationPayloadObject(record: ambiguousRecord))
        let envelope = try makeEnvelope(
            record: ambiguousRecord,
            payload: payload,
            signingKey: signingKey
        )

        #expect(throws: PassiveBluetoothCaptureFieldAuthorizationError.invalidExternalBuildRecord) {
            _ = try PassiveBluetoothCaptureFieldAuthorizationVerifier.verify(
                envelope,
                publicKeyX963Representation: signingKey.publicKey.x963Representation,
                runtimeBuildIdentity: runtimeIdentity
            )
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
        let signingKey = P256.Signing.PrivateKey()
        let runtimeIdentity = try makeRuntimeIdentity()
        let record = try json(baseRecordObject())
        let payload = try json(baseAuthorizationPayloadObject(record: record))
        let envelope = try makeEnvelope(
            record: record,
            payload: payload,
            signingKey: signingKey
        )
        return Fixture(
            privateKey: signingKey,
            runtimeIdentity: runtimeIdentity,
            record: record,
            payload: payload,
            envelope: envelope
        )
    }

    private func makeRuntimeIdentity() throws -> PassiveBluetoothCaptureRuntimeBuildIdentity {
        try PassiveBluetoothCaptureRuntimeBuildIdentityReader.resolveEmbeddedMetadata(
            infoDictionary: [
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildIdentifierInfoDictionaryKey:
                    buildIdentifier,
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildInstanceIDInfoDictionaryKey:
                    buildInstanceID,
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.sourceCommitSHAInfoDictionaryKey:
                    sourceCommitSHA,
            ],
            executableData: executableData,
            infoPlistData: infoPlistData
        )
    }

    private func baseRecordObject() -> [String: Any] {
        [
            "schemaVersion": 3,
            "buildIdentifier": buildIdentifier,
            "buildInstanceID": buildInstanceID,
            "sourceCommitSHA": sourceCommitSHA,
            "executableSHA256": sha256Hex(executableData),
            "infoPlistSHA256": sha256Hex(infoPlistData),
            "experimentRecipeID": "ES80-FINGERPRINT-v1",
            "procedureVersion": "V14",
        ]
    }

    private func baseAuthorizationPayloadObject(record: Data) -> [String: Any] {
        [
            "schemaVersion": 1,
            "decision": "GO",
            "externalBuildRecordSHA256": sha256Hex(record),
            "signedFieldArtifactEvidenceSHA256": sha256Hex(fieldEvidenceData),
            "retainedIPASHA256": sha256Hex(retainedIPAData),
        ]
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
        let wrappedJSON = String(decoding: wrappedValue, as: UTF8.self)
        guard wrappedJSON.first == "[", wrappedJSON.last == "]" else {
            throw FixtureError.expectedJSONObject
        }
        let valueJSON = wrappedJSON.dropFirst().dropLast()
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
