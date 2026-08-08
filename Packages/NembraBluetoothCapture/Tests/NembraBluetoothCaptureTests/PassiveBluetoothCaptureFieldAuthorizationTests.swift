import CryptoKit
import Foundation
import Testing
@testable import NembraBluetoothCapture

struct PassiveBluetoothCaptureFieldAuthorizationTests {
    private let buildIdentifier = "Capture Build V14-abcdef012345"
    private let buildInstanceID = "a1b2c3d4-e5f6-47a8-90bc-def123456789"
    private let sourceCommitSHA = "abcdef0123456789abcdef0123456789abcdef01"
    private let executableData = Data("exact signed executable bytes".utf8)
    private let infoPlistData = Data("exact signed Info.plist bytes".utf8)
    private let signedInstallableSHA256 = String(repeating: "c", count: 64)

    @Test
    func validSchemaV2GoBindsExactCanonicalIPAEvidenceAndRuntime() throws {
        let fixture = try makeFixture()
        let authorization = try verify(fixture, runtimeIdentity: fixture.runtimeIdentity)

        #expect(authorization.externalBuildRecord.exactRecordSHA256 == sha256Hex(fixture.record))
        #expect(authorization.externalBuildRecord.buildIdentifier == buildIdentifier)
        #expect(authorization.externalBuildRecord.infoPlistSHA256 == sha256Hex(infoPlistData))
        #expect(
            authorization.fieldBuildEvidenceRecord.exactEvidenceRecordSHA256
                == sha256Hex(fixture.fieldEvidence)
        )
        #expect(
            authorization.fieldBuildEvidenceRecord.externalBuildRecordSHA256
                == sha256Hex(fixture.record)
        )
        #expect(
            authorization.fieldBuildEvidenceRecord.signedInstallableSHA256
                == signedInstallableSHA256
        )
        #expect(authorization.fieldBuildEvidenceRecord.signedInstallableKind == "ipa")
        #expect(authorization.authorizationPayloadSHA256 == sha256Hex(fixture.payload))
    }

    @Test
    func wrongSigningKeyFailsClosed() throws {
        let fixture = try makeFixture()
        let unrelatedKey = P256.Signing.PrivateKey()

        #expect(throws: PassiveBluetoothCaptureFieldAuthorizationError.invalidSignature) {
            _ = try PassiveBluetoothCaptureFieldAuthorizationVerifier.verify(
                fixture.envelope,
                publicKeyX963Representation: unrelatedKey.publicKey.x963Representation,
                runtimeBuildIdentity: fixture.runtimeIdentity
            )
        }
    }

    @Test
    func signedPayloadCannotBeReboundToDifferentExternalRecordBytes() throws {
        let fixture = try makeFixture()
        var alternate = baseRecordObject()
        alternate["buildIdentifier"] = "Capture Build V14-fedcba543210"
        let alternateRecord = try json(alternate)
        let rebound = try makeEnvelope(
            record: alternateRecord,
            fieldEvidence: fixture.fieldEvidence,
            payload: fixture.payload,
            signingKey: fixture.privateKey
        )

        #expect(throws: PassiveBluetoothCaptureFieldAuthorizationError.externalBuildRecordDigestMismatch) {
            _ = try PassiveBluetoothCaptureFieldAuthorizationVerifier.verify(
                rebound,
                publicKeyX963Representation: fixture.privateKey.publicKey.x963Representation,
                runtimeBuildIdentity: fixture.runtimeIdentity
            )
        }
    }

    @Test
    func signedPayloadCannotBeReboundToDifferentFieldEvidenceBytes() throws {
        let fixture = try makeFixture()
        var alternate = try jsonObject(fixture.fieldEvidence)
        alternate["signedInstallableSHA256"] = String(repeating: "d", count: 64)
        let alternateEvidence = try json(alternate)
        let rebound = try makeEnvelope(
            record: fixture.record,
            fieldEvidence: alternateEvidence,
            payload: fixture.payload,
            signingKey: fixture.privateKey
        )

        #expect(
            throws: PassiveBluetoothCaptureFieldAuthorizationError
                .fieldBuildEvidenceRecordDigestMismatch
        ) {
            _ = try PassiveBluetoothCaptureFieldAuthorizationVerifier.verify(
                rebound,
                publicKeyX963Representation: fixture.privateKey.publicKey.x963Representation,
                runtimeBuildIdentity: fixture.runtimeIdentity
            )
        }
    }

    @Test
    func newlySignedButInternallyMismatchedFieldEvidenceFailsClosed() throws {
        let signingKey = P256.Signing.PrivateKey()
        let runtimeIdentity = try makeRuntimeIdentity()
        let record = try json(baseRecordObject())
        var fieldObject = fieldEvidenceObject(externalRecordSHA256: sha256Hex(record))
        fieldObject["executableSHA256"] = String(repeating: "d", count: 64)
        let fieldEvidence = try json(fieldObject)
        let payload = try makePayload(record: record, fieldEvidence: fieldEvidence)
        let envelope = try makeEnvelope(
            record: record,
            fieldEvidence: fieldEvidence,
            payload: payload,
            signingKey: signingKey
        )

        #expect(throws: PassiveBluetoothCaptureFieldAuthorizationError.fieldBuildEvidenceMismatch) {
            _ = try PassiveBluetoothCaptureFieldAuthorizationVerifier.verify(
                envelope,
                publicKeyX963Representation: signingKey.publicKey.x963Representation,
                runtimeBuildIdentity: runtimeIdentity
            )
        }
    }

    @Test
    func differentRunningExecutableFailsClosed() throws {
        let fixture = try makeFixture()
        let differentRuntime = try makeRuntimeIdentity(
            executableData: Data("different installed executable".utf8)
        )

        #expect(throws: PassiveBluetoothCaptureFieldAuthorizationError.runtimeBuildMismatch) {
            _ = try verify(fixture, runtimeIdentity: differentRuntime)
        }
    }

    @Test
    func differentRunningInfoPlistFailsClosed() throws {
        let fixture = try makeFixture()
        let differentRuntime = try makeRuntimeIdentity(
            infoPlistData: Data("different Info.plist".utf8)
        )

        #expect(throws: PassiveBluetoothCaptureFieldAuthorizationError.runtimeInfoPlistMismatch) {
            _ = try verify(fixture, runtimeIdentity: differentRuntime)
        }
    }

    @Test
    func unknownAuthorityLookingEnvelopeAndPayloadFieldsFailClosed() throws {
        let fixture = try makeFixture()
        var envelopeObject = try jsonObject(fixture.envelope)
        envelopeObject["physicalGO"] = true
        let unknownEnvelope = try json(envelopeObject)

        #expect(
            throws: PassiveBluetoothCaptureFieldAuthorizationError.unexpectedEnvelopeField("physicalGO")
        ) {
            _ = try PassiveBluetoothCaptureFieldAuthorizationVerifier.verify(
                unknownEnvelope,
                publicKeyX963Representation: fixture.privateKey.publicKey.x963Representation,
                runtimeBuildIdentity: fixture.runtimeIdentity
            )
        }

        var payloadObject = try jsonObject(fixture.payload)
        payloadObject["fieldAuthorized"] = true
        let unknownPayload = try json(payloadObject)
        let signedUnknownPayload = try makeEnvelope(
            record: fixture.record,
            fieldEvidence: fixture.fieldEvidence,
            payload: unknownPayload,
            signingKey: fixture.privateKey
        )

        #expect(
            throws: PassiveBluetoothCaptureFieldAuthorizationError
                .unexpectedAuthorizationPayloadField("fieldAuthorized")
        ) {
            _ = try PassiveBluetoothCaptureFieldAuthorizationVerifier.verify(
                signedUnknownPayload,
                publicKeyX963Representation: fixture.privateKey.publicKey.x963Representation,
                runtimeBuildIdentity: fixture.runtimeIdentity
            )
        }
    }

    @Test
    func everyEnvelopeAuthorityMemberRejectsDuplicateSemanticKey() throws {
        let fixture = try makeFixture()
        let object = try jsonObject(fixture.envelope)

        for field in [
            "schemaVersion",
            "externalBuildRecordBase64",
            "fieldBuildEvidenceRecordBase64",
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
    func everySignedPayloadMemberRejectsDuplicateSemanticKey() throws {
        let fixture = try makeFixture()
        let object = try jsonObject(fixture.payload)

        for field in [
            "schemaVersion",
            "decision",
            "externalBuildRecordSHA256",
            "fieldBuildEvidenceRecordSHA256",
        ] {
            let duplicatedPayload = try insertingDuplicateField(
                field,
                value: try #require(object[field]),
                into: fixture.payload
            )
            let signedEnvelope = try makeEnvelope(
                record: fixture.record,
                fieldEvidence: fixture.fieldEvidence,
                payload: duplicatedPayload,
                signingKey: fixture.privateKey
            )
            #expect(
                throws: PassiveBluetoothCaptureFieldAuthorizationError
                    .duplicateAuthorizationPayloadField(field)
            ) {
                _ = try PassiveBluetoothCaptureFieldAuthorizationVerifier.verify(
                    signedEnvelope,
                    publicKeyX963Representation: fixture.privateKey.publicKey.x963Representation,
                    runtimeBuildIdentity: fixture.runtimeIdentity
                )
            }
        }
    }

    @Test
    func escapeEquivalentDecisionKeyFailsClosedBySemanticName() throws {
        let fixture = try makeFixture()
        let canonicalPayload = String(decoding: fixture.payload, as: UTF8.self)
        let duplicatedPayload = Data(
            ("{\"decisio\\u006e\":\"GO\"," + canonicalPayload.dropFirst()).utf8
        )
        let envelope = try makeEnvelope(
            record: fixture.record,
            fieldEvidence: fixture.fieldEvidence,
            payload: duplicatedPayload,
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
    func validSignatureCannotPromoteAmbiguousExternalBuildRecordBytes() throws {
        let signingKey = P256.Signing.PrivateKey()
        let runtimeIdentity = try makeRuntimeIdentity()
        let canonicalRecord = try json(baseRecordObject())
        let duplicatedRecord = try insertingDuplicateField(
            "infoPlistSHA256",
            value: sha256Hex(infoPlistData),
            into: canonicalRecord
        )
        let fieldEvidence = try json(
            fieldEvidenceObject(externalRecordSHA256: sha256Hex(duplicatedRecord))
        )
        let payload = try makePayload(record: duplicatedRecord, fieldEvidence: fieldEvidence)
        let envelope = try makeEnvelope(
            record: duplicatedRecord,
            fieldEvidence: fieldEvidence,
            payload: payload,
            signingKey: signingKey
        )

        #expect(
            throws: PassiveBluetoothCaptureFieldAuthorizationError
                .duplicateExternalBuildRecordField("infoPlistSHA256")
        ) {
            _ = try PassiveBluetoothCaptureFieldAuthorizationVerifier.verify(
                envelope,
                publicKeyX963Representation: signingKey.publicKey.x963Representation,
                runtimeBuildIdentity: runtimeIdentity
            )
        }
    }

    @Test
    func validSignatureCannotPromoteAmbiguousIPAEvidenceBytes() throws {
        let signingKey = P256.Signing.PrivateKey()
        let runtimeIdentity = try makeRuntimeIdentity()
        let record = try json(baseRecordObject())
        let canonicalEvidence = try json(
            fieldEvidenceObject(externalRecordSHA256: sha256Hex(record))
        )
        let duplicatedEvidence = try insertingDuplicateField(
            "signedInstallableSHA256",
            value: signedInstallableSHA256,
            into: canonicalEvidence
        )
        let payload = try makePayload(record: record, fieldEvidence: duplicatedEvidence)
        let envelope = try makeEnvelope(
            record: record,
            fieldEvidence: duplicatedEvidence,
            payload: payload,
            signingKey: signingKey
        )

        #expect(
            throws: PassiveBluetoothCaptureFieldAuthorizationError
                .duplicateFieldBuildEvidenceRecordField("signedInstallableSHA256")
        ) {
            _ = try PassiveBluetoothCaptureFieldAuthorizationVerifier.verify(
                envelope,
                publicKeyX963Representation: signingKey.publicKey.x963Representation,
                runtimeBuildIdentity: runtimeIdentity
            )
        }
    }

    @Test
    func legacyV1EnvelopeAndPayloadCannotAcquireSchemaV2Meaning() throws {
        let fixture = try makeFixture()
        var envelopeObject = try jsonObject(fixture.envelope)
        envelopeObject["schemaVersion"] = 1
        let legacyEnvelope = try json(envelopeObject)

        #expect(
            throws: PassiveBluetoothCaptureFieldAuthorizationError
                .unsupportedEnvelopeSchemaVersion(1)
        ) {
            _ = try PassiveBluetoothCaptureFieldAuthorizationVerifier.verify(
                legacyEnvelope,
                publicKeyX963Representation: fixture.privateKey.publicKey.x963Representation,
                runtimeBuildIdentity: fixture.runtimeIdentity
            )
        }

        var payloadObject = try jsonObject(fixture.payload)
        payloadObject["schemaVersion"] = 1
        let legacyPayload = try json(payloadObject)
        let envelope = try makeEnvelope(
            record: fixture.record,
            fieldEvidence: fixture.fieldEvidence,
            payload: legacyPayload,
            signingKey: fixture.privateKey
        )

        #expect(
            throws: PassiveBluetoothCaptureFieldAuthorizationError
                .unsupportedAuthorizationPayloadSchemaVersion(1)
        ) {
            _ = try PassiveBluetoothCaptureFieldAuthorizationVerifier.verify(
                envelope,
                publicKeyX963Representation: fixture.privateKey.publicKey.x963Representation,
                runtimeBuildIdentity: fixture.runtimeIdentity
            )
        }
    }

    @Test
    func onlyCanonicalGoDecisionIsAccepted() throws {
        let fixture = try makeFixture()
        var payloadObject = try jsonObject(fixture.payload)
        payloadObject["decision"] = "NO_GO"
        let noGoPayload = try json(payloadObject)
        let envelope = try makeEnvelope(
            record: fixture.record,
            fieldEvidence: fixture.fieldEvidence,
            payload: noGoPayload,
            signingKey: fixture.privateKey
        )

        #expect(throws: PassiveBluetoothCaptureFieldAuthorizationError.unsupportedDecision("NO_GO")) {
            _ = try PassiveBluetoothCaptureFieldAuthorizationVerifier.verify(
                envelope,
                publicKeyX963Representation: fixture.privateKey.publicKey.x963Representation,
                runtimeBuildIdentity: fixture.runtimeIdentity
            )
        }
    }

    @Test
    func malformedEmbeddedRecordsAndTrustKeyFailClosed() throws {
        let signingKey = P256.Signing.PrivateKey()
        let runtimeIdentity = try makeRuntimeIdentity()
        let malformedRecord = Data("{}".utf8)
        let evidence = try json(
            fieldEvidenceObject(externalRecordSHA256: sha256Hex(malformedRecord))
        )
        let payload = try makePayload(record: malformedRecord, fieldEvidence: evidence)
        let malformedEnvelope = try makeEnvelope(
            record: malformedRecord,
            fieldEvidence: evidence,
            payload: payload,
            signingKey: signingKey
        )

        #expect(throws: PassiveBluetoothCaptureFieldAuthorizationError.invalidExternalBuildRecord) {
            _ = try PassiveBluetoothCaptureFieldAuthorizationVerifier.verify(
                malformedEnvelope,
                publicKeyX963Representation: signingKey.publicKey.x963Representation,
                runtimeBuildIdentity: runtimeIdentity
            )
        }

        let fixture = try makeFixture()
        #expect(throws: PassiveBluetoothCaptureFieldAuthorizationError.invalidAuthorizationPublicKey) {
            _ = try PassiveBluetoothCaptureFieldAuthorizationVerifier.verify(
                fixture.envelope,
                publicKeyX963Representation: Data("not a P-256 key".utf8),
                runtimeBuildIdentity: fixture.runtimeIdentity
            )
        }
    }

    private struct Fixture {
        let privateKey: P256.Signing.PrivateKey
        let runtimeIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity
        let record: Data
        let fieldEvidence: Data
        let payload: Data
        let envelope: Data
    }

    private func makeFixture() throws -> Fixture {
        let signingKey = P256.Signing.PrivateKey()
        let runtimeIdentity = try makeRuntimeIdentity()
        let record = try json(baseRecordObject())
        let fieldEvidence = try json(
            fieldEvidenceObject(externalRecordSHA256: sha256Hex(record))
        )
        let payload = try makePayload(record: record, fieldEvidence: fieldEvidence)
        let envelope = try makeEnvelope(
            record: record,
            fieldEvidence: fieldEvidence,
            payload: payload,
            signingKey: signingKey
        )
        return Fixture(
            privateKey: signingKey,
            runtimeIdentity: runtimeIdentity,
            record: record,
            fieldEvidence: fieldEvidence,
            payload: payload,
            envelope: envelope
        )
    }

    private func verify(
        _ fixture: Fixture,
        runtimeIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity
    ) throws -> PassiveBluetoothCaptureVerifiedFieldAuthorization {
        try PassiveBluetoothCaptureFieldAuthorizationVerifier.verify(
            fixture.envelope,
            publicKeyX963Representation: fixture.privateKey.publicKey.x963Representation,
            runtimeBuildIdentity: runtimeIdentity
        )
    }

    private func makeRuntimeIdentity(
        executableData: Data? = nil,
        infoPlistData: Data? = nil
    ) throws -> PassiveBluetoothCaptureRuntimeBuildIdentity {
        try PassiveBluetoothCaptureRuntimeBuildIdentityReader.resolveEmbeddedMetadata(
            infoDictionary: [
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildIdentifierInfoDictionaryKey:
                    buildIdentifier,
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildInstanceIDInfoDictionaryKey:
                    buildInstanceID,
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.sourceCommitSHAInfoDictionaryKey:
                    sourceCommitSHA,
            ],
            executableData: executableData ?? self.executableData,
            infoPlistData: infoPlistData ?? self.infoPlistData
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

    private func fieldEvidenceObject(externalRecordSHA256: String) -> [String: Any] {
        [
            "schemaVersion": 1,
            "externalBuildRecordSHA256": externalRecordSHA256,
            "signedInstallableSHA256": signedInstallableSHA256,
            "signedInstallableKind": "ipa",
            "buildIdentifier": buildIdentifier,
            "buildInstanceID": buildInstanceID,
            "sourceCommitSHA": sourceCommitSHA,
            "executableSHA256": sha256Hex(executableData),
            "infoPlistSHA256": sha256Hex(infoPlistData),
            "experimentRecipeID": "ES80-FINGERPRINT-v1",
            "procedureVersion": "V14",
        ]
    }

    private func makePayload(record: Data, fieldEvidence: Data) throws -> Data {
        try json([
            "schemaVersion": PassiveBluetoothCaptureFieldAuthorizationVerifier
                .authorizationPayloadSchemaVersion,
            "decision": "GO",
            "externalBuildRecordSHA256": sha256Hex(record),
            "fieldBuildEvidenceRecordSHA256": sha256Hex(fieldEvidence),
        ])
    }

    private func makeEnvelope(
        record: Data,
        fieldEvidence: Data,
        payload: Data,
        signingKey: P256.Signing.PrivateKey
    ) throws -> Data {
        let signature = try signingKey.signature(for: payload)
        return try json([
            "schemaVersion": PassiveBluetoothCaptureFieldAuthorizationVerifier.envelopeSchemaVersion,
            "externalBuildRecordBase64": record.base64EncodedString(),
            "fieldBuildEvidenceRecordBase64": fieldEvidence.base64EncodedString(),
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
