import Darwin
import Foundation
import NembraBluetoothCapture

public enum AuthenticatedStationaryCaptureAuthorizationInboxError: Error, Equatable, Sendable {
    case applicationSupportUnavailable
    case directoryCustodyRejected(String)
    case missingSubject(String)
    case symbolicLinkRejected(String)
    case nonRegularFile(String)
    case multipleLinksRejected(String)
    case ownershipRejected(String)
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

    private let applicationSupportURL: URL?
    private let directoryURL: URL

    public init() throws {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.applicationSupportUnavailable
        }
        applicationSupportURL = applicationSupport
        directoryURL = applicationSupport.appendingPathComponent(
            Self.directoryName,
            isDirectory: true
        )
    }

    package init(directoryURL: URL) {
        applicationSupportURL = nil
        self.directoryURL = directoryURL
    }

    package init(applicationSupportURL: URL) {
        self.applicationSupportURL = applicationSupportURL
        directoryURL = applicationSupportURL.appendingPathComponent(
            Self.directoryName,
            isDirectory: true
        )
    }

    /// Creates and validates the owner-controlled app-container rendezvous directory before the
    /// field Mac attempts the first manifest copy. This operation is deliberately non-authorizing:
    /// it creates no manifest, envelope, challenge, capability, signature, or physical GO state.
    ///
    /// Every path component is created/opened descriptor-relatively with `O_NOFOLLOW`, remains
    /// owned by the app user, and rejects group/world-writable custody. This removes a chronology
    /// cycle where the manifest could not be delivered until a directory that was previously only
    /// created after manifest acceptance happened to exist.
    public func prepareHandoffDirectory() throws {
        guard let applicationSupportURL else {
            let descriptor = try openDirectoryNoFollow(
                subjectFilename: Self.installManifestFilename
            )
            Darwin.close(descriptor)
            return
        }

        let baseFD = applicationSupportURL.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard baseFD >= 0 else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError
                .directoryCustodyRejected("Application Support")
        }

        var currentFD = baseFD
        do {
            try validateOwnedDirectory(
                descriptor: currentFD,
                label: "Application Support"
            )
            for component in Self.directoryName.split(separator: "/").map(String.init) {
                if Darwin.mkdirat(currentFD, component, mode_t(0o700)) != 0,
                   errno != EEXIST {
                    throw AuthenticatedStationaryCaptureAuthorizationInboxError
                        .directoryCustodyRejected(component)
                }

                let nextFD = Darwin.openat(
                    currentFD,
                    component,
                    O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
                )
                guard nextFD >= 0 else {
                    throw AuthenticatedStationaryCaptureAuthorizationInboxError
                        .directoryCustodyRejected(component)
                }
                do {
                    try validateOwnedDirectory(descriptor: nextFD, label: component)
                } catch {
                    Darwin.close(nextFD)
                    throw error
                }
                Darwin.close(currentFD)
                currentFD = nextFD
            }
            Darwin.close(currentFD)
        } catch {
            Darwin.close(currentFD)
            throw error
        }
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
        let directoryFD = try openDirectoryNoFollow(subjectFilename: filename)
        defer { Darwin.close(directoryFD) }

        let descriptor = try openSubjectNoFollow(
            directoryFD: directoryFD,
            filename: filename
        )
        defer { Darwin.close(descriptor) }

        var before = stat()
        guard Darwin.fstat(descriptor, &before) == 0 else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.readFailed(filename)
        }
        guard (before.st_mode & S_IFMT) == S_IFREG else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.nonRegularFile(filename)
        }
        guard before.st_nlink == 1 else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.multipleLinksRejected(filename)
        }
        guard before.st_uid == getuid() else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.ownershipRejected(filename)
        }
        guard before.st_size > 0,
              before.st_size <= off_t(maximumByteCount) else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.byteLimitExceeded(filename)
        }

        var data = Data()
        data.reserveCapacity(Int(before.st_size))
        var buffer = [UInt8](repeating: 0, count: min(64 * 1024, maximumByteCount))
        while true {
            let count = buffer.withUnsafeMutableBytes { rawBuffer in
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

        var afterRead = stat()
        guard Darwin.fstat(descriptor, &afterRead) == 0,
              sameSnapshot(before, afterRead),
              data.count == Int(before.st_size) else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.subjectChangedDuringRead(filename)
        }

        // Retire the directory entry while the validated inode is still open. A same-UID rename or
        // replacement cannot cause success: after unlinking the expected name, the descriptor-bound
        // inode itself must have zero remaining links before its bytes can leave this custody layer.
        guard Darwin.unlinkat(directoryFD, filename, 0) == 0 else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.readFailed(filename)
        }

        var afterUnlink = stat()
        guard Darwin.fstat(descriptor, &afterUnlink) == 0,
              sameInode(before, afterUnlink),
              afterUnlink.st_nlink == 0 else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.subjectChangedDuringRead(filename)
        }
        return data
    }

    private func openDirectoryNoFollow(subjectFilename: String) throws -> Int32 {
        let descriptor = directoryURL.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard descriptor >= 0 else {
            switch errno {
            case ELOOP:
                throw AuthenticatedStationaryCaptureAuthorizationInboxError
                    .symbolicLinkRejected(Self.directoryName)
            case ENOENT, ENOTDIR:
                throw AuthenticatedStationaryCaptureAuthorizationInboxError
                    .missingSubject(subjectFilename)
            default:
                throw AuthenticatedStationaryCaptureAuthorizationInboxError
                    .readFailed(subjectFilename)
            }
        }
        return descriptor
    }

    private func openSubjectNoFollow(directoryFD: Int32, filename: String) throws -> Int32 {
        let descriptor = Darwin.openat(
            directoryFD,
            filename,
            O_RDONLY | O_NOFOLLOW | O_CLOEXEC
        )
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

    private func validateOwnedDirectory(descriptor: Int32, label: String) throws {
        var metadata = stat()
        guard Darwin.fstat(descriptor, &metadata) == 0,
              (metadata.st_mode & S_IFMT) == S_IFDIR,
              metadata.st_uid == getuid(),
              (metadata.st_mode & mode_t(0o022)) == 0 else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError
                .directoryCustodyRejected(label)
        }
    }

    private func sameSnapshot(_ lhs: stat, _ rhs: stat) -> Bool {
        sameInode(lhs, rhs)
            && lhs.st_mode == rhs.st_mode
            && lhs.st_uid == rhs.st_uid
            && lhs.st_gid == rhs.st_gid
            && lhs.st_nlink == rhs.st_nlink
            && lhs.st_size == rhs.st_size
            && lhs.st_mtimespec.tv_sec == rhs.st_mtimespec.tv_sec
            && lhs.st_mtimespec.tv_nsec == rhs.st_mtimespec.tv_nsec
            && lhs.st_ctimespec.tv_sec == rhs.st_ctimespec.tv_sec
            && lhs.st_ctimespec.tv_nsec == rhs.st_ctimespec.tv_nsec
    }

    private func sameInode(_ lhs: stat, _ rhs: stat) -> Bool {
        lhs.st_dev == rhs.st_dev && lhs.st_ino == rhs.st_ino
    }
}
