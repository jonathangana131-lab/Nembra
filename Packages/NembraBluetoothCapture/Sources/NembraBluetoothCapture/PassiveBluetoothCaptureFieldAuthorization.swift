import CryptoKit
import Foundation

/// A field-authorization result minted only after one signed external GO envelope is verified against:
/// - Nembra's independent package-pinned authority;
/// - the exact canonical signed-installable evidence-record bytes;
/// - the exact schema-v3 external build-record bytes; and
/// - the exact build identity measured from the running application.
///
/// The retained signed-installable SHA-256 remains evidence carried by the canonical field record.
/// Possession of this value is software field-build authority only. It does not authenticate an
/// AOVOPRO ES80, prove RF completeness, establish protocol/telemetry semantics, or prove that the
/// physical procedure occurred.
public struct PassiveBluetoothCaptureVerifiedFieldAuthorization: Equatable, Sendable {
    public let externalBuildRecord: PassiveBluetoothCaptureExternalBuildRecord
    public let fieldBuildEvidenceRecord: PassiveBluetoothCaptureFieldBuildEvidenceRecord
    public let authorizationPayloadSHA256: String

    fileprivate init(
        externalBuildRecord: PassiveBluetoothCaptureExternalBuildRecord,
        fieldBuildEvidenceRecord: PassiveBluetoothCaptureFieldBuildEvidenceRecord,
        authorizationPayloadSHA256: String
    ) {
        self.externalBuildRecord = externalBuildRecord
        self.fieldBuildEvidenceRecord = fieldBuildEvidenceRecord
        self.authorizationPayloadSHA256 = authorizationPayloadSHA256
    }
}

public enum PassiveBluetoothCaptureFieldAuthorizationError: Error, Equatable, Sendable {
    case malformedEnvelope
    case unexpectedEnvelopeField(String)
    case duplicateEnvelopeField(String)
    case unsupportedEnvelopeSchemaVersion(Int)
    case invalidExternalBuildRecordBase64
    case invalidFieldBuildEvidenceRecordBase64
    case invalidAuthorizationPayloadBase64
    case invalidSignatureBase64
    case malformedAuthorizationPayload
    case unexpectedAuthorizationPayloadField(String)
    case duplicateAuthorizationPayloadField(String)
    case unsupportedAuthorizationPayloadSchemaVersion(Int)
    case unsupportedDecision(String)
    case invalidExternalBuildRecordSHA256
    case invalidFieldBuildEvidenceRecordSHA256
    case externalBuildRecordDigestMismatch
    case fieldBuildEvidenceRecordDigestMismatch
    case duplicateExternalBuildRecordField(String)
    case duplicateFieldBuildEvidenceRecordField(String)
    case invalidExternalBuildRecord
    case invalidFieldBuildEvidenceRecord
    case fieldBuildEvidenceMismatch
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
/// Envelope/payload schema v2 is intentionally incompatible with the earlier build-record-only v1
/// contract. The independent authority must sign the SHA-256 of both exact external records after
/// the retained signed IPA and its canonical evidence record have been independently accepted.
public enum PassiveBluetoothCaptureFieldAuthorizationVerifier {
    public static let envelopeSchemaVersion = 2
    public static let authorizationPayloadSchemaVersion = 2

    private struct EnvelopeWire: Decodable {
        let schemaVersion: Int
        let externalBuildRecordBase64: String
        let fieldBuildEvidenceRecordBase64: String
        let authorizationPayloadBase64: String
        let signatureDERBase64: String
    }

