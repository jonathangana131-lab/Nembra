import CryptoKit
import Foundation

/// Canonical cross-binding contract for the exact retained Capture install candidate.
///
/// This manifest is evidence, not physical authority. It lets the installer and later app
/// authorization attempt agree on the exact accepted IPA/build/evidence/device-binding inputs
/// without letting any one of those caller-controlled files mint a field-attempt capability.
///
/// Per-attempt authorization-envelope bytes are intentionally absent. The envelope binds a fresh,
/// app-generated process-local challenge and therefore cannot exist before this retained install
/// candidate is installed and the current application attempt begins.
public struct AuthenticatedStationaryCaptureInstallManifest: Equatable, Sendable {
    public let procedureID: String
    public let sourceCommitSHA: String
    public let bundleIdentifier: String
    public let buildIdentifier: String
    public let buildInstanceID: String
    public let retainedIPASHA256: String
    public let executableSHA256: String
    public let infoPlistSHA256: String
    public let tuyaDependencyLockSHA256: String
    public let externalBuildRecordSHA256: String
    public let signedBuildEvidenceSHA256: String
    public let finalGORecordSHA256: String
    public let intendedDevicePseudonymSHA256: String
    public let canonicalManifestSHA256: String

    fileprivate init(
        procedureID: String,
        sourceCommitSHA: String,
        bundleIdentifier: String,
        buildIdentifier: String,
        buildInstanceID: String,
        retainedIPASHA256: String,
        executableSHA256: String,
        infoPlistSHA256: String,
        tuyaDependencyLockSHA256: String,
        externalBuildRecordSHA256: String,
        signedBuildEvidenceSHA256: String,
        finalGORecordSHA256: String,
        intendedDevicePseudonymSHA256: String,
        canonicalManifestSHA256: String
    ) {
        self.procedureID = procedureID
        self.sourceCommitSHA = sourceCommitSHA
        self.bundleIdentifier = bundleIdentifier
        self.buildIdentifier = buildIdentifier
        self.buildInstanceID = buildInstanceID
        self.retainedIPASHA256 = retainedIPASHA256
        self.executableSHA256 = executableSHA256
        self.infoPlistSHA256 = infoPlistSHA256
        self.tuyaDependencyLockSHA256 = tuyaDependencyLockSHA256
        self.externalBuildRecordSHA256 = externalBuildRecordSHA256
        self.signedBuildEvidenceSHA256 = signedBuildEvidenceSHA256
        self.finalGORecordSHA256 = finalGORecordSHA256
        self.intendedDevicePseudonymSHA256 = intendedDevicePseudonymSHA256
        self.canonicalManifestSHA256 = canonicalManifestSHA256
    }

    /// Reconstructs only the stable external bindings consumed by the later signed authorization
    /// verifier. The fresh attempt challenge and its signed envelope are deliberately post-install.
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
    /// The retained IPA digest remains installer-side evidence and is intentionally not inferred
    /// from the running process.
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
    case unsupportedProcedure
    case invalidBundleIdentifier
    case invalidSourceCommitSHA
    case invalidBuildIdentifier
    case invalidBuildInstanceID
    case invalidDigestField(String)
}

/// Strict decoder for the workflow/install manifest. The accepted bytes intentionally match
/// `scripts/ci/es80_retained_install_manifest.py`: compact UTF-8 JSON, sorted keys, no trailing
/// newline, and no caller-authored authority field. Keeping one cross-language byte grammar
/// prevents the installer and running app from accepting different manifests.
public enum AuthenticatedStationaryCaptureInstallManifestVerifier {
    public static let schema = "nembra.es80-authenticated-stationary-install-manifest"
    public static let schemaVersion = 1
    public static let bundleIdentifier = "com.jonathangana131.nembra.capturelearn"
    public static let maximumManifestByteCount = 16_384

    private struct Wire: Codable {
        let schema: String
        let version: Int
        let procedureID: String
        let sourceCommitSHA: String
        let bundleIdentifier: String
        let buildIdentifier: String
        let buildInstanceID: String
        let retainedIPASHA256: String
        let executableSHA256: String
        let infoPlistSHA256: String
        let tuyaDependencyLockSHA256: String
        let externalBuildRecordSHA256: String
        let signedBuildEvidenceSHA256: String
        let finalGORecordSHA256: String
        let intendedDevicePseudonymSHA256: String
    }

    private static let allowedKeys: Set<String> = [
        "schema", "version", "procedureID", "sourceCommitSHA", "bundleIdentifier",
        "buildIdentifier", "buildInstanceID", "retainedIPASHA256", "executableSHA256",
        "infoPlistSHA256", "tuyaDependencyLockSHA256", "externalBuildRecordSHA256",
        "signedBuildEvidenceSHA256", "finalGORecordSHA256", "intendedDevicePseudonymSHA256",
    ]

    public static func decodeCanonical(
        _ data: Data
    ) throws -> AuthenticatedStationaryCaptureInstallManifest {
        guard !data.isEmpty, data.count <= maximumManifestByteCount else {
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

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard try encoder.encode(wire) == data else {
            throw AuthenticatedStationaryCaptureInstallManifestError.nonCanonicalManifest
        }
        guard wire.schema == schema, wire.version == schemaVersion else {
            throw AuthenticatedStationaryCaptureInstallManifestError.unsupportedSchema
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
        let expectedBuildIdentifier = "Capture Build V14-\(wire.sourceCommitSHA.prefix(12))"
        guard wire.buildIdentifier == expectedBuildIdentifier else {
            throw AuthenticatedStationaryCaptureInstallManifestError.invalidBuildIdentifier
        }
        guard PassiveBluetoothCaptureRuntimeBuildIdentityReader
            .normalizedBuildInstanceID(wire.buildInstanceID) == wire.buildInstanceID else {
            throw AuthenticatedStationaryCaptureInstallManifestError.invalidBuildInstanceID
        }

        let digestFields: [(String, String)] = [
            ("retainedIPASHA256", wire.retainedIPASHA256),
            ("executableSHA256", wire.executableSHA256),
            ("infoPlistSHA256", wire.infoPlistSHA256),
            ("tuyaDependencyLockSHA256", wire.tuyaDependencyLockSHA256),
            ("externalBuildRecordSHA256", wire.externalBuildRecordSHA256),
            ("signedBuildEvidenceSHA256", wire.signedBuildEvidenceSHA256),
            ("finalGORecordSHA256", wire.finalGORecordSHA256),
            ("intendedDevicePseudonymSHA256", wire.intendedDevicePseudonymSHA256),
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
            retainedIPASHA256: wire.retainedIPASHA256,
            executableSHA256: wire.executableSHA256,
            infoPlistSHA256: wire.infoPlistSHA256,
            tuyaDependencyLockSHA256: wire.tuyaDependencyLockSHA256,
            externalBuildRecordSHA256: wire.externalBuildRecordSHA256,
            signedBuildEvidenceSHA256: wire.signedBuildEvidenceSHA256,
            finalGORecordSHA256: wire.finalGORecordSHA256,
            intendedDevicePseudonymSHA256: wire.intendedDevicePseudonymSHA256,
            canonicalManifestSHA256: sha256Hex(data)
        )
    }

    private static func isCanonicalNonzeroSHA256(_ value: String) -> Bool {
        value != String(repeating: "0", count: 64)
            && value.utf8.count == 64
            && value.utf8.allSatisfy {
                (0x30 ... 0x39).contains($0) || (0x61 ... 0x66).contains($0)
            }
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
