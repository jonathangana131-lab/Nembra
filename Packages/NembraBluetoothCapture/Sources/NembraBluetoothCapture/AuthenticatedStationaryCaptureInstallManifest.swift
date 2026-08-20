import CryptoKit
import Foundation

/// Canonical cross-binding contract for the exact retained Capture install candidate.
///
/// This manifest is evidence, not physical authority. It lets the installer, app adapter, and
/// authorization envelope agree on the exact accepted IPA/build/evidence/device-binding inputs
/// without letting any one of those caller-controlled files mint a field-attempt capability.
public struct AuthenticatedStationaryCaptureInstallManifest: Equatable, Sendable {
    public let procedureID: String
    public let sourceCommitSHA: String
    public let bundleIdentifier: String
    public let buildIdentifier: String
    public let buildInstanceID: String
    public let signedInstallableSHA256: String
    public let executableSHA256: String
    public let infoPlistSHA256: String
    public let tuyaDependencyLockSHA256: String
    public let externalBuildRecordSHA256: String
    public let signedBuildEvidenceSHA256: String
    public let finalGORecordSHA256: String
    public let intendedDevicePseudonymSHA256: String
    public let authorizationEnvelopeSHA256: String
    public let canonicalManifestSHA256: String

    fileprivate init(
        procedureID: String,
        sourceCommitSHA: String,
        bundleIdentifier: String,
        buildIdentifier: String,
        buildInstanceID: String,
        signedInstallableSHA256: String,
        executableSHA256: String,
        infoPlistSHA256: String,
        tuyaDependencyLockSHA256: String,
        externalBuildRecordSHA256: String,
        signedBuildEvidenceSHA256: String,
        finalGORecordSHA256: String,
        intendedDevicePseudonymSHA256: String,
        authorizationEnvelopeSHA256: String,
        canonicalManifestSHA256: String
    ) {
        self.procedureID = procedureID
        self.sourceCommitSHA = sourceCommitSHA
        self.bundleIdentifier = bundleIdentifier
        self.buildIdentifier = buildIdentifier
        self.buildInstanceID = buildInstanceID
        self.signedInstallableSHA256 = signedInstallableSHA256
        self.executableSHA256 = executableSHA256
        self.infoPlistSHA256 = infoPlistSHA256
        self.tuyaDependencyLockSHA256 = tuyaDependencyLockSHA256
        self.externalBuildRecordSHA256 = externalBuildRecordSHA256
        self.signedBuildEvidenceSHA256 = signedBuildEvidenceSHA256
        self.finalGORecordSHA256 = finalGORecordSHA256
        self.intendedDevicePseudonymSHA256 = intendedDevicePseudonymSHA256
        self.authorizationEnvelopeSHA256 = authorizationEnvelopeSHA256
        self.canonicalManifestSHA256 = canonicalManifestSHA256
    }

    /// Reconstructs the exact external bindings consumed by the signed authorization verifier.
    /// The initializer can only be reached after manifest validation, so these digests are already
    /// canonical; the throwing boundary remains explicit instead of force-unwrapping evidence.
    public func externalBindings() throws -> AuthenticatedStationaryCaptureExternalBindings {
        try AuthenticatedStationaryCaptureExternalBindings(
            tuyaDependencyLockSHA256: tuyaDependencyLockSHA256,
            externalBuildRecordSHA256: externalBuildRecordSHA256,
            signedBuildEvidenceSHA256: signedBuildEvidenceSHA256,
            finalGORecordSHA256: finalGORecordSHA256,
            intendedDevicePseudonymSHA256: intendedDevicePseudonymSHA256
        )
    }

    /// Checks the manifest against the build identity measured from the running application.
    /// The retained IPA digest and authorization-envelope digest remain installer-side evidence;
    /// they are intentionally not inferred from the running process.
    public func matches(runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity) -> Bool {
        sourceCommitSHA == runtimeBuildIdentity.sourceCommitSHA
            && buildIdentifier == runtimeBuildIdentity.buildIdentifier
            && buildInstanceID == runtimeBuildIdentity.buildInstanceID
            && executableSHA256 == runtimeBuildIdentity.executableSHA256
            && infoPlistSHA256 == runtimeBuildIdentity.infoPlistSHA256
    }
}

public enum AuthenticatedStationaryCaptureInstallManifestError: Error, Equatable, Sendable {
    case inputByteLimitExceeded
    case malformedManifest
    case duplicateManifestField(String)
    case unexpectedManifestField(String)
    case nonCanonicalManifest
    case unsupportedSchema
    case unsupportedManifestKind
    case unsupportedProcedure
    case invalidBundleIdentifier
    case invalidSourceCommitSHA
    case invalidBuildIdentifier
    case invalidBuildInstanceID
    case invalidDigestField(String)
}

