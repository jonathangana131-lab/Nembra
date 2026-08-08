import CryptoKit
import Foundation

/// A field-authorization result minted only after a signed external GO envelope is verified against
/// Nembra's independent package-pinned authority, one exact externally accepted signed-installable
/// evidence record, and the exact build identity measured from the running application.
///
/// This is software field-build authority only. It does not authenticate an AOVOPRO ES80, prove RF
/// completeness, establish protocol/telemetry semantics, or prove the physical procedure occurred.
public struct PassiveBluetoothCaptureVerifiedFieldAuthorization: Equatable, Sendable {
    public let externalBuildRecord: PassiveBluetoothCaptureExternalBuildRecord
    public let signedInstallableSHA256: String
    public let signedFieldArtifactEvidenceSHA256: String
    public let authorizationPayloadSHA256: String

    fileprivate init(
        externalBuildRecord: PassiveBluetoothCaptureExternalBuildRecord,
        signedInstallableSHA256: String,
        signedFieldArtifactEvidenceSHA256: String,
        authorizationPayloadSHA256: String
    ) {
        self.externalBuildRecord = externalBuildRecord
        self.signedInstallableSHA256 = signedInstallableSHA256
        self.signedFieldArtifactEvidenceSHA256 = signedFieldArtifactEvidenceSHA256
        self.authorizationPayloadSHA256 = authorizationPayloadSHA256
    }
}

public enum PassiveBluetoothCaptureFieldAuthorizationError: Error, Equatable, Sendable {
    case malformedEnvelope
    case unexpectedEnvelopeField(String)
    case unsupportedEnvelopeSchemaVersion(Int)
    case invalidExternalBuildRecordBase64
    case invalidSignedFieldArtifactEvidenceBase64
    case invalidAuthorizationPayloadBase64
    case invalidSignatureBase64
    case malformedAuthorizationPayload
    case unexpectedAuthorizationPayloadField(String)
    case unsupportedAuthorizationPayloadSchemaVersion(Int)
    case unsupportedDecision(String)
    case invalidExternalBuildRecordSHA256
    case invalidSignedFieldArtifactEvidenceSHA256
    case externalBuildRecordDigestMismatch
    case signedFieldArtifactEvidenceDigestMismatch
    case invalidExternalBuildRecord
    case malformedSignedFieldArtifactEvidence
    case unexpectedSignedFieldArtifactEvidenceField(String)
    case unsupportedSignedFieldArtifactEvidenceSchemaVersion(Int)
    case invalidSignedFieldArtifactEvidence
    case signedFieldArtifactEvidenceExternalRecordMismatch
    case signedFieldArtifactEvidenceBuildMismatch
    case authorizationTrustAnchorNotConfigured
    case invalidAuthorizationPublicKey
    case invalidSignature
    case runtimeBuildMismatch
    case runtimeInfoPlistMismatch
}

/// Package-owned trust root for final field authorization.
///
/// This stays deliberately unconfigured while physical Experiment One remains NO-GO. A future
/// field release must pin only the independently controlled authority's P-256 public key here in
/// reviewed source. The running app, Info.plist, imported envelope, preferences, and caller input
/// cannot select their own trust root.
enum PassiveBluetoothCaptureFieldAuthorizationTrustAnchor {
    static let publicKeyX963Representation: Data? = nil
}

/// Verifies a post-build field-authorization envelope without embedding final artifact hashes back
/// into the signed app. The external authority signs an exact GO payload only after the exact signed
/// IPA evidence and schema-v3 external build record are known and independently accepted.
public enum PassiveBluetoothCaptureFieldAuthorizationVerifier {
    public static let envelopeSchemaVersion = 1
    public static let authorizationPayloadSchemaVersion = 1
    public static let signedFieldArtifactEvidenceSchemaVersion = 1

    private static let signedFieldArtifactEvidenceAuthority =
        "signed-field-artifact-evidence-not-field-authorization"
    private static let nembraBundleIdentifier = "com.jonathangana131.nembra"

    private struct EnvelopeWire: Decodable {
        let schemaVersion: Int
        let externalBuildRecordBase64: String
        let signedFieldArtifactEvidenceBase64: String
        let authorizationPayloadBase64: String
        let signatureDERBase64: String
    }

    private struct AuthorizationPayloadWire: Decodable {
        let schemaVersion: Int
        let decision: String
        let externalBuildRecordSHA256: String
        let signedFieldArtifactEvidenceSHA256: String
    }