    private struct AuthorizationPayloadWire: Decodable {
        let schemaVersion: Int
        let decision: String
        let externalBuildRecordSHA256: String
        let fieldBuildEvidenceRecordSHA256: String
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
        guard let fieldBuildEvidenceRecordData = decodeCanonicalBase64(
            envelope.fieldBuildEvidenceRecordBase64
        ) else {
            throw PassiveBluetoothCaptureFieldAuthorizationError.invalidFieldBuildEvidenceRecordBase64
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
        guard isCanonicalSHA256(payload.fieldBuildEvidenceRecordSHA256) else {
            throw PassiveBluetoothCaptureFieldAuthorizationError.invalidFieldBuildEvidenceRecordSHA256
        }

        let exactExternalRecordSHA256 = sha256Hex(externalBuildRecordData)
        guard exactExternalRecordSHA256 == payload.externalBuildRecordSHA256 else {
            throw PassiveBluetoothCaptureFieldAuthorizationError.externalBuildRecordDigestMismatch
        }
        let exactFieldEvidenceSHA256 = sha256Hex(fieldBuildEvidenceRecordData)
        guard exactFieldEvidenceSHA256 == payload.fieldBuildEvidenceRecordSHA256 else {
            throw PassiveBluetoothCaptureFieldAuthorizationError.fieldBuildEvidenceRecordDigestMismatch
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

        if let duplicateKey = duplicateTopLevelObjectKey(in: externalBuildRecordData) {
            throw PassiveBluetoothCaptureFieldAuthorizationError
                .duplicateExternalBuildRecordField(duplicateKey)
        }
        if let duplicateKey = duplicateTopLevelObjectKey(in: fieldBuildEvidenceRecordData) {
            throw PassiveBluetoothCaptureFieldAuthorizationError
                .duplicateFieldBuildEvidenceRecordField(duplicateKey)
        }

        let externalBuildRecord: PassiveBluetoothCaptureExternalBuildRecord
        do {
            externalBuildRecord = try PassiveBluetoothCaptureExternalBuildRecordJSON
                .decodeDeclaration(externalBuildRecordData)
        } catch {
            throw PassiveBluetoothCaptureFieldAuthorizationError.invalidExternalBuildRecord
        }

        let fieldBuildEvidenceRecord: PassiveBluetoothCaptureFieldBuildEvidenceRecord
        do {
            fieldBuildEvidenceRecord = try PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON
                .decodeDeclaration(fieldBuildEvidenceRecordData)
        } catch {
            throw PassiveBluetoothCaptureFieldAuthorizationError.invalidFieldBuildEvidenceRecord
        }

        do {
            _ = try fieldBuildEvidenceRecord.makeSoftwareExportBuildReference(
                matching: externalBuildRecord
            )
        } catch {
            throw PassiveBluetoothCaptureFieldAuthorizationError.fieldBuildEvidenceMismatch
        }

        do {
            try externalBuildRecord.validateRuntimeBinding(to: runtimeBuildIdentity)
        } catch PassiveBluetoothCaptureExternalBuildRuntimeBindingError.infoPlistSHA256Mismatch {
            throw PassiveBluetoothCaptureFieldAuthorizationError.runtimeInfoPlistMismatch
        } catch {
            throw PassiveBluetoothCaptureFieldAuthorizationError.runtimeBuildMismatch
        }

        return PassiveBluetoothCaptureVerifiedFieldAuthorization(
            externalBuildRecord: externalBuildRecord,
            fieldBuildEvidenceRecord: fieldBuildEvidenceRecord,
            authorizationPayloadSHA256: sha256Hex(authorizationPayloadData)
        )
    }

    private static func validateClosedWorldEnvelope(_ data: Data) throws {
        if let duplicateKey = duplicateTopLevelObjectKey(in: data) {
            throw PassiveBluetoothCaptureFieldAuthorizationError.duplicateEnvelopeField(duplicateKey)
        }
        let root = try jsonObject(data, malformed: .malformedEnvelope)
        let allowed: Set<String> = [
            "schemaVersion",
            "externalBuildRecordBase64",
            "fieldBuildEvidenceRecordBase64",
            "authorizationPayloadBase64",
            "signatureDERBase64",
        ]
        for key in root.keys.sorted() where !allowed.contains(key) {
            throw PassiveBluetoothCaptureFieldAuthorizationError.unexpectedEnvelopeField(key)
        }
    }

    private static func validateClosedWorldAuthorizationPayload(_ data: Data) throws {
        if let duplicateKey = duplicateTopLevelObjectKey(in: data) {
            throw PassiveBluetoothCaptureFieldAuthorizationError
                .duplicateAuthorizationPayloadField(duplicateKey)
        }
        let root = try jsonObject(data, malformed: .malformedAuthorizationPayload)
        let allowed: Set<String> = [
            "schemaVersion",
            "decision",
            "externalBuildRecordSHA256",
            "fieldBuildEvidenceRecordSHA256",
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

    /// `JSONSerialization` and `JSONDecoder` collapse object members into keyed storage. At this
    /// signature boundary, accepting duplicate names would make authority depend on parser duplicate
    /// precedence. Scan exact UTF-8 bytes before keyed parsing and reject repeated semantic names,
    /// including names written with escape-equivalent JSON spelling.
    private static func duplicateTopLevelObjectKey(in data: Data) -> String? {
        let bytes = Array(data)
        var objectDepth = 0
        var seenKeys = Set<String>()
        var index = 0

        while index < bytes.count {
            switch bytes[index] {
            case 0x7B: // {
                objectDepth += 1
            case 0x7D: // }
                objectDepth -= 1
            case 0x22: // "
                let stringStart = index
                index += 1
                var isEscaped = false

                while index < bytes.count {
                    let byte = bytes[index]
                    if isEscaped {
                        isEscaped = false
                    } else if byte == 0x5C { // \
                        isEscaped = true
                    } else if byte == 0x22 {
                        break
                    }
                    index += 1
                }

                guard index < bytes.count else { return nil }
                let stringEnd = index

                if objectDepth == 1 {
                    var lookahead = index + 1
                    while lookahead < bytes.count, isJSONWhitespace(bytes[lookahead]) {
                        lookahead += 1
                    }
                    if lookahead < bytes.count, bytes[lookahead] == 0x3A { // :
                        let encodedKey = Data(bytes[stringStart...stringEnd])
                        if let key = try? JSONDecoder().decode(String.self, from: encodedKey),
                           !seenKeys.insert(key).inserted {
                            return key
                        }
                    }
                }
            default:
                break
            }
            index += 1
        }

        return nil
    }

    private static func isJSONWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
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