/// Strict decoder for the workflow/install manifest. The accepted bytes intentionally match
/// `scripts/ci/es80_retained_install_manifest.py`: UTF-8, sorted keys, two-space indentation,
/// Python-style `": "` separators, and one trailing newline. Keeping one cross-language byte
/// grammar prevents the installer and running app from accepting different manifests.
public enum AuthenticatedStationaryCaptureInstallManifestVerifier {
    public static let schema = "nembra.es80-authenticated-stationary-retained-install-manifest"
    public static let schemaVersion = 1
    public static let manifestKind = "retained-install-exact-subject-bindings-not-authorization"
    public static let bundleIdentifier = "com.jonathangana131.nembra.capturelearn"
    public static let maximumManifestByteCount = 32_768

    private struct Wire: Codable {
        let schema: String
        let version: Int
        let manifestKind: String
        let procedureID: String
        let bundleIdentifier: String
        let sourceCommitSHA: String
        let buildIdentifier: String
        let buildInstanceID: String
        let signedInstallableSHA256: String
        let executableSHA256: String
        let infoPlistSHA256: String
        let tuyaDependencyLockSHA256: String
        let externalBuildRecordSHA256: String
        let signedBuildEvidenceSHA256: String
        let finalGORecordSHA256: String
        let intendedDevicePseudonymSHA256: String
        let authorizationEnvelopeSHA256: String
    }

    private static let allowedKeys: Set<String> = [
        "schema", "version", "manifestKind", "procedureID", "sourceCommitSHA",
        "bundleIdentifier", "buildIdentifier", "buildInstanceID", "signedInstallableSHA256",
        "executableSHA256", "infoPlistSHA256", "tuyaDependencyLockSHA256",
        "externalBuildRecordSHA256", "signedBuildEvidenceSHA256", "finalGORecordSHA256",
        "intendedDevicePseudonymSHA256", "authorizationEnvelopeSHA256",
    ]