    /// Closed-world view of the existing rich evidence emitted by
    /// `scripts/ci/es80_signed_field_artifact_evidence.py`.
    ///
    /// This evidence is not authority by itself. Its exact bytes become authoritative for one field
    /// release only because the independently controlled package-pinned authority signs their digest
    /// together with the exact schema-v3 external build-record digest in the GO payload.
    private struct SignedFieldArtifactEvidenceWire: Decodable {
        let schemaVersion: Int
        let authority: String
        let buildIdentifier: String
        let buildInstanceID: String
        let sourceCommitSHA: String
        let bundleIdentifier: String
        let platformName: String
        let supportedPlatforms: [String]
        let teamIdentifier: String
        let signingAuthorities: [String]
        let ipaSHA256: String
        let ipaByteCount: Int
        let executableSHA256: String
        let infoPlistSHA256: String
        let externalBuildRecordSHA256: String
        let experimentRecipeID: String
        let procedureVersion: String
    }

    /// Production verification uses only the package-owned trust root and the canonical runtime
    /// identity reader. Until a reviewed authority key is pinned, this fails closed before it can
    /// mint any field authorization.
    public static func verifyForCurrentApplication(
        _ envelopeData: Data
    ) throws -> PassiveBluetoothCaptureVerifiedFieldAuthorization {
        guard let publicKey = PassiveBluetoothCaptureFieldAuthorizationTrustAnchor
            .publicKeyX963Representation else {
            throw PassiveBluetoothCaptureFieldAuthorizationError.authorizationTrustAnchorNotConfigured
        }
        let runtimeIdentity = try PassiveBluetoothCaptureRuntimeBuildIdentityReader.currentApplication()
        return try verify(
            envelopeData,
            publicKeyX963Representation: publicKey,
            runtimeBuildIdentity: runtimeIdentity
        )
    }

