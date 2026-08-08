import CryptoKit
import Foundation

/// A field-authorization result minted only after a signed external GO envelope is verified against
/// Nembra's independent package-pinned authority and the exact build identity measured from the
/// running application.
///
/// The independently signed decision also names the exact retained signed IPA and the exact
/// signed-artifact inspection evidence reviewed for that installable. Those external hashes remain
/// audit/authorization subjects; they are never reinterpreted as runtime telemetry or physical
/// scooter evidence.
///
/// This is software field-build authority only. It does not authenticate an AOVOPRO ES80, prove RF
/// completeness, establish protocol/telemetry semantics, prove the named IPA is installed, or prove
/// the physical procedure occurred.
public struct PassiveBluetoothCaptureVerifiedFieldAuthorization: Equatable, Sendable {
    public let externalBuildRecord: PassiveBluetoothCaptureExternalBuildRecord
    public let retainedIPASHA256: String
    public let signedArtifactInspectionSHA256: String
    public let authorizationPayloadSHA256: String

    fileprivate init(
        externalBuildRecord: PassiveBluetoothCaptureExternalBuildRecord,
        retainedIPASHA256: String,
        signedArtifactInspectionSHA256: String,
        authorizationPayloadSHA256: String
    ) {
        self.externalBuildRecord = externalBuildRecord
        self.retainedIPASHA256 = retainedIPASHA256
        self.signedArtifactInspectionSHA256 = signedArtifactInspectionSHA256
        self.authorizationPayloadSHA256 = authorizationPayloadSHA256
    }
}

public enum PassiveBluetoothCaptureFieldAuthorizationError: Error, Equatable, Sendable {
    case malformedEnvelope
    case duplicateEnvelopeField(String)
    case unexpectedEnvelopeField(String)
    case unsupportedEnvelopeSchemaVersion(Int)
    case invalidExternalBuildRecordBase64
    case invalidAuthorizationPayloadBase64
    case invalidSignatureBase64
    case malformedAuthorizationPayload
    case duplicateAuthorizationPayloadField(String)
    case unexpectedAuthorizationPayloadField(String)
    case unsupportedAuthorizationPayloadSchemaVersion(Int)
    case unsupportedDecision(String)
    case invalidExternalBuildRecordSHA256
    case invalidRetainedIPASHA256
    case invalidSignedArtifactInspectionSHA256
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
/// into the signed app.
///
/// Authorization schema v2 deliberately signs the three independent software subjects needed for
/// the field-build decision:
/// - the exact schema-v3 external build-record bytes;
/// - SHA-256 of the exact retained signed/installable IPA accepted outside the app;
/// - SHA-256 of the exact signed-artifact inspection evidence accepted outside the app.
///
/// The package separately proves that the signed schema-v3 record describes the executable and raw
/// Info.plist bytes that are actually running. No second package-side field-evidence schema is needed.
public enum PassiveBluetoothCaptureFieldAuthorizationVerifier {
    public static let envelopeSchemaVersion = 2
    public static let authorizationPayloadSchemaVersion = 2

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
        let retainedIPASHA256: String
        let signedArtifactInspectionSHA256: String
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
        guard isCanonicalSHA256(payload.retainedIPASHA256) else {
            throw PassiveBluetoothCaptureFieldAuthorizationError.invalidRetainedIPASHA256
        }
        guard isCanonicalSHA256(payload.signedArtifactInspectionSHA256) else {
            throw PassiveBluetoothCaptureFieldAuthorizationError.invalidSignedArtifactInspectionSHA256
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
            retainedIPASHA256: payload.retainedIPASHA256,
            signedArtifactInspectionSHA256: payload.signedArtifactInspectionSHA256,
            authorizationPayloadSHA256: sha256Hex(authorizationPayloadData)
        )
    }

    private static func validateClosedWorldEnvelope(_ data: Data) throws {
        do {
            try PassiveBluetoothCaptureStrictJSON.validateNoDuplicateObjectKeys(data)
        } catch PassiveBluetoothCaptureStrictJSONError.duplicateObjectKey(let key) {
            throw PassiveBluetoothCaptureFieldAuthorizationError.duplicateEnvelopeField(key)
        } catch {
            throw PassiveBluetoothCaptureFieldAuthorizationError.malformedEnvelope
        }

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
        do {
            try PassiveBluetoothCaptureStrictJSON.validateNoDuplicateObjectKeys(data)
        } catch PassiveBluetoothCaptureStrictJSONError.duplicateObjectKey(let key) {
            throw PassiveBluetoothCaptureFieldAuthorizationError.duplicateAuthorizationPayloadField(key)
        } catch {
            throw PassiveBluetoothCaptureFieldAuthorizationError.malformedAuthorizationPayload
        }

        let root = try jsonObject(data, malformed: .malformedAuthorizationPayload)
        let allowed: Set<String> = [
            "schemaVersion",
            "decision",
            "externalBuildRecordSHA256",
            "retainedIPASHA256",
            "signedArtifactInspectionSHA256",
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
