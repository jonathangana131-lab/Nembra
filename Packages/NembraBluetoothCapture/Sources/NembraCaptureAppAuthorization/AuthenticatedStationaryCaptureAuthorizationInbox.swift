import Foundation
import NembraBluetoothCapture

public enum AuthenticatedStationaryCaptureAuthorizationInboxError: Error, Equatable, Sendable {
    case applicationSupportUnavailable
    case missingSubject(String)
    case symbolicLinkRejected(String)
    case nonRegularFile(String)
    case byteLimitExceeded(String)
    case subjectChangedDuringRead(String)
    case readFailed(String)
}

/// Non-authorizing app-container handoff for the retained install manifest and the later signed
/// authorization envelope.
///
/// The field Mac may copy these files into the app data container. File presence never grants
/// physical authority: manifest bytes still pass the canonical runtime cross-binding verifier and
/// envelope bytes still pass the independently pinned signature/current-attempt/replay verifier.
/// This inbox only provides bounded, one-shot custody for those bytes.
public struct AuthenticatedStationaryCaptureAuthorizationInbox: Sendable {
    public static let directoryName = "NembraCapture/FieldAuthorization"
    public static let installManifestFilename = "retained-install-manifest.json"
    public static let authorizationEnvelopeFilename = "authorization-envelope.json"

    private let directoryURL: URL

    public init() throws {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.applicationSupportUnavailable
        }
        directoryURL = applicationSupport.appendingPathComponent(
            Self.directoryName,
            isDirectory: true
        )
    }

    package init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    /// Takes the stable retained-install manifest. The returned bytes are still non-authorizing and
    /// must be passed to `AuthenticatedStationaryCaptureAppSession.prepare(installManifestData:)`.
    public func takeInstallManifest() throws -> Data {
        try take(
            filename: Self.installManifestFilename,
            maximumByteCount: AuthenticatedStationaryCaptureInstallManifestVerifier
                .maximumManifestByteCount
        )
    }

    /// Takes the post-install signer response. The returned bytes are still non-authorizing and
    /// must be passed to `AuthenticatedStationaryCaptureAppSession.acceptEnvelope(_:)`.
    public func takeAuthorizationEnvelope() throws -> Data {
        try take(
            filename: Self.authorizationEnvelopeFilename,
            maximumByteCount: AuthenticatedStationaryCaptureFieldAuthorizationVerifier
                .maximumEnvelopeByteCount
        )
    }

    private func take(filename: String, maximumByteCount: Int) throws -> Data {
        let fileURL = directoryURL.appendingPathComponent(filename, isDirectory: false)
        let keys: Set<URLResourceKey> = [
            .isSymbolicLinkKey,
            .isRegularFileKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .fileResourceIdentifierKey,
        ]

        let before: URLResourceValues
        do {
            before = try fileURL.resourceValues(forKeys: keys)
        } catch {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.missingSubject(filename)
        }
        guard before.isSymbolicLink != true else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.symbolicLinkRejected(filename)
        }
        guard before.isRegularFile == true else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.nonRegularFile(filename)
        }
        guard let expectedSize = before.fileSize,
              expectedSize > 0,
              expectedSize <= maximumByteCount else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.byteLimitExceeded(filename)
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL, options: [.uncached])
        } catch {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.readFailed(filename)
        }
        guard data.count == expectedSize, data.count <= maximumByteCount else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.subjectChangedDuringRead(filename)
        }

        let after: URLResourceValues
        do {
            after = try fileURL.resourceValues(forKeys: keys)
        } catch {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.subjectChangedDuringRead(filename)
        }
        guard after.isSymbolicLink != true,
              after.isRegularFile == true,
              after.fileSize == before.fileSize,
              after.contentModificationDate == before.contentModificationDate,
              String(describing: after.fileResourceIdentifier)
                == String(describing: before.fileResourceIdentifier) else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.subjectChangedDuringRead(filename)
        }

        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            // A file that cannot be retired must not be treated as one-shot handoff state. The
            // cryptographic replay store remains the final envelope replay boundary, but failing
            // closed here avoids silently retaining sensitive signer material in the app container.
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.readFailed(filename)
        }
        return data
    }
}
