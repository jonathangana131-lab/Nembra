import CryptoKit
import Foundation

/// A field-authorization result that can only be minted by the package verifier after all of the
/// following are true at once:
/// - an externally issued GO payload has a valid signature from the build-embedded authorization key;
/// - that signed payload binds the SHA-256 of the exact external build-record bytes;
/// - the external build record passes the existing closed-world V14/schema-v3 parser;
/// - the record's build tuple matches the application that is actually running; and
/// - the record's generated Info.plist digest matches the exact Info.plist bytes in that app bundle.
///
/// Possession of this value is software field-build authority only. It does not authenticate an
/// AOVOPRO ES80, prove RF completeness, establish protocol/telemetry semantics, or prove that the
/// physical procedure was actually performed.
public struct PassiveBluetoothCaptureVerifiedFieldAuthorization: Equatable, Sendable {
    public let externalBuildRecord: PassiveBluetoothCaptureExternalBuildRecord
    public let authorizationPayloadSHA256: String

    fileprivate init(
        externalBuildRecord: PassiveBluetoothCaptureExternalBuildRecord,
        authorizationPayloadSHA256: String
    ) {
        self.externalBuildRecord = externalBuildRecord
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
    case externalBuildRecordDigestMismatch
    case invalidExternalBuildRecord
    case missingAuthorizationPublicKey
    case invalidAuthorizationPublicKey
    case invalidSignature
    case runtimeBuildMismatch
    case runtimeInfoPlistUnreadable
    case runtimeInfoPlistMismatch
}

/// Verifies one post-build field-authorization envelope without creating the signed-build
/// self-reference that a bundled final-executable digest would cause.
///
/// The final field build embeds only a P-256 *public* authorization key before signing. After the
/// exact signed build is produced and independently accepted, an external authority may sign a GO
/// payload that binds the SHA-256 of the exact schema-v3 external build record. The private signing
/// key never belongs in the app or repository.
///
/// The envelope itself stays outside the signed bundle and can therefore be issued after the final
/// executable and Info.plist bytes are known. A signature over caller-selected metadata is not
/// enough: this verifier also requires exact equality with the running executable/build tuple and
/// exact runtime Info.plist bytes.
public enum PassiveBluetoothCaptureFieldAuthorizationVerifier {
    public static let envelopeSchemaVersion = 1
    public static let authorizationPayloadSchemaVersion = 1
    public static let authorizationPublicKeyInfoDictionaryKey =
        "NembraCaptureFieldAuthorizationPublicKeyX963Base64"

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
    }

    /// Verifies an external authorization against the exact application that is currently running.
    /// Missing/malformed build metadata, executable bytes, authorization-key metadata, Info.plist
    /// bytes, signature, record binding, or runtime equality all fail closed.
    public static func verifyForCurrentApplication(
        _ envelopeData: Data
    ) throws -> PassiveBluetoothCaptureVerifiedFieldAuthorization {
        guard let rawPublicKey = Bundle.main.infoDictionary?[
            authorizationPublicKeyInfoDictionaryKey
        ] as? String else {
            throw PassiveBluetoothCaptureFieldAuthorizationError.missingAuthorizationPublicKey
        }
        guard let publicKey = decodeCanonicalBase64(rawPublicKey) else {
            throw PassiveBluetoothCaptureFieldAuthorizationError.invalidAuthorizationPublicKey
        }

        let runtimeIdentity = try PassiveBluetoothCaptureRuntimeBuildIdentityReader.currentApplication()
        let infoPlistURL = Bundle.main.bundleURL.appendingPathComponent("Info.plist", isDirectory: false)
        let infoPlistData: Data
        do {
            infoPlistData = try Data(contentsOf: infoPlistURL, options: .mappedIfSafe)
        } catch {
            throw PassiveBluetoothCaptureFieldAuthorizationError.runtimeInfoPlistUnreadable
        }

        return try verify(
            envelopeData,
            publicKeyX963Representation: publicKey,
            runtimeBuildIdentity: runtimeIdentity,
            runtimeInfoPlistSHA256: sha256Hex(infoPlistData)
        )
    }

    /// Package-scoped deterministic seam for verifier tests. Production app code cannot supply a
    /// caller-selected runtime identity, Info.plist digest, or trust key to mint field authority.
    package static func verify(
        _ envelopeData: Data,
        publicKeyX963Representation: Data,
        runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity,
        runtimeInfoPlistSHA256: String
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
            throw PassiveBluetoothCaptureFieldAuthorizationError
                .unsupportedDecision(payload.decision)
        }
        guard isCanonicalSHA256(payload.externalBuildRecordSHA256) else {
            throw PassiveBluetoothCaptureFieldAuthorizationError.invalidExternalBuildRecordSHA256
        }

        let exactExternalRecordSHA256 = sha256Hex(externalBuildRecordData)
        guard exactExternalRecordSHA256 == payload.externalBuildRecordSHA256 else {
            throw PassiveBluetoothCaptureFieldAuthorizationError.externalBuildRecordDigestMismatch
        }

        let publicKey: P256.Signing.PublicKey
        do {
            publicKey = try P256.Signing.PublicKey(
                x963Representation: publicKeyX963Representation
            )
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
        guard isCanonicalSHA256(runtimeInfoPlistSHA256),
              externalBuildRecord.infoPlistSHA256 == runtimeInfoPlistSHA256 else {
            throw PassiveBluetoothCaptureFieldAuthorizationError.runtimeInfoPlistMismatch
        }

        return PassiveBluetoothCaptureVerifiedFieldAuthorization(
            externalBuildRecord: externalBuildRecord,
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