    public static func decodeCanonical(
        _ data: Data
    ) throws -> AuthenticatedStationaryCaptureInstallManifest {
        guard data.count <= maximumManifestByteCount else {
            throw AuthenticatedStationaryCaptureInstallManifestError.inputByteLimitExceeded
        }
        if let duplicate = PassiveBluetoothStrictJSON.duplicateTopLevelObjectKey(in: data) {
            throw AuthenticatedStationaryCaptureInstallManifestError
                .duplicateManifestField(duplicate)
        }

        let root: [String: Any]
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw AuthenticatedStationaryCaptureInstallManifestError.malformedManifest
            }
            root = object
        } catch let error as AuthenticatedStationaryCaptureInstallManifestError {
            throw error
        } catch {
            throw AuthenticatedStationaryCaptureInstallManifestError.malformedManifest
        }
        if let unexpected = root.keys.sorted().first(where: { !allowedKeys.contains($0) }) {
            throw AuthenticatedStationaryCaptureInstallManifestError
                .unexpectedManifestField(unexpected)
        }

        let wire: Wire
        do {
            wire = try JSONDecoder().decode(Wire.self, from: data)
        } catch {
            throw AuthenticatedStationaryCaptureInstallManifestError.malformedManifest
        }

        guard try canonicalManifestData(wire) == data else {
            throw AuthenticatedStationaryCaptureInstallManifestError.nonCanonicalManifest
        }
        guard wire.schema == schema, wire.version == schemaVersion else {
            throw AuthenticatedStationaryCaptureInstallManifestError.unsupportedSchema
        }
        guard wire.manifestKind == manifestKind else {
            throw AuthenticatedStationaryCaptureInstallManifestError.unsupportedManifestKind
        }
        guard wire.procedureID == AuthenticatedStationaryCaptureFieldAuthorizationVerifier.procedureID else {
            throw AuthenticatedStationaryCaptureInstallManifestError.unsupportedProcedure
        }
        guard wire.bundleIdentifier == bundleIdentifier else {
            throw AuthenticatedStationaryCaptureInstallManifestError.invalidBundleIdentifier
        }
        guard PassiveBluetoothCaptureRuntimeBuildIdentityReader
            .normalizedFullGitCommitSHA(wire.sourceCommitSHA) == wire.sourceCommitSHA,
              wire.sourceCommitSHA != String(repeating: "0", count: 40) else {
            throw AuthenticatedStationaryCaptureInstallManifestError.invalidSourceCommitSHA
        }
        guard isValidBuildIdentifier(wire.buildIdentifier) else {
            throw AuthenticatedStationaryCaptureInstallManifestError.invalidBuildIdentifier
        }
        guard isCanonicalUUIDv4(wire.buildInstanceID) else {
            throw AuthenticatedStationaryCaptureInstallManifestError.invalidBuildInstanceID
        }

        let digestFields: [(String, String)] = [
            ("signedInstallableSHA256", wire.signedInstallableSHA256),
            ("executableSHA256", wire.executableSHA256),
            ("infoPlistSHA256", wire.infoPlistSHA256),
            ("tuyaDependencyLockSHA256", wire.tuyaDependencyLockSHA256),
            ("externalBuildRecordSHA256", wire.externalBuildRecordSHA256),
            ("signedBuildEvidenceSHA256", wire.signedBuildEvidenceSHA256),
            ("finalGORecordSHA256", wire.finalGORecordSHA256),
            ("intendedDevicePseudonymSHA256", wire.intendedDevicePseudonymSHA256),
            ("authorizationEnvelopeSHA256", wire.authorizationEnvelopeSHA256),
        ]
        if let invalid = digestFields.first(where: { !isCanonicalNonzeroSHA256($0.1) }) {
            throw AuthenticatedStationaryCaptureInstallManifestError.invalidDigestField(invalid.0)
        }

        return AuthenticatedStationaryCaptureInstallManifest(
            procedureID: wire.procedureID,
            sourceCommitSHA: wire.sourceCommitSHA,
            bundleIdentifier: wire.bundleIdentifier,
            buildIdentifier: wire.buildIdentifier,
            buildInstanceID: wire.buildInstanceID,
            signedInstallableSHA256: wire.signedInstallableSHA256,
            executableSHA256: wire.executableSHA256,
            infoPlistSHA256: wire.infoPlistSHA256,
            tuyaDependencyLockSHA256: wire.tuyaDependencyLockSHA256,
            externalBuildRecordSHA256: wire.externalBuildRecordSHA256,
            signedBuildEvidenceSHA256: wire.signedBuildEvidenceSHA256,
            finalGORecordSHA256: wire.finalGORecordSHA256,
            intendedDevicePseudonymSHA256: wire.intendedDevicePseudonymSHA256,
            authorizationEnvelopeSHA256: wire.authorizationEnvelopeSHA256,
            canonicalManifestSHA256: sha256Hex(data)
        )
    }

    private static func canonicalManifestData(_ wire: Wire) throws -> Data {
        let fields: [(String, String)] = [
            ("schema", try encodedJSONString(wire.schema)),
            ("version", String(wire.version)),
            ("manifestKind", try encodedJSONString(wire.manifestKind)),
            ("procedureID", try encodedJSONString(wire.procedureID)),
            ("bundleIdentifier", try encodedJSONString(wire.bundleIdentifier)),
            ("sourceCommitSHA", try encodedJSONString(wire.sourceCommitSHA)),
            ("buildIdentifier", try encodedJSONString(wire.buildIdentifier)),
            ("buildInstanceID", try encodedJSONString(wire.buildInstanceID)),
            ("signedInstallableSHA256", try encodedJSONString(wire.signedInstallableSHA256)),
            ("executableSHA256", try encodedJSONString(wire.executableSHA256)),
            ("infoPlistSHA256", try encodedJSONString(wire.infoPlistSHA256)),
            ("tuyaDependencyLockSHA256", try encodedJSONString(wire.tuyaDependencyLockSHA256)),
            ("externalBuildRecordSHA256", try encodedJSONString(wire.externalBuildRecordSHA256)),
            ("signedBuildEvidenceSHA256", try encodedJSONString(wire.signedBuildEvidenceSHA256)),
            ("finalGORecordSHA256", try encodedJSONString(wire.finalGORecordSHA256)),
            ("intendedDevicePseudonymSHA256", try encodedJSONString(wire.intendedDevicePseudonymSHA256)),
            ("authorizationEnvelopeSHA256", try encodedJSONString(wire.authorizationEnvelopeSHA256)),
        ].sorted { $0.0 < $1.0 }

        var lines = ["{"]
        for (index, field) in fields.enumerated() {
            let comma = index == fields.count - 1 ? "" : ","
            lines.append("  \(try encodedJSONString(field.0)): \(field.1)\(comma)")
        }
        lines.append("}")
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    private static func encodedJSONString(_ value: String) throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: [value],
            options: [.withoutEscapingSlashes]
        )
        guard let array = String(data: data, encoding: .utf8),
              array.first == "[", array.last == "]" else {
            throw AuthenticatedStationaryCaptureInstallManifestError.malformedManifest
        }
        return String(array.dropFirst().dropLast())
    }

    private static func isCanonicalNonzeroSHA256(_ value: String) -> Bool {
        value != String(repeating: "0", count: 64)
            && value.utf8.count == 64
            && value.utf8.allSatisfy {
                (0x30 ... 0x39).contains($0) || (0x61 ... 0x66).contains($0)
            }
    }

    private static func isCanonicalUUIDv4(_ value: String) -> Bool {
        guard PassiveBluetoothCaptureRuntimeBuildIdentityReader
            .normalizedBuildInstanceID(value) == value else { return false }
        let bytes = Array(value.utf8)
        guard bytes[14] == 0x34 else { return false }
        return [0x38, 0x39, 0x61, 0x62].contains(bytes[19])
    }

    private static func isValidBuildIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 128,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return !value.unicodeScalars.contains { scalar in
            CharacterSet.controlCharacters.contains(scalar)
        }
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
