import CryptoKit
import Foundation

/// Exact non-authorizing subject evidence emitted by `es80_signed_field_artifact_evidence.py`.
///
/// This evidence proves only that a retained signed IPA/build tuple was assembled against the
/// accepted dependency/final-GO/device-pseudonym subjects. It never authorizes OFF1, Bluetooth,
/// Tuya ownership, or physical evidence. Physical authority still requires the independently
/// signed per-attempt authorization envelope verified by the package-pinned production key.
public struct AuthenticatedStationaryCaptureSignedBuildEvidence: Equatable, Sendable {
    public let procedureID: String
    public let bundleIdentifier: String
    public let sourceCommitSHA: String
    public let buildIdentifier: String
    public let buildInstanceID: String
    public let signedInstallableSHA256: String
    public let executableSHA256: String
    public let infoPlistSHA256: String
    public let tuyaDependencyLockSHA256: String
    public let externalBuildRecordSHA256: String
    public let finalGORecordSHA256: String
    public let intendedDevicePseudonymSHA256: String
    public let canonicalEvidenceSHA256: String

    fileprivate init(
        procedureID: String,
        bundleIdentifier: String,
        sourceCommitSHA: String,
        buildIdentifier: String,
        buildInstanceID: String,
        signedInstallableSHA256: String,
        executableSHA256: String,
        infoPlistSHA256: String,
        tuyaDependencyLockSHA256: String,
        externalBuildRecordSHA256: String,
        finalGORecordSHA256: String,
        intendedDevicePseudonymSHA256: String,
        canonicalEvidenceSHA256: String
    ) {
        self.procedureID = procedureID
        self.bundleIdentifier = bundleIdentifier
        self.sourceCommitSHA = sourceCommitSHA
        self.buildIdentifier = buildIdentifier
        self.buildInstanceID = buildInstanceID
        self.signedInstallableSHA256 = signedInstallableSHA256
        self.executableSHA256 = executableSHA256
        self.infoPlistSHA256 = infoPlistSHA256
        self.tuyaDependencyLockSHA256 = tuyaDependencyLockSHA256
        self.externalBuildRecordSHA256 = externalBuildRecordSHA256
        self.finalGORecordSHA256 = finalGORecordSHA256
        self.intendedDevicePseudonymSHA256 = intendedDevicePseudonymSHA256
        self.canonicalEvidenceSHA256 = canonicalEvidenceSHA256
    }

    public func externalBindings() throws -> AuthenticatedStationaryCaptureExternalBindings {
        try AuthenticatedStationaryCaptureExternalBindings(
            tuyaDependencyLockSHA256: tuyaDependencyLockSHA256,
            externalBuildRecordSHA256: externalBuildRecordSHA256,
            signedBuildEvidenceSHA256: canonicalEvidenceSHA256,
            finalGORecordSHA256: finalGORecordSHA256,
            intendedDevicePseudonymSHA256: intendedDevicePseudonymSHA256
        )
    }

    /// Matches only facts measured from the running process. The retained IPA digest and external
    /// evidence digests remain external evidence and are deliberately not inferred from runtime.
    public func matches(
        runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity,
        bundleIdentifier runtimeBundleIdentifier: String
    ) -> Bool {
        bundleIdentifier == runtimeBundleIdentifier
            && sourceCommitSHA == runtimeBuildIdentity.sourceCommitSHA
            && buildIdentifier == runtimeBuildIdentity.buildIdentifier
            && buildInstanceID == runtimeBuildIdentity.buildInstanceID
            && executableSHA256 == runtimeBuildIdentity.executableSHA256
            && infoPlistSHA256 == runtimeBuildIdentity.infoPlistSHA256
    }
}

public enum AuthenticatedStationaryCaptureSignedBuildEvidenceError: Error, Equatable, Sendable {
    case inputByteLimitExceeded
    case malformedEvidence
    case duplicateEvidenceField(String)
    case unexpectedEvidenceField(String)
    case nonCanonicalEvidence
    case unsupportedSchema
    case unsupportedEvidenceKind
    case unsupportedProcedure
    case unsupportedBundleIdentifier
    case unsupportedSignedInstallableKind
    case invalidSourceCommitSHA
    case invalidBuildIdentifier
    case invalidBuildInstanceID
    case invalidDigestField(String)
}

/// Strict Swift mirror of the repository's signed-artifact evidence verifier.
///
/// The producer uses Python `json.dumps(..., indent=2, sort_keys=True) + "\n"`. The decoder
/// reconstructs that exact bounded ASCII wire shape instead of accepting merely equivalent JSON,
/// so the SHA-256 used by the later signed authorization envelope has one byte identity.
public enum AuthenticatedStationaryCaptureSignedBuildEvidenceVerifier {
    public static let schemaVersion = 1
    public static let evidenceKind = "signed-field-artifact-digests-not-authorization"
    public static let expectedBundleIdentifier = "com.jonathangana131.nembra.capturelearn"
    public static let signedInstallableKind = "ipa"
    public static let maximumEvidenceByteCount = 1_048_576

