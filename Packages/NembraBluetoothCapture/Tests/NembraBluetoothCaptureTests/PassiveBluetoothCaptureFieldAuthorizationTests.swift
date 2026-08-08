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
    private let retainedIPASHA256 = String(repeating: "a", count: 64)
    private let inspectionSHA256 = String(repeating: "b", count: 64)

    @Test
    func validSignedGoBindsBuildRecordRetainedIPAInspectionAndRuntimeIdentity() throws {
        let fixture = try makeFixture()
        let authorization = try verify(fixture, runtimeIdentity: fixture.runtimeIdentity)

        #expect(authorization.externalBuildRecord.exactRecordSHA256 == sha256Hex(fixture.record))
        #expect(authorization.externalBuildRecord.buildIdentifier == buildIdentifier)
        #expect(authorization.externalBuildRecord.buildInstanceID == buildInstanceID)
        #expect(authorization.externalBuildRecord.sourceCommitSHA == sourceCommitSHA)
        #expect(authorization.externalBuildRecord.executableSHA256 == sha256Hex(executableData))
        #expect(authorization.externalBuildRecord.infoPlistSHA256 == sha256Hex(infoPlistData))
        #expect(authorization.externalBuildRecord.experimentRecipeID == .es80FingerprintV1)
        #expect(authorization.externalBuildRecord.procedureVersion == "V14")
        #expect(authorization.retainedIPASHA256 == retainedIPASHA256)
        #expect(authorization.signedArtifactInspectionSHA256 == inspectionSHA256)
        #expect(authorization.authorizationPayloadSHA256 == sha256Hex(fixture.payload))
    }

    @Test
    func signatureFromDifferentKeyFailsClosed() throws {
        let fixture = try makeFixture(signingKey: P256.Signing.PrivateKey())
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
    func retainedIPAHashCannotChangeWithoutBreakingSignature() throws {
        let fixture = try makeFixture()
        var payloadObject = try jsonObject(fixture.payload)
        payloadObject["retainedIPASHA256"] = String(repeating: "c", count: 64)
        let changedPayload = try json(payloadObject)
        let envelope = try makeEnvelope(
            record: fixture.record,
            payload: changedPayload,
            signatureData: try fixture.privateKey.signature(for: fixture.payload).derRepresentation
        )

        #expect(throws: PassiveBluetoothCaptureFieldAuthorizationError.invalidSignature) {
            _ = try PassiveBluetoothCaptureFieldAuthorizationVerifier.verify(
                envelope,
                publicKeyX963Representation: fixture.privateKey.publicKey.x963Representation,
                runtimeBuildIdentity: fixture.runtimeIdentity
            )
        }
    }

    @Test
    func inspectionHashCannotChangeWithoutBreakingSignature() throws {
        let fixture = try makeFixture()
        var payloadObject = try jsonObject(fixture.payload)
        payloadObject["signedArtifactInspectionSHA256"] = String(repeating: "c", count: 64)
        let changedPayload = try json(payloadObject)
        let envelope = try makeEnvelope(
            record: fixture.record,
            payload: changedPayload,
            signatureData: try fixture.privateKey.signature(for: fixture.payload).derRepresentation
        )

        #expect(throws: PassiveBluetoothCaptureFieldAuthorizationError.invalidSignature) {
            _ = try PassiveBluetoothCaptureFieldAuthorizationVerifier.verify(
                envelope,
                publicKeyX963Representation: fixture.privateKey.publicKey.x963Representation,
                runtimeBuildIdentity: fixture.runtimeIdentity
            )
        }
    }

    @Test
    func nonCanonicalExternalEvidenceHashesFailClosedBeforeAuthority() throws {
        let signingKey = P256.Signing.PrivateKey()
        let runtimeIdentity = try makeRuntimeIdentity()
        let record = try json(baseRecordObject())

        var payload = basePayloadObject(record: record)
        payload["retainedIPASHA256"] = String(repeating: "A", count: 64)
        let uppercaseIPA = try json(payload)
        let uppercaseEnvelope = try makeEnvelope(
            record: record,
            payload: uppercaseIPA,
            signingKey: signingKey
        )
        #expect(throws: PassiveBluetoothCaptureFieldAuthorizationError.invalidRetainedIPASHA256) {
            _ = try PassiveBluetoothCaptureFieldAuthorizationVerifier.verify(
                uppercaseEnvelope,
                publicKeyX963Representation: signingKey.publicKey.x963Representation,
                runtimeBuildIdentity: runtimeIdentity
            )
        }

        payload = basePayloadObject(record: record)
        payload["signedArtifactInspectionSHA256"] = "deadbeef"
        let shortInspection = try json(payload)
        let shortEnvelope = try makeEnvelope(
            record: record,
            payload: shortInspection,
            signingKey: signingKey
        )
        #expect(throws: PassiveBluetoothCaptureFieldAuthorizationError.invalidSignedArtifactInspectionSHA256) {
            _ = try PassiveBluetoothCaptureFieldAuthorizationVerifier.verify(
                shortEnvelope,
                publicKeyX963Representation: signingKey.publicKey.x963Representation,
                runtimeBuildIdentity: runtimeIdentity
            )
        }
    }

    @Test
    func legacyEnvelopeAndPayloadSchemasFailClosed() throws {
        let signingKey = P256.Signing.PrivateKey()
        let runtimeIdentity = try makeRuntimeIdentity()
        let record = try json(baseRecordObject())

        let payloadV1 = try json([
            "schemaVersion": 1,
            "decision": "GO",
            "externalBuildRecordSHA256": sha256Hex(record),
            "retainedIPASHA256": retainedIPASHA256,
            "signedArtifactInspectionSHA256": inspectionSHA256,
        ])
        let envelopeV2 = try makeEnvelope(record: record, payload: payloadV1, signingKey: signingKey)
        #expect(
            throws: PassiveBluetoothCaptureFieldAuthorizationError
                .unsupportedAuthorizationPayloadSchemaVersion(1)
        ) {
            _ = try PassiveBluetoothCaptureFieldAuthorizationVerifier.verify(
                envelopeV2,
                publicKeyX963Representation: signingKey.publicKey.x963Representation,
                runtimeBuildIdentity: runtimeIdentity
            )
        }

        let payloadV2 = try makePayload(record: record)
        let signature = try signingKey.signature(for: payloadV2)
        let envelopeV1 = try json([
            "schemaVersion": 1,
            "externalBuildRecordBase64": record.base64EncodedString(),
            "authorizationPayloadBase64": payloadV2.base64EncodedString(),
            "signatureDERBase64": signature.derRepresentation.base64EncodedString(),
        ])
        #expect(throws: PassiveBluetoothCaptureFieldAuthorizationError.unsupportedEnvelopeSchemaVersion(1)) {
            _ = try PassiveBluetoothCaptureFieldAuthorizationVerifier.verify(
                envelopeV1,
                publicKeyX963Representation: signingKey.publicKey.x963Representation,
                runtimeBuildIdentity: runtimeIdentity
            )
        }
    }

    @Test
    func duplicateEnvelopeAndPayloadMembersFailClosedBeforeFoundationCanCollapseThem() throws {
        let fixture = try makeFixture()
        let duplicateEnvelope = Data(
            """
            {"schemaVersion":2,"schemaVersion":2,"externalBuildRecordBase64":"\(fixture.record.base64EncodedString())","authorizationPayloadBase64":"\(fixture.payload.base64EncodedString())","signatureDERBase64":"x"}
            """.utf8
        )
        #expect(throws: PassiveBluetoothCaptureFieldAuthorizationError.duplicateEnvelopeField("schemaVersion")) {
            _ = try PassiveBluetoothCaptureFieldAuthorizationVerifier.verify(
                duplicateEnvelope,
                publicKeyX963Representation: fixture.privateKey.publicKey.x963Representation,
                runtimeBuildIdentity: fixture.runtimeIdentity
            )
        }

        let duplicatePayload = Data(
            """
            {"schemaVersion":2,"decision":"GO","externalBuildRecordSHA256":"\(sha256Hex(fixture.record))","retainedIPASHA256":"\(retainedIPASHA256)","retainedIPA\\u0053HA256":"\(String(repeating: "c", count: 64))","signedArtifactInspectionSHA256":"\(inspectionSHA256)"}
            """.utf8
        )
        let duplicatePayloadEnvelope = try makeEnvelope(
            record: fixture.record,
            payload: duplicatePayload,
            signingKey: fixture.privateKey
        )
        #expect(
            throws: PassiveBluetoothCaptureFieldAuthorizationError
                .duplicateAuthorizationPayloadField("retainedIPASHA256")
        ) {
            _ = try PassiveBluetoothCaptureFieldAuthorizationVerifier.verify(
                duplicatePayloadEnvelope,
                publicKeyX963Representation: fixture.privateKey.publicKey.x963Representation,
                runtimeBuildIdentity: fixture.runtimeIdentity
            )
        }
    }

    @Test
    func acceptedRecordForDifferentRuntimeExecutableFailsClosed() throws {
        let fixture = try makeFixture()
        let differentRuntime = try makeRuntimeIdentity(
            executableData: Data("different installed executable".utf8)
        )
        #expect(throws: PassiveBluetoothCaptureFieldAuthorizationError.runtimeBuildMismatch) {
            _ = try verify(fixture, runtimeIdentity: differentRuntime)
        }
    }

    @Test
    func acceptedRecordForDifferentRuntimeInfoPlistFailsClosed() throws {
        let fixture = try makeFixture()
        let differentRuntime = try makeRuntimeIdentity(
            infoPlistData: Data("different Info.plist".utf8)
        )
        #expect(throws: PassiveBluetoothCaptureFieldAuthorizationError.runtimeInfoPlistMismatch) {
            _ = try verify(fixture, runtimeIdentity: differentRuntime)
        }
    }

    @Test
    func authorityLookingUnknownEnvelopeAndPayloadFieldsFailClosed() throws {
        let fixture = try makeFixture()
        var envelopeObject = try jsonObject(fixture.envelope)
        envelopeObject["physicalGO"] = true
        let envelopeWithUnknownField = try json(envelopeObject)

        #expect(
            throws: PassiveBluetoothCaptureFieldAuthorizationError.unexpectedEnvelopeField("physicalGO")
        ) {
            _ = try PassiveBluetoothCaptureFieldAuthorizationVerifier.verify(
                envelopeWithUnknownField,
                publicKeyX963Representation: fixture.privateKey.publicKey.x963Representation,
                runtimeBuildIdentity: fixture.runtimeIdentity
            )
        }

        var payloadObject = try jsonObject(fixture.payload)
        payloadObject["fieldAuthorized"] = true
        let payloadWithUnknownField = try json(payloadObject)
        let envelopeWithUnknownPayloadField = try makeEnvelope(
            record: fixture.record,
            payload: payloadWithUnknownField,
            signingKey: fixture.privateKey
        )

        #expect(
            throws: PassiveBluetoothCaptureFieldAuthorizationError
                .unexpectedAuthorizationPayloadField("fieldAuthorized")
        ) {
            _ = try PassiveBluetoothCaptureFieldAuthorizationVerifier.verify(
                envelopeWithUnknownPayloadField,
                publicKeyX963Representation: fixture.privateKey.publicKey.x963Representation,
                runtimeBuildIdentity: fixture.runtimeIdentity
            )
        }
    }

    @Test
    func onlyCanonicalSignedGoDecisionIsAccepted() throws {
        let signingKey = P256.Signing.PrivateKey()
        let runtimeIdentity = try makeRuntimeIdentity()
        let record = try json(baseRecordObject())
        var payloadObject = basePayloadObject(record: record)
        payloadObject["decision"] = "NO_GO"
        let payload = try json(payloadObject)
        let envelope = try makeEnvelope(record: record, payload: payload, signingKey: signingKey)

        #expect(throws: PassiveBluetoothCaptureFieldAuthorizationError.unsupportedDecision("NO_GO")) {
            _ = try PassiveBluetoothCaptureFieldAuthorizationVerifier.verify(
                envelope,
                publicKeyX963Representation: signingKey.publicKey.x963Representation,
                runtimeBuildIdentity: runtimeIdentity
            )
        }
    }

    @Test
    func signedMalformedExternalBuildRecordCannotMintAuthority() throws {
        let signingKey = P256.Signing.PrivateKey()
        let runtimeIdentity = try makeRuntimeIdentity()
        let malformedRecord = Data("{}".utf8)
        let payload = try makePayload(record: malformedRecord)
        let envelope = try makeEnvelope(record: malformedRecord, payload: payload, signingKey: signingKey)

        #expect(throws: PassiveBluetoothCaptureFieldAuthorizationError.invalidExternalBuildRecord) {
            _ = try PassiveBluetoothCaptureFieldAuthorizationVerifier.verify(
                envelope,
                publicKeyX963Representation: signingKey.publicKey.x963Representation,
                runtimeBuildIdentity: runtimeIdentity
            )
        }
    }

    @Test
    func malformedTrustKeyFailsClosedBeforeAuthorityIsMinted() throws {
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
        let payload: Data
        let envelope: Data
    }

    private func makeFixture(
        signingKey: P256.Signing.PrivateKey = P256.Signing.PrivateKey()
    ) throws -> Fixture {
        let runtimeIdentity = try makeRuntimeIdentity()
        let record = try json(baseRecordObject())
        let payload = try makePayload(record: record)
        let envelope = try makeEnvelope(record: record, payload: payload, signingKey: signingKey)
        return Fixture(
            privateKey: signingKey,
            runtimeIdentity: runtimeIdentity,
            record: record,
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

    private func basePayloadObject(record: Data) -> [String: Any] {
        [
            "schemaVersion": 2,
            "decision": "GO",
            "externalBuildRecordSHA256": sha256Hex(record),
            "retainedIPASHA256": retainedIPASHA256,
            "signedArtifactInspectionSHA256": inspectionSHA256,
        ]
    }

    private func makePayload(record: Data) throws -> Data {
        try json(basePayloadObject(record: record))
    }

    private func makeEnvelope(
        record: Data,
        payload: Data,
        signingKey: P256.Signing.PrivateKey
    ) throws -> Data {
        let signature = try signingKey.signature(for: payload)
        return try makeEnvelope(record: record, payload: payload, signatureData: signature.derRepresentation)
    }

    private func makeEnvelope(
        record: Data,
        payload: Data,
        signatureData: Data
    ) throws -> Data {
        try json([
            "schemaVersion": 2,
            "externalBuildRecordBase64": record.base64EncodedString(),
            "authorizationPayloadBase64": payload.base64EncodedString(),
            "signatureDERBase64": signatureData.base64EncodedString(),
        ])
    }

    private func json(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw TestFixtureError.expectedJSONObject
        }
        return dictionary
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private enum TestFixtureError: Error {
        case expectedJSONObject
    }
}
