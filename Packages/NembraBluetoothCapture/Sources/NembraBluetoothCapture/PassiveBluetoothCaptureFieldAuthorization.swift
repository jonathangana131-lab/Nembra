import CryptoKit
import Foundation

/// A field-authorization result minted only after a signed external GO envelope is verified against
/// both Nembra's independent package-pinned authority and the exact build identity measured from the
/// running application.
///
/// The authorization also carries the independently signed subjects for the exact retained field
/// evidence record and exact retained IPA. These digests are authority/audit bindings; they do not
/// make the running app capable of reconstructing or re-verifying the original IPA container after
/// installation.
///
/// This is software field-build authority only. It does not authenticate an AOVOPRO ES80, prove RF
/// completeness, establish protocol/telemetry semantics, or prove the physical procedure occurred.
public struct PassiveBluetoothCaptureVerifiedFieldAuthorization: Equatable, Sendable {
    public let externalBuildRecord: PassiveBluetoothCaptureExternalBuildRecord
    public let signedFieldArtifactEvidenceSHA256: String
    public let retainedIPASHA256: String
    public let authorizationPayloadSHA256: String

    fileprivate init(
        externalBuildRecord: PassiveBluetoothCaptureExternalBuildRecord,
        signedFieldArtifactEvidenceSHA256: String,
        retainedIPASHA256: String,
        authorizationPayloadSHA256: String
    ) {
        self.externalBuildRecord = externalBuildRecord
        self.signedFieldArtifactEvidenceSHA256 = signedFieldArtifactEvidenceSHA256
        self.retainedIPASHA256 = retainedIPASHA256
        self.authorizationPayloadSHA256 = authorizationPayloadSHA256
    }
}

public enum PassiveBluetoothCaptureFieldAuthorizationError: Error, Equatable, Sendable {
    case malformedEnvelope
    case unexpectedEnvelopeField(String)
    case unsupportedEnvelopeSchemaVersion(Int)
    case invalidExternalBuildRecordBase64
    case invalidAuthorizationPayloadBase64
    case invalidSignatureBase64
    case malformedAuthorizationPayload
    case unexpectedAuthorizationPayloadField(String)
    case unsupportedAuthorizationPayloadSchemaVersion(Int)
    case unsupportedDecision(String)
    case invalidExternalBuildRecordSHA256
    case invalidSignedFieldArtifactEvidenceSHA256
    case invalidRetainedIPASHA256
    case externalBuildRecordDigestMismatch
    case invalidExternalBuildRecord
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
/// into the signed app. The external authority signs an exact GO payload only after the signed build,
/// its retained signed-field-artifact evidence, and the schema-v3 external build record are known and
/// independently accepted.
///
/// The exact field-evidence and IPA digests are deliberately part of the signed payload rather than
/// inferred from a matching build tuple. This prevents a future GO issuer from accidentally blessing
/// only build-label/runtime self-consistency while omitting the exact signed-installable evidence that
/// V14 requires before physical execution can be considered.
public enum PassiveBluetoothCaptureFieldAuthorizationVerifier {
    public static let envelopeSchemaVersion = 1
    public static let authorizationPayloadSchemaVersion = 1

    private struct EnvelopeWire: Decodable {
        let schemaVersion: Int
        let externalBuildRecordBase64: String
        let authorizationPayloadBase64: String
        let signatureDERBase64: String
    }

    private struct AuthorizationPayloadWire: Decodable {
        let schemaVersion: Int
        let decision: String
        let externalBuildRecordSHA256: String
        let signedFieldArtifactEvidenceSHA256: String
        let retainedIPASHA256: String
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
        guard isCanonicalSHA256(payload.retainedIPASHA256) else {
            throw PassiveBluetoothCaptureFieldAuthorizationError.invalidRetainedIPASHA256
        }

        let exactExternalRecordSHA256 = sha256Hex(externalBuildRecordData)
        guard exactExternalRecordSHA256 == payload.externalBuildRecordSHA256 else {
            throw PassiveBluetoothCaptureFieldAuthorizationError.externalBuildRecordDigestMismatch
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
            signedFieldArtifactEvidenceSHA256: payload.signedFieldArtifactEvidenceSHA256,
            retainedIPASHA256: payload.retainedIPASHA256,
            authorizationPayloadSHA256: sha256Hex(authorizationPayloadData)
        )
    }

    private static func validateClosedWorldEnvelope(_ data: Data) throws {
        let root = try jsonObject(data, malformed: .malformedEnvelope)
        let allowed: Set<String> = [
            "schemaVersion",
            "externalBuildRecordBase64",
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
            "retainedIPASHA256",
        ]
        for key in root.keys.sorted() where !allowed.contains(key) {
            throw PassiveBluetoothCaptureFieldAuthorizationError
                .unexpectedAuthorizationPayloadField(key)
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
