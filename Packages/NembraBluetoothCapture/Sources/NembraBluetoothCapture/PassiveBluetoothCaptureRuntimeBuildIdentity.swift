import CryptoKit
import Foundation

/// Build identity read from the running Nembra application rather than rider/operator input.
///
/// The embedded build identifier, build-instance identifier, and source commit are declarations
/// produced by the accepted build pipeline. `executableSHA256` and `infoPlistSHA256` are computed
/// from the exact executable and raw `Info.plist` bytes visible to the running application. The
/// build-instance identifier is an opaque per-produced-build rendezvous key: it lets an independently
/// attested external build record identify this exact build without embedding final artifact digests
/// back into the signed app bundle and creating a code-signing self-reference.
public struct PassiveBluetoothCaptureRuntimeBuildIdentity: Equatable, Sendable {
    public let buildIdentifier: String
    public let buildInstanceID: String
    public let sourceCommitSHA: String
    public let executableSHA256: String
    public let infoPlistSHA256: String

    fileprivate init(
        buildIdentifier: String,
        buildInstanceID: String,
        sourceCommitSHA: String,
        executableSHA256: String,
        infoPlistSHA256: String
    ) {
        self.buildIdentifier = buildIdentifier
        self.buildInstanceID = buildInstanceID
        self.sourceCommitSHA = sourceCommitSHA
        self.executableSHA256 = executableSHA256
        self.infoPlistSHA256 = infoPlistSHA256
    }
}

public enum PassiveBluetoothCaptureRuntimeBuildIdentityError: Error, Equatable, Sendable {
    case missingBuildIdentifier
    case invalidBuildIdentifier
    case missingBuildInstanceID
    case invalidBuildInstanceID
    case missingSourceCommitSHA
    case invalidSourceCommitSHA
    case executableUnavailable
    case executableNotRegularFile
    case executableUnreadable
    case infoPlistUnavailable
    case infoPlistNotRegularFile
    case infoPlistUnreadable
}

/// Fail-closed producer for the build identity of the application that is actually running.
///
/// Production callers intentionally receive no API that accepts arbitrary metadata or bytes.
/// The only public producer reads `Bundle.main` and hashes its executable plus raw `Info.plist`.
/// Tests use the package-scoped resolver below to exercise validation deterministically.
public enum PassiveBluetoothCaptureRuntimeBuildIdentityReader {
    public static let buildIdentifierInfoDictionaryKey = "NembraCaptureBuildIdentifier"
    public static let buildInstanceIDInfoDictionaryKey = "NembraCaptureBuildInstanceID"
    public static let sourceCommitSHAInfoDictionaryKey = "NembraCaptureBuildCommitSHA"

    /// Reads build identity from the running application's main bundle and hashes the exact
    /// executable plus raw root `Info.plist` bytes. Missing or malformed build metadata fails closed.
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

        let infoPlistURL = bundle.bundleURL.appendingPathComponent("Info.plist", isDirectory: false)
        guard FileManager.default.fileExists(atPath: infoPlistURL.path) else {
            throw PassiveBluetoothCaptureRuntimeBuildIdentityError.infoPlistUnavailable
        }

        do {
            let resourceValues = try infoPlistURL.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues.isRegularFile == true else {
                throw PassiveBluetoothCaptureRuntimeBuildIdentityError.infoPlistNotRegularFile
            }
        } catch let error as PassiveBluetoothCaptureRuntimeBuildIdentityError {
            throw error
        } catch {
            throw PassiveBluetoothCaptureRuntimeBuildIdentityError.infoPlistUnreadable
        }

        let infoPlistData: Data
        do {
            infoPlistData = try Data(contentsOf: infoPlistURL, options: .mappedIfSafe)
        } catch {
            throw PassiveBluetoothCaptureRuntimeBuildIdentityError.infoPlistUnreadable
        }

        return try resolveEmbeddedMetadata(
            infoDictionary: bundle.infoDictionary ?? [:],
            executableData: executableData,
            infoPlistData: infoPlistData
        )
    }

    package static func resolveEmbeddedMetadata(
        infoDictionary: [String: Any],
        executableData: Data,
        infoPlistData: Data
    ) throws -> PassiveBluetoothCaptureRuntimeBuildIdentity {
        guard let rawBuildIdentifier = infoDictionary[buildIdentifierInfoDictionaryKey] as? String else {
            throw PassiveBluetoothCaptureRuntimeBuildIdentityError.missingBuildIdentifier
        }
        guard isValidBuildIdentifier(rawBuildIdentifier) else {
            throw PassiveBluetoothCaptureRuntimeBuildIdentityError.invalidBuildIdentifier
        }

        guard let rawBuildInstanceID = infoDictionary[buildInstanceIDInfoDictionaryKey] as? String else {
            throw PassiveBluetoothCaptureRuntimeBuildIdentityError.missingBuildInstanceID
        }
        guard let normalizedBuildInstanceID = normalizedBuildInstanceID(rawBuildInstanceID) else {
            throw PassiveBluetoothCaptureRuntimeBuildIdentityError.invalidBuildInstanceID
        }

        guard let rawCommitSHA = infoDictionary[sourceCommitSHAInfoDictionaryKey] as? String else {
            throw PassiveBluetoothCaptureRuntimeBuildIdentityError.missingSourceCommitSHA
        }
        guard let normalizedCommitSHA = normalizedFullGitCommitSHA(rawCommitSHA) else {
            throw PassiveBluetoothCaptureRuntimeBuildIdentityError.invalidSourceCommitSHA
        }

        return PassiveBluetoothCaptureRuntimeBuildIdentity(
            buildIdentifier: rawBuildIdentifier,
            buildInstanceID: normalizedBuildInstanceID,
            sourceCommitSHA: normalizedCommitSHA,
            executableSHA256: sha256Hex(executableData),
            infoPlistSHA256: sha256Hex(infoPlistData)
        )
    }

    package static func normalizedBuildInstanceID(_ rawValue: String) -> String? {
        let normalized = rawValue.lowercased()
        guard normalized.utf8.count == 36 else { return nil }

        let bytes = Array(normalized.utf8)
        let hyphenOffsets: Set<Int> = [8, 13, 18, 23]
        for (offset, byte) in bytes.enumerated() {
            if hyphenOffsets.contains(offset) {
                guard byte == 45 else { return nil }
            } else {
                guard (48...57).contains(byte) || (97...102).contains(byte) else { return nil }
            }
        }
        return normalized
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
