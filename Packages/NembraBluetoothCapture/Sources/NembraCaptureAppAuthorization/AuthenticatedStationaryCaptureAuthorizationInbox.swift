import Darwin
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
        let descriptor = try openNoFollow(fileURL: fileURL, filename: filename)
        defer { Darwin.close(descriptor) }

        var before = stat()
        guard Darwin.fstat(descriptor, &before) == 0 else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.readFailed(filename)
        }
        guard (before.st_mode & S_IFMT) == S_IFREG, before.st_nlink == 1 else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.nonRegularFile(filename)
        }
        guard before.st_size > 0, before.st_size <= maximumByteCount else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.byteLimitExceeded(filename)
        }

        var data = Data()
        data.reserveCapacity(Int(before.st_size))
        var buffer = [UInt8](repeating: 0, count: min(64 * 1024, maximumByteCount))
        while true {
            let count: Int = buffer.withUnsafeMutableBytes { rawBuffer in
                Darwin.read(descriptor, rawBuffer.baseAddress, rawBuffer.count)
            }
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                throw AuthenticatedStationaryCaptureAuthorizationInboxError.readFailed(filename)
            }
            guard data.count <= maximumByteCount - count else {
                throw AuthenticatedStationaryCaptureAuthorizationInboxError.byteLimitExceeded(filename)
            }
            data.append(contentsOf: buffer.prefix(count))
        }

        var after = stat()
        guard Darwin.fstat(descriptor, &after) == 0,
              sameIdentity(before, after),
              data.count == Int(before.st_size) else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.subjectChangedDuringRead(filename)
        }

        // Verify that the expected pathname still resolves to the exact descriptor-bound inode
        // before retiring the handoff. Even if a final same-UID swap happens after this comparison,
        // the bytes already returned above remain bound to the no-follow descriptor, so pathname
        // mutation cannot substitute authority input.
        var pathState = stat()
        let lstatResult = fileURL.withUnsafeFileSystemRepresentation { path in
            guard let path else { return -1 }
            return Darwin.lstat(path, &pathState)
        }
        guard lstatResult == 0,
              (pathState.st_mode & S_IFMT) == S_IFREG,
              pathState.st_dev == before.st_dev,
              pathState.st_ino == before.st_ino else {
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

    private func openNoFollow(fileURL: URL, filename: String) throws -> Int32 {
        let descriptor = fileURL.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard descriptor >= 0 else {
            switch errno {
            case ELOOP:
                throw AuthenticatedStationaryCaptureAuthorizationInboxError
                    .symbolicLinkRejected(filename)
            case ENOENT, ENOTDIR:
                throw AuthenticatedStationaryCaptureAuthorizationInboxError.missingSubject(filename)
            default:
                throw AuthenticatedStationaryCaptureAuthorizationInboxError.readFailed(filename)
            }
        }
        return descriptor
    }

    private func sameIdentity(_ lhs: stat, _ rhs: stat) -> Bool {
        lhs.st_dev == rhs.st_dev
            && lhs.st_ino == rhs.st_ino
            && lhs.st_mode == rhs.st_mode
            && lhs.st_nlink == rhs.st_nlink
            && lhs.st_size == rhs.st_size
            && lhs.st_mtimespec.tv_sec == rhs.st_mtimespec.tv_sec
            && lhs.st_mtimespec.tv_nsec == rhs.st_mtimespec.tv_nsec
            && lhs.st_ctimespec.tv_sec == rhs.st_ctimespec.tv_sec
            && lhs.st_ctimespec.tv_nsec == rhs.st_ctimespec.tv_nsec
    }
}
