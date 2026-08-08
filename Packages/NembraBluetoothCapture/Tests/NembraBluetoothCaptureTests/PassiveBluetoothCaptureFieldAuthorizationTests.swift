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
    private let signedInstallableSHA256 = String(repeating: "d", count: 64)

    @Test
    func validSignedGoBindsExactInstallableEvidenceAndCurrentRuntimeIdentity() throws {
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
        #expect(authorization.signedInstallableSHA256 == signedInstallableSHA256)
        #expect(authorization.fieldBuildEvidenceRecordSHA256 == sha256Hex(fixture.evidence))
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
        alternate["buildInstanceID"] = "11111111-2222-4333-8444-555555555555"
        let alternateRecord = try json(alternate)
        let rebound = try makeEnvelope(
            record: alternateRecord,
            evidence: fixture.evidence,
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
    func signedPayloadCannotBeReboundToDifferentInstallableEvidenceBytes() throws {
        let fixture = try makeFixture()
        let alternateEvidence = try makeEvidence(
            record: fixture.record,
            overrides: ["signedInstallableSHA256": String(repeating: "e", count: 64)]
        )
        let rebound = try makeEnvelope(
            record: fixture.record,
            evidence: alternateEvidence,
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
    func separatelySignedEvidenceForDifferentBuildTupleCannotMintAuthority() throws {
        let fixture = try makeFixture()
        let mismatchedEvidence = try makeEvidence(
            record: fixture.record,
            overrides: ["executableSHA256": String(repeating: "e", count: 64)]
        )
        let payload = try makePayload(record: fixture.record, evidence: mismatchedEvidence)
        let envelope = try makeEnvelope(
            record: fixture.record,
            evidence: mismatchedEvidence,
            payload: payload,
            signingKey: fixture.privateKey
        )

        #expect(throws: PassiveBluetoothCaptureFieldAuthorizationError.fieldBuildEvidenceRecordMismatch) {
            _ = try PassiveBluetoothCaptureFieldAuthorizationVerifier.verify(
                envelope,
                publicKeyX963Representation: fixture.privateKey.publicKey.x963Representation,
                runtimeBuildIdentity: fixture.runtimeIdentity
            )
        }
    }

    @Test
    func separatelySignedEvidenceDetachedFromExternalRecordCannotMintAuthority() throws {
        let fixture = try makeFixture()
        let detachedEvidence = try makeEvidence(
            record: fixture.record,
            overrides: ["externalBuildRecordSHA256": String(repeating: "e", count: 64)]
        )
        let payload = try makePayload(record: fixture.record, evidence: detachedEvidence)
        let envelope = try makeEnvelope(
            record: fixture.record,
            evidence: detachedEvidence,
            payload: payload,
            signingKey: fixture.privateKey
        )

        #expect(throws: PassiveBluetoothCaptureFieldAuthorizationError.fieldBuildEvidenceRecordMismatch) {
            _ = try PassiveBluetoothCaptureFieldAuthorizationVerifier.verify(
                envelope,
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
    func legacyEnvelopeWithoutInstallableEvidenceCannotMintAuthority() throws {
        let fixture = try makeFixture()
        var envelopeObject = try jsonObject(fixture.envelope)
        envelopeObject.removeValue(forKey: "fieldBuildEvidenceRecordBase64")
        let legacyEnvelope = try json(envelopeObject)

        #expect(throws: PassiveBluetoothCaptureFieldAuthorizationError.malformedEnvelope) {
            _ = try PassiveBluetoothCaptureFieldAuthorizationVerifier.verify(
                legacyEnvelope,
                publicKeyX963Representation: fixture.privateKey.publicKey.x963Representation,
                runtimeBuildIdentity: fixture.runtimeIdentity
            )
        }
    }

    @Test
    func authorityLookingUnknownEnvelopePayloadAndEvidenceFieldsFailClosed() throws {
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
            evidence: fixture.evidence,
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

        var evidenceObject = try jsonObject(fixture.evidence)
        evidenceObject["physicalGO"] = true
        let evidenceWithUnknownField = try json(evidenceObject)
        let payloadForUnknownEvidence = try makePayload(
            record: fixture.record,
            evidence: evidenceWithUnknownField
        )
        let envelopeWithUnknownEvidenceField = try makeEnvelope(
            record: fixture.record,
            evidence: evidenceWithUnknownField,
            payload: payloadForUnknownEvidence,
            signingKey: fixture.privateKey
        )

        #expect(throws: PassiveBluetoothCaptureFieldAuthorizationError.invalidFieldBuildEvidenceRecord) {
            _ = try PassiveBluetoothCaptureFieldAuthorizationVerifier.verify(
                envelopeWithUnknownEvidenceField,
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
        let evidence = try makeEvidence(record: record)
        let payload = try json([
            "schemaVersion": 1,
            "decision": "NO_GO",
            "externalBuildRecordSHA256": sha256Hex(record),
            "fieldBuildEvidenceRecordSHA256": sha256Hex(evidence),
        ])
        let envelope = try makeEnvelope(
            record: record,
            evidence: evidence,
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
        let evidence = try makeEvidence(record: malformedRecord)
        let payload = try makePayload(record: malformedRecord, evidence: evidence)
        let envelope = try makeEnvelope(
            record: malformedRecord,
            evidence: evidence,
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
    func signedMalformedInstallableEvidenceCannotMintAuthority() throws {
        let fixture = try makeFixture()
        let malformedEvidence = Data("{}".utf8)
        let payload = try makePayload(record: fixture.record, evidence: malformedEvidence)
        let envelope = try makeEnvelope(
            record: fixture.record,
            evidence: malformedEvidence,
            payload: payload,
            signingKey: fixture.privateKey
        )

        #expect(throws: PassiveBluetoothCaptureFieldAuthorizationError.invalidFieldBuildEvidenceRecord) {
            _ = try PassiveBluetoothCaptureFieldAuthorizationVerifier.verify(
                envelope,
                publicKeyX963Representation: fixture.privateKey.publicKey.x963Representation,
                runtimeBuildIdentity: fixture.runtimeIdentity
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
        let evidence: Data
        let payload: Data
        let envelope: Data
    }

    private func makeFixture(
        signingKey: P256.Signing.PrivateKey = P256.Signing.PrivateKey()
    ) throws -> Fixture {
        let runtimeIdentity = try makeRuntimeIdentity()
        let record = try json(baseRecordObject())
        let evidence = try makeEvidence(record: record)
        let payload = try makePayload(record: record, evidence: evidence)
        let envelope = try makeEnvelope(
            record: record,
            evidence: evidence,
            payload: payload,
            signingKey: signingKey
        )
        return Fixture(
            privateKey: signingKey,
            runtimeIdentity: runtimeIdentity,
            record: record,
            evidence: evidence,
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

    private func makeEvidence(
        record: Data,
        overrides: [String: Any] = [:]
    ) throws -> Data {
        var object: [String: Any] = [
            "schemaVersion": 1,
            "externalBuildRecordSHA256": sha256Hex(record),
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
        for (key, value) in overrides {
            object[key] = value
        }
        return try json(object)
    }

    private func makePayload(record: Data, evidence: Data) throws -> Data {
        try json([
            "schemaVersion": 1,
            "decision": "GO",
            "externalBuildRecordSHA256": sha256Hex(record),
            "fieldBuildEvidenceRecordSHA256": sha256Hex(evidence),
        ])
    }

    private func makeEnvelope(
        record: Data,
        evidence: Data,
        payload: Data,
        signingKey: P256.Signing.PrivateKey
    ) throws -> Data {
        let signature = try signingKey.signature(for: payload)
        return try json([
            "schemaVersion": 1,
            "externalBuildRecordBase64": record.base64EncodedString(),
            "fieldBuildEvidenceRecordBase64": evidence.base64EncodedString(),
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