    /// Package-scoped deterministic seam for verifier tests. Production app code cannot supply a
    /// caller-selected runtime identity or trust key to mint field authority.
    package static func verify(
        _ envelopeData: Data,
        publicKeyX963Representation: Data,
        runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity
    ) throws -> PassiveBluetoothCaptureVerifiedFieldAuthorization {
        try validateClosedWorldEnvelope(envelopeData)

        let envelope: EnvelopeWire
        do {
            envelope = try JSONDecoder().decode(EnvelopeWire.self, from: envelopeData)
        } catch {
            throw PassiveBluetoothCaptureFieldAuthorizationError.malformedEnvelope
        }
        guard envelope.schemaVersion == envelopeSchemaVersion else {
            throw PassiveBluetoothCaptureFieldAuthorizationError
                .unsupportedEnvelopeSchemaVersion(envelope.schemaVersion)
        }

        guard let externalBuildRecordData = decodeCanonicalBase64(
            envelope.externalBuildRecordBase64
        ) else {
            throw PassiveBluetoothCaptureFieldAuthorizationError.invalidExternalBuildRecordBase64
        }
        guard let signedFieldArtifactEvidenceData = decodeCanonicalBase64(
            envelope.signedFieldArtifactEvidenceBase64
        ) else {
            throw PassiveBluetoothCaptureFieldAuthorizationError
                .invalidSignedFieldArtifactEvidenceBase64
        }
        guard let authorizationPayloadData = decodeCanonicalBase64(
            envelope.authorizationPayloadBase64
        ) else {
            throw PassiveBluetoothCaptureFieldAuthorizationError.invalidAuthorizationPayloadBase64
        }
        guard let signatureData = decodeCanonicalBase64(envelope.signatureDERBase64) else {
            throw PassiveBluetoothCaptureFieldAuthorizationError.invalidSignatureBase64
        }

        try validateClosedWorldAuthorizationPayload(authorizationPayloadData)
        let payload: AuthorizationPayloadWire
        do {
            payload = try JSONDecoder().decode(
                AuthorizationPayloadWire.self,
                from: authorizationPayloadData
            )
        } catch {
            throw PassiveBluetoothCaptureFieldAuthorizationError.malformedAuthorizationPayload
        }
        guard payload.schemaVersion == authorizationPayloadSchemaVersion else {
            throw PassiveBluetoothCaptureFieldAuthorizationError
                .unsupportedAuthorizationPayloadSchemaVersion(payload.schemaVersion)
        }
        guard payload.decision == "GO" else {
            throw PassiveBluetoothCaptureFieldAuthorizationError.unsupportedDecision(payload.decision)
        }
        guard isCanonicalSHA256(payload.externalBuildRecordSHA256) else {
            throw PassiveBluetoothCaptureFieldAuthorizationError.invalidExternalBuildRecordSHA256
        }
        guard isCanonicalSHA256(payload.signedFieldArtifactEvidenceSHA256) else {
            throw PassiveBluetoothCaptureFieldAuthorizationError
                .invalidSignedFieldArtifactEvidenceSHA256
        }

        let exactExternalRecordSHA256 = sha256Hex(externalBuildRecordData)
        guard exactExternalRecordSHA256 == payload.externalBuildRecordSHA256 else {
            throw PassiveBluetoothCaptureFieldAuthorizationError.externalBuildRecordDigestMismatch
        }
        let exactSignedFieldArtifactEvidenceSHA256 = sha256Hex(signedFieldArtifactEvidenceData)
        guard exactSignedFieldArtifactEvidenceSHA256 == payload.signedFieldArtifactEvidenceSHA256 else {
            throw PassiveBluetoothCaptureFieldAuthorizationError
                .signedFieldArtifactEvidenceDigestMismatch
        }

        let publicKey: P256.Signing.PublicKey
        do {
            publicKey = try P256.Signing.PublicKey(x963Representation: publicKeyX963Representation)
        } catch {
            throw PassiveBluetoothCaptureFieldAuthorizationError.invalidAuthorizationPublicKey
        }
        let signature: P256.Signing.ECDSASignature
        do {
            signature = try P256.Signing.ECDSASignature(derRepresentation: signatureData)
        } catch {
            throw PassiveBluetoothCaptureFieldAuthorizationError.invalidSignature
        }
        guard publicKey.isValidSignature(signature, for: authorizationPayloadData) else {
            throw PassiveBluetoothCaptureFieldAuthorizationError.invalidSignature
        }

        let externalBuildRecord: PassiveBluetoothCaptureExternalBuildRecord
        do {
            externalBuildRecord = try PassiveBluetoothCaptureExternalBuildRecordJSON
                .decodeDeclaration(externalBuildRecordData)
        } catch {
            throw PassiveBluetoothCaptureFieldAuthorizationError.invalidExternalBuildRecord
        }

        let signedFieldArtifactEvidence = try decodeSignedFieldArtifactEvidence(
            signedFieldArtifactEvidenceData
        )
        guard signedFieldArtifactEvidence.externalBuildRecordSHA256 == exactExternalRecordSHA256 else {
            throw PassiveBluetoothCaptureFieldAuthorizationError
                .signedFieldArtifactEvidenceExternalRecordMismatch
        }
        guard signedFieldArtifactEvidence.buildIdentifier == externalBuildRecord.buildIdentifier,
              signedFieldArtifactEvidence.buildInstanceID == externalBuildRecord.buildInstanceID,
              signedFieldArtifactEvidence.sourceCommitSHA == externalBuildRecord.sourceCommitSHA,
              signedFieldArtifactEvidence.executableSHA256 == externalBuildRecord.executableSHA256,
              signedFieldArtifactEvidence.infoPlistSHA256 == externalBuildRecord.infoPlistSHA256,
              signedFieldArtifactEvidence.experimentRecipeID == externalBuildRecord.experimentRecipeID.rawValue,
              signedFieldArtifactEvidence.procedureVersion == externalBuildRecord.procedureVersion else {
            throw PassiveBluetoothCaptureFieldAuthorizationError
                .signedFieldArtifactEvidenceBuildMismatch
        }

        guard externalBuildRecord.buildIdentifier == runtimeBuildIdentity.buildIdentifier,
              externalBuildRecord.buildInstanceID == runtimeBuildIdentity.buildInstanceID,
              externalBuildRecord.sourceCommitSHA == runtimeBuildIdentity.sourceCommitSHA,
              externalBuildRecord.executableSHA256 == runtimeBuildIdentity.executableSHA256 else {
            throw PassiveBluetoothCaptureFieldAuthorizationError.runtimeBuildMismatch
        }
        guard externalBuildRecord.infoPlistSHA256 == runtimeBuildIdentity.infoPlistSHA256 else {
            throw PassiveBluetoothCaptureFieldAuthorizationError.runtimeInfoPlistMismatch
        }

        return PassiveBluetoothCaptureVerifiedFieldAuthorization(
            externalBuildRecord: externalBuildRecord,
            signedInstallableSHA256: signedFieldArtifactEvidence.ipaSHA256,
            signedFieldArtifactEvidenceSHA256: exactSignedFieldArtifactEvidenceSHA256,
            authorizationPayloadSHA256: sha256Hex(authorizationPayloadData)
        )
    }