    private struct Wire: Codable {
        let schemaVersion: Int
        let evidenceKind: String
        let procedureID: String
        let bundleIdentifier: String
        let sourceCommitSHA: String
        let buildIdentifier: String
        let buildInstanceID: String
        let signedInstallableKind: String
        let signedInstallableSHA256: String
        let executableSHA256: String
        let infoPlistSHA256: String
        let tuyaDependencyLockSHA256: String
        let externalBuildRecordSHA256: String
        let finalGORecordSHA256: String
        let intendedDevicePseudonymSHA256: String
    }

    private static let allowedKeys: Set<String> = [
        "schemaVersion", "evidenceKind", "procedureID", "bundleIdentifier", "sourceCommitSHA",
        "buildIdentifier", "buildInstanceID", "signedInstallableKind", "signedInstallableSHA256",
        "executableSHA256", "infoPlistSHA256", "tuyaDependencyLockSHA256",
        "externalBuildRecordSHA256", "finalGORecordSHA256", "intendedDevicePseudonymSHA256",
    ]

    public static func decodeCanonical(
        _ data: Data
    ) throws -> AuthenticatedStationaryCaptureSignedBuildEvidence {
        guard !data.isEmpty, data.count <= maximumEvidenceByteCount else {
            throw AuthenticatedStationaryCaptureSignedBuildEvidenceError.inputByteLimitExceeded
        }
        if let duplicate = PassiveBluetoothStrictJSON.duplicateTopLevelObjectKey(in: data) {
            throw AuthenticatedStationaryCaptureSignedBuildEvidenceError
                .duplicateEvidenceField(duplicate)
        }

        let root: [String: Any]
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw AuthenticatedStationaryCaptureSignedBuildEvidenceError.malformedEvidence
            }
            root = object
        } catch let error as AuthenticatedStationaryCaptureSignedBuildEvidenceError {
            throw error
        } catch {
            throw AuthenticatedStationaryCaptureSignedBuildEvidenceError.malformedEvidence
        }
        guard Set(root.keys) == allowedKeys else {
            if let unexpected = root.keys.sorted().first(where: { !allowedKeys.contains($0) }) {
                throw AuthenticatedStationaryCaptureSignedBuildEvidenceError
                    .unexpectedEvidenceField(unexpected)
            }
            throw AuthenticatedStationaryCaptureSignedBuildEvidenceError.malformedEvidence
        }

        let wire: Wire
        do {
            wire = try JSONDecoder().decode(Wire.self, from: data)
        } catch {
            throw AuthenticatedStationaryCaptureSignedBuildEvidenceError.malformedEvidence
        }

        guard isValidBuildIdentifier(wire.buildIdentifier) else {
            throw AuthenticatedStationaryCaptureSignedBuildEvidenceError.invalidBuildIdentifier
        }
        guard try canonicalBytes(for: wire) == data else {
            throw AuthenticatedStationaryCaptureSignedBuildEvidenceError.nonCanonicalEvidence
        }
        guard wire.schemaVersion == schemaVersion else {
            throw AuthenticatedStationaryCaptureSignedBuildEvidenceError.unsupportedSchema
        }
        guard wire.evidenceKind == evidenceKind else {
            throw AuthenticatedStationaryCaptureSignedBuildEvidenceError.unsupportedEvidenceKind
        }
        guard wire.procedureID == AuthenticatedStationaryCaptureFieldAuthorizationVerifier.procedureID else {
            throw AuthenticatedStationaryCaptureSignedBuildEvidenceError.unsupportedProcedure
        }
        guard wire.bundleIdentifier == expectedBundleIdentifier else {
            throw AuthenticatedStationaryCaptureSignedBuildEvidenceError.unsupportedBundleIdentifier
        }
        guard wire.signedInstallableKind == signedInstallableKind else {
            throw AuthenticatedStationaryCaptureSignedBuildEvidenceError.unsupportedSignedInstallableKind
        }
        guard isCanonicalSHA40(wire.sourceCommitSHA) else {
            throw AuthenticatedStationaryCaptureSignedBuildEvidenceError.invalidSourceCommitSHA
        }
        guard isCanonicalUUIDv4(wire.buildInstanceID) else {
            throw AuthenticatedStationaryCaptureSignedBuildEvidenceError.invalidBuildInstanceID
        }

        let digestFields: [(String, String)] = [
            ("signedInstallableSHA256", wire.signedInstallableSHA256),
            ("executableSHA256", wire.executableSHA256),
            ("infoPlistSHA256", wire.infoPlistSHA256),
            ("tuyaDependencyLockSHA256", wire.tuyaDependencyLockSHA256),
            ("externalBuildRecordSHA256", wire.externalBuildRecordSHA256),
            ("finalGORecordSHA256", wire.finalGORecordSHA256),
            ("intendedDevicePseudonymSHA256", wire.intendedDevicePseudonymSHA256),
        ]
        if let invalid = digestFields.first(where: { !isCanonicalNonzeroSHA256($0.1) }) {
            throw AuthenticatedStationaryCaptureSignedBuildEvidenceError.invalidDigestField(invalid.0)
        }

        return AuthenticatedStationaryCaptureSignedBuildEvidence(
            procedureID: wire.procedureID,
            bundleIdentifier: wire.bundleIdentifier,
            sourceCommitSHA: wire.sourceCommitSHA,
            buildIdentifier: wire.buildIdentifier,
            buildInstanceID: wire.buildInstanceID,
            signedInstallableSHA256: wire.signedInstallableSHA256,
            executableSHA256: wire.executableSHA256,
            infoPlistSHA256: wire.infoPlistSHA256,
            tuyaDependencyLockSHA256: wire.tuyaDependencyLockSHA256,
            externalBuildRecordSHA256: wire.externalBuildRecordSHA256,
            finalGORecordSHA256: wire.finalGORecordSHA256,
            intendedDevicePseudonymSHA256: wire.intendedDevicePseudonymSHA256,
            canonicalEvidenceSHA256: sha256Hex(data)
        )
    }

    private static func canonicalBytes(for wire: Wire) throws -> Data {
        let values: [(String, String)] = [
            ("buildIdentifier", try jsonString(wire.buildIdentifier)),
            ("buildInstanceID", try jsonString(wire.buildInstanceID)),
            ("bundleIdentifier", try jsonString(wire.bundleIdentifier)),
            ("evidenceKind", try jsonString(wire.evidenceKind)),
            ("executableSHA256", try jsonString(wire.executableSHA256)),
            ("externalBuildRecordSHA256", try jsonString(wire.externalBuildRecordSHA256)),
            ("finalGORecordSHA256", try jsonString(wire.finalGORecordSHA256)),
            ("infoPlistSHA256", try jsonString(wire.infoPlistSHA256)),
            ("intendedDevicePseudonymSHA256", try jsonString(wire.intendedDevicePseudonymSHA256)),
            ("procedureID", try jsonString(wire.procedureID)),
            ("schemaVersion", String(wire.schemaVersion)),
            ("signedInstallableKind", try jsonString(wire.signedInstallableKind)),
            ("signedInstallableSHA256", try jsonString(wire.signedInstallableSHA256)),
            ("sourceCommitSHA", try jsonString(wire.sourceCommitSHA)),
            ("tuyaDependencyLockSHA256", try jsonString(wire.tuyaDependencyLockSHA256)),
        ]
        let lines = values.enumerated().map { index, pair in
            "  \(try! jsonString(pair.0)): \(pair.1)\(index + 1 == values.count ? "" : ",")"
        }
        return Data(("{\n" + lines.joined(separator: "\n") + "\n}\n").utf8)
    }

    private static func jsonString(_ value: String) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private static func isCanonicalSHA40(_ value: String) -> Bool {
        value.utf8.count == 40 && value.utf8.allSatisfy(isLowerHex)
    }

    private static func isCanonicalNonzeroSHA256(_ value: String) -> Bool {
        value.utf8.count == 64
            && value.utf8.allSatisfy(isLowerHex)
            && value != String(repeating: "0", count: 64)
    }

    private static func isLowerHex(_ byte: UInt8) -> Bool {
        (0x30 ... 0x39).contains(byte) || (0x61 ... 0x66).contains(byte)
    }

    private static func isCanonicalUUIDv4(_ value: String) -> Bool {
        guard value.utf8.count == 36 else { return false }
        let bytes = Array(value.utf8)
        let hyphenOffsets: Set<Int> = [8, 13, 18, 23]
        for (index, byte) in bytes.enumerated() {
            if hyphenOffsets.contains(index) {
                guard byte == 0x2D else { return false }
            } else {
                guard isLowerHex(byte) else { return false }
            }
        }
        guard bytes[14] == 0x34 else { return false }
        return [UInt8(ascii: "8"), UInt8(ascii: "9"), UInt8(ascii: "a"), UInt8(ascii: "b")]
            .contains(bytes[19])
    }

    private static func isValidBuildIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty,
              value.utf8.count <= 128,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        // Current Capture build identifiers are repository-generated ASCII. Rejecting a broader
        // producer-valid Unicode spelling is conservative and keeps the exact canonical mirror
        // deterministic without widening the accepted physical-build surface.
        return value.utf8.allSatisfy { (0x20 ... 0x7E).contains($0) }
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
