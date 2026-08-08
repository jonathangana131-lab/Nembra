import CryptoKit
import Foundation

/// Build identity read from the running Nembra application rather than rider/operator input.
///
/// The embedded build identifier and source commit are declarations produced by the accepted
/// build pipeline. `executableSHA256` is computed from the exact executable bytes visible to
/// the running application. Together they let a later trusted build record bind the runtime
/// bytes to the exact checkout that produced them without treating a typed Git SHA as proof.
public struct PassiveBluetoothCaptureRuntimeBuildIdentity: Equatable, Sendable {
    public let buildIdentifier: String
    public let sourceCommitSHA: String
    public let executableSHA256: String

    fileprivate init(
        buildIdentifier: String,
        sourceCommitSHA: String,
        executableSHA256: String
    ) {
        self.buildIdentifier = buildIdentifier
        self.sourceCommitSHA = sourceCommitSHA
        self.executableSHA256 = executableSHA256
    }
}

public enum PassiveBluetoothCaptureRuntimeBuildIdentityError: Error, Equatable, Sendable {
    case missingBuildIdentifier
    case invalidBuildIdentifier
    case missingSourceCommitSHA
    case invalidSourceCommitSHA
    case executableUnavailable
    case executableNotRegularFile
    case executableUnreadable
}

/// Fail-closed producer for the build identity of the application that is actually running.
///
/// Production callers intentionally receive no API that accepts arbitrary metadata or bytes.
/// The only public producer reads `Bundle.main` and hashes its executable. Tests use the
/// package-scoped resolver below to exercise validation deterministically.
public enum PassiveBluetoothCaptureRuntimeBuildIdentityReader {
    public static let buildIdentifierInfoDictionaryKey = "NembraCaptureBuildIdentifier"
    public static let sourceCommitSHAInfoDictionaryKey = "NembraCaptureBuildCommitSHA"

    /// Reads build identity from the running application's main bundle and hashes the exact
    /// executable bytes. Missing or malformed build metadata fails closed.
    public static func currentApplication() throws -> PassiveBluetoothCaptureRuntimeBuildIdentity {
        let bundle = Bundle.main

        guard let executableURL = bundle.executableURL else {
            throw PassiveBluetoothCaptureRuntimeBuildIdentityError.executableUnavailable
        }

        do {
            let resourceValues = try executableURL.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues.isRegularFile == true else {
                throw PassiveBluetoothCaptureRuntimeBuildIdentityError.executableNotRegularFile
            }
        } catch let error as PassiveBluetoothCaptureRuntimeBuildIdentityError {
            throw error
        } catch {
            throw PassiveBluetoothCaptureRuntimeBuildIdentityError.executableUnreadable
        }

        let executableData: Data
        do {
            executableData = try Data(contentsOf: executableURL, options: .mappedIfSafe)
        } catch {
            throw PassiveBluetoothCaptureRuntimeBuildIdentityError.executableUnreadable
        }

        return try resolveEmbeddedMetadata(
            infoDictionary: bundle.infoDictionary ?? [:],
            executableData: executableData
        )
    }

    package static func resolveEmbeddedMetadata(
        infoDictionary: [String: Any],
        executableData: Data
    ) throws -> PassiveBluetoothCaptureRuntimeBuildIdentity {
        guard let rawBuildIdentifier = infoDictionary[buildIdentifierInfoDictionaryKey] as? String else {
            throw PassiveBluetoothCaptureRuntimeBuildIdentityError.missingBuildIdentifier
        }
        guard isValidBuildIdentifier(rawBuildIdentifier) else {
            throw PassiveBluetoothCaptureRuntimeBuildIdentityError.invalidBuildIdentifier
        }

        guard let rawCommitSHA = infoDictionary[sourceCommitSHAInfoDictionaryKey] as? String else {
            throw PassiveBluetoothCaptureRuntimeBuildIdentityError.missingSourceCommitSHA
        }
        guard let normalizedCommitSHA = normalizedFullGitCommitSHA(rawCommitSHA) else {
            throw PassiveBluetoothCaptureRuntimeBuildIdentityError.invalidSourceCommitSHA
        }

        return PassiveBluetoothCaptureRuntimeBuildIdentity(
            buildIdentifier: rawBuildIdentifier,
            sourceCommitSHA: normalizedCommitSHA,
            executableSHA256: sha256Hex(executableData)
        )
    }

    package static func normalizedFullGitCommitSHA(_ rawValue: String) -> String? {
        let normalized = rawValue.lowercased()
        guard normalized.utf8.count == 40 else { return nil }
        guard normalized.utf8.allSatisfy({ byte in
            (48...57).contains(byte) || (97...102).contains(byte)
        }) else {
            return nil
        }
        return normalized
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

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
