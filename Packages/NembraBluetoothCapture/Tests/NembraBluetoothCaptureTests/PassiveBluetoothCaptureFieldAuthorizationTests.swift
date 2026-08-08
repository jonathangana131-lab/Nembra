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
    private let ipaData = Data("exact retained signed IPA bytes".utf8)

    @Test
    func validSignedGoBindsExactInstallableEvidenceAndRecordToCurrentRuntimeIdentity() throws {
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
        #expect(authorization.signedFieldArtifactEvidence.exactEvidenceRecordSHA256 == sha256Hex(fixture.fieldEvidence))
        #expect(authorization.signedFieldArtifactEvidence.ipaSHA256 == sha256Hex(ipaData))
        #expect(authorization.signedFieldArtifactEvidence.externalBuildRecordSHA256 == sha256Hex(fixture.record))
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
    func signedPayloadCannotBeReboundToDifferentSignedInstallableEvidenceBytes() throws {
        let fixture = try makeFixture()
        var alternate = try jsonObject(fixture.fieldEvidence)
        alternate["ipaSHA256"] = sha256Hex(Data("different signed IPA".utf8))
        let alternateEvidence = try json(alternate)
        let rebound = try makeEnvelope(
            record: fixture.record,
            fieldEvidence: alternateEvidence,
            payload: fixture.payload,
            signingKey: fixture.privateKey
        )

        #expect(throws: PassiveBluetoothCaptureFieldAuthorizationError.signedFieldArtifactEvidenceDigestMismatch) {
            _ = try PassiveBluetoothCaptureFieldAuthorizationVerifier.verify(
                rebound,
                publicKeyX963Representation: fixture.privateKey.publicKey.x963Representation,
                runtimeBuildIdentity: fixture.runtimeIdentity
            )
        }
    }

    @Test
    func independentlySignedEvidenceForDetachedBuildTupleFailsClosed() throws {
        let signingKey = P256.Signing.PrivateKey()
        let runtimeIdentity = try makeRuntimeIdentity()
        let record = try json(baseRecordObject())
        var fieldObject = try baseFieldEvidenceObject(record: record)
        fieldObject["executableSHA256"] = sha256Hex(Data("detached executable declaration".utf8))
        let fieldEvidence = try json(fieldObject)
        let payload = try makePayload(record: record, fieldEvidence: fieldEvidence)
        let envelope = try makeEnvelope(
            record: record,
            fieldEvidence: fieldEvidence,
            payload: payload,
            signingKey: signingKey
        )

        #expect(throws: PassiveBluetoothCaptureFieldAuthorizationError.signedFieldArtifactEvidenceMismatch) {
            _ = try PassiveBluetoothCaptureFieldAuthorizationVerifier.verify(
                envelope,
                publicKeyX963Representation: signingKey.publicKey.x963Representation,
                runtimeBuildIdentity: runtimeIdentity
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
            fieldEvidence: fixture.fieldEvidence,
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
        let fieldEvidence = try json(baseFieldEvidenceObject(record: record))
        let payload = try json([
            "schemaVersion": 2,
            "decision": "NO_GO",
            "externalBuildRecordSHA256": sha256Hex(record),
            "signedFieldArtifactEvidenceSHA256": sha256Hex(fieldEvidence),
        ])
        let envelope = try makeEnvelope(
            record: record,
            fieldEvidence: fieldEvidence,
            payload: payload,
            signingKey: signingKey
        )

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
        let fieldEvidence = try json(baseFieldEvidenceObject(record: malformedRecord))
        let payload = try makePayload(record: malformedRecord, fieldEvidence: fieldEvidence)
        let envelope = try makeEnvelope(
            record: malformedRecord,
            fieldEvidence: fieldEvidence,
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

    @Test
    func signedMalformedFieldEvidenceCannotMintAuthority() throws {
        let signingKey = P256.Signing.PrivateKey()
        let runtimeIdentity = try makeRuntimeIdentity()
        let record = try json(baseRecordObject())
        let malformedEvidence = Data("{}".utf8)
        let payload = try makePayload(record: record, fieldEvidence: malformedEvidence)
        let envelope = try makeEnvelope(
            record: record,
            fieldEvidence: malformedEvidence,
            payload: payload,
            signingKey: signingKey
        )

        #expect(throws: PassiveBluetoothCaptureFieldAuthorizationError.invalidSignedFieldArtifactEvidence) {
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
        let fieldEvidence: Data
        let payload: Data
        let envelope: Data
    }

    private func makeFixture(
        signingKey: P256.Signing.PrivateKey = P256.Signing.PrivateKey()
    ) throws -> Fixture {
        let runtimeIdentity = try makeRuntimeIdentity()
        let record = try json(baseRecordObject())
        let fieldEvidence = try json(baseFieldEvidenceObject(record: record))
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

    private func baseFieldEvidenceObject(record: Data) throws -> [String: Any] {
        [
            "schemaVersion": 2,
            "authority": "signed-field-artifact-evidence-not-field-authorization",
            "buildIdentifier": buildIdentifier,
            "buildInstanceID": buildInstanceID,
            "sourceCommitSHA": sourceCommitSHA,
            "bundleIdentifier": "com.jonathangana131.nembra",
            "platformName": "iphoneos",
            "supportedPlatforms": ["iPhoneOS"],
            "teamIdentifier": "ABCDEFGHIJ",
            "signingAuthorities": ["Apple Development: Nembra"],
            "codeDirectoryHash": String(repeating: "a", count: 40),
            "provisioningProfileUUID": "12345678-1234-4234-8234-123456789abc",
            "provisioningProfileExpirationUTC": "2030-01-01T00:00:00Z",
            "ipaSHA256": sha256Hex(ipaData),
            "ipaByteCount": ipaData.count,
            "executableSHA256": sha256Hex(executableData),
            "infoPlistSHA256": sha256Hex(infoPlistData),
            "externalBuildRecordSHA256": sha256Hex(record),
            "experimentRecipeID": "ES80-FINGERPRINT-v1",
            "procedureVersion": "V14",
        ]
    }

    private func makePayload(record: Data, fieldEvidence: Data) throws -> Data {
        try json([
            "schemaVersion": 2,
            "decision": "GO",
            "externalBuildRecordSHA256": sha256Hex(record),
            "signedFieldArtifactEvidenceSHA256": sha256Hex(fieldEvidence),
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
            "schemaVersion": 2,
            "externalBuildRecordBase64": record.base64EncodedString(),
            "signedFieldArtifactEvidenceBase64": fieldEvidence.base64EncodedString(),
            "authorizationPayloadBase64": payload.base64EncodedString(),
            "signatureDERBase64": signature.derRepresentation.base64EncodedString(),
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