    private static func decodeSignedFieldArtifactEvidence(
        _ data: Data
    ) throws -> SignedFieldArtifactEvidenceWire {
        try validateClosedWorldSignedFieldArtifactEvidence(data)
        let evidence: SignedFieldArtifactEvidenceWire
        do {
            evidence = try JSONDecoder().decode(SignedFieldArtifactEvidenceWire.self, from: data)
        } catch {
            throw PassiveBluetoothCaptureFieldAuthorizationError.malformedSignedFieldArtifactEvidence
        }
        guard evidence.schemaVersion == signedFieldArtifactEvidenceSchemaVersion else {
            throw PassiveBluetoothCaptureFieldAuthorizationError
                .unsupportedSignedFieldArtifactEvidenceSchemaVersion(evidence.schemaVersion)
        }
        guard evidence.authority == signedFieldArtifactEvidenceAuthority,
              evidence.bundleIdentifier == nembraBundleIdentifier,
              evidence.platformName == "iphoneos",
              evidence.supportedPlatforms.contains("iPhoneOS"),
              !evidence.supportedPlatforms.contains(where: { $0.contains("Simulator") }),
              !evidence.teamIdentifier.isEmpty,
              !["not set", "none", "-"].contains(evidence.teamIdentifier.lowercased()),
              !evidence.signingAuthorities.isEmpty,
              evidence.signingAuthorities.allSatisfy({ !$0.isEmpty }),
              evidence.ipaByteCount > 0,
              isValidBuildIdentifier(evidence.buildIdentifier),
              PassiveBluetoothCaptureRuntimeBuildIdentityReader
                .normalizedBuildInstanceID(evidence.buildInstanceID) == evidence.buildInstanceID,
              PassiveBluetoothCaptureRuntimeBuildIdentityReader
                .normalizedFullGitCommitSHA(evidence.sourceCommitSHA) == evidence.sourceCommitSHA,
              isCanonicalSHA256(evidence.ipaSHA256),
              isCanonicalSHA256(evidence.executableSHA256),
              isCanonicalSHA256(evidence.infoPlistSHA256),
              isCanonicalSHA256(evidence.externalBuildRecordSHA256),
              evidence.experimentRecipeID == PassiveBluetoothExperimentRecipeID.es80FingerprintV1.rawValue,
              evidence.procedureVersion == PassiveBluetoothCaptureExternalBuildRecord.requiredProcedureVersion else {
            throw PassiveBluetoothCaptureFieldAuthorizationError.invalidSignedFieldArtifactEvidence
        }
        return evidence
    }

    private static func validateClosedWorldEnvelope(_ data: Data) throws {
        let root = try jsonObject(data, malformed: .malformedEnvelope)
        let allowed: Set<String> = [
            "schemaVersion",
            "externalBuildRecordBase64",
            "signedFieldArtifactEvidenceBase64",
            "authorizationPayloadBase64",
            "signatureDERBase64",
        ]
        for key in root.keys.sorted() where !allowed.contains(key) {
            throw PassiveBluetoothCaptureFieldAuthorizationError.unexpectedEnvelopeField(key)
        }
    }

    private static func validateClosedWorldAuthorizationPayload(_ data: Data) throws {
        let root = try jsonObject(data, malformed: .malformedAuthorizationPayload)
        let allowed: Set<String> = [
            "schemaVersion",
            "decision",
            "externalBuildRecordSHA256",
            "signedFieldArtifactEvidenceSHA256",
        ]
        for key in root.keys.sorted() where !allowed.contains(key) {
            throw PassiveBluetoothCaptureFieldAuthorizationError
                .unexpectedAuthorizationPayloadField(key)
        }
    }

    private static func validateClosedWorldSignedFieldArtifactEvidence(_ data: Data) throws {
        let root = try jsonObject(data, malformed: .malformedSignedFieldArtifactEvidence)
        let allowed: Set<String> = [
            "schemaVersion",
            "authority",
            "buildIdentifier",
            "buildInstanceID",
            "sourceCommitSHA",
            "bundleIdentifier",
            "platformName",
            "supportedPlatforms",
            "teamIdentifier",
            "signingAuthorities",
            "ipaSHA256",
            "ipaByteCount",
            "executableSHA256",
            "infoPlistSHA256",
            "externalBuildRecordSHA256",
            "experimentRecipeID",
            "procedureVersion",
        ]
        for key in root.keys.sorted() where !allowed.contains(key) {
            throw PassiveBluetoothCaptureFieldAuthorizationError
                .unexpectedSignedFieldArtifactEvidenceField(key)
        }
    }

    private static func jsonObject(
        _ data: Data,
        malformed: PassiveBluetoothCaptureFieldAuthorizationError
    ) throws -> [String: Any] {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw malformed
        }
        guard let root = object as? [String: Any] else {
            throw malformed
        }
        return root
    }

    private static func decodeCanonicalBase64(_ value: String) -> Data? {
        guard let data = Data(base64Encoded: value),
              data.base64EncodedString() == value else {
            return nil
        }
        return data
    }

    private static func isValidBuildIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 128 else { return false }
        guard value == value.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        guard !value.unicodeScalars.contains(where: { scalar in
            CharacterSet.controlCharacters.contains(scalar)
        }) else {
            return false
        }
        return true
    }

    private static func isCanonicalSHA256(_ value: String) -> Bool {
        guard value.utf8.count == 64 else { return false }
        return value.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (97...102).contains(byte)
        }
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}