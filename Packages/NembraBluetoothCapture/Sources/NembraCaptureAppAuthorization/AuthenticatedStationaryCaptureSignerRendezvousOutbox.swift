import Darwin
import Foundation

public enum AuthenticatedStationaryCaptureSignerRendezvousOutboxError: Error, Equatable, Sendable {
    case applicationSupportUnavailable
    case directoryCustodyRejected(String)
    case alreadyPublished
    case subjectCustodyRejected
    case writeFailed
    case retirementFailed
}

/// App-container publication boundary for one non-authorizing signer rendezvous document.
///
/// Publication is no-replace and owner-only. The file contains only package-generated rendezvous
/// facts; it never carries a capability, trust root, signature, GO decision, device identifier, or
/// Bluetooth authority. A later field transport may copy these exact bytes FROM the still-running
/// app container, but OFF1 remains impossible until the independently signed envelope is returned
/// and accepted by `AuthenticatedStationaryCaptureAppSession`.
public struct AuthenticatedStationaryCaptureSignerRendezvousOutbox: Sendable {
    public static let filename = "signer-rendezvous.json"

    private let applicationSupportURL: URL

    public init() throws {
        guard let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw AuthenticatedStationaryCaptureSignerRendezvousOutboxError
                .applicationSupportUnavailable
        }
        self.applicationSupportURL = applicationSupportURL
    }

    package init(applicationSupportURL: URL) {
        self.applicationSupportURL = applicationSupportURL
    }

    /// Creates and verifies only the owner-controlled app-container directory needed by the
    /// external exact-file transport for the first retained manifest. This publishes no bytes,
    /// creates no challenge, consumes no manifest, mints no capability, and grants no Bluetooth
    /// authority. It is safe to call repeatedly before the independent signer handoff begins.
    public func prepareAuthorizationTransferDirectory() throws {
        let directoryFD = try openFieldAuthorizationDirectory(createIfMissing: true)
        Darwin.close(directoryFD)
    }

    /// Publishes exactly one canonical document without replacing any earlier attempt's rendezvous.
    /// Returns the same bytes written to disk for diagnostics/tests; the bytes are non-authorizing.
    @discardableResult
    public func publish(
        _ rendezvous: AuthenticatedStationaryCaptureAppSession.SignerRendezvous
    ) throws -> Data {
        let data = try AuthenticatedStationaryCaptureSignerRendezvousDocument.encode(rendezvous)
        let directoryFD = try openFieldAuthorizationDirectory(createIfMissing: true)
        defer { Darwin.close(directoryFD) }

        let descriptor = Darwin.openat(
            directoryFD,
            Self.filename,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            mode_t(0o600)
        )
        guard descriptor >= 0 else {
            if errno == EEXIST {
                throw AuthenticatedStationaryCaptureSignerRendezvousOutboxError.alreadyPublished
            }
            throw AuthenticatedStationaryCaptureSignerRendezvousOutboxError.writeFailed
        }

        var completed = false
        defer {
            if !completed,
               pathStillNamesDescriptor(directoryFD: directoryFD, descriptor: descriptor) {
                _ = Darwin.unlinkat(directoryFD, Self.filename, 0)
            }
            Darwin.close(descriptor)
        }

        try data.withUnsafeBytes { rawBuffer in
            var offset = 0
            while offset < rawBuffer.count {
                guard let baseAddress = rawBuffer.baseAddress else {
                    throw AuthenticatedStationaryCaptureSignerRendezvousOutboxError.writeFailed
                }
                let count = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    rawBuffer.count - offset
                )
                if count < 0 {
                    if errno == EINTR { continue }
                    throw AuthenticatedStationaryCaptureSignerRendezvousOutboxError.writeFailed
                }
                guard count > 0 else {
                    throw AuthenticatedStationaryCaptureSignerRendezvousOutboxError.writeFailed
                }
                offset += count
            }
        }
        guard Darwin.fsync(descriptor) == 0 else {
            throw AuthenticatedStationaryCaptureSignerRendezvousOutboxError.writeFailed
        }

        var metadata = stat()
        guard Darwin.fstat(descriptor, &metadata) == 0,
              (metadata.st_mode & S_IFMT) == S_IFREG,
              metadata.st_nlink == 1,
              metadata.st_uid == getuid(),
              (metadata.st_mode & mode_t(0o777)) == mode_t(0o600),
              metadata.st_size == off_t(data.count),
              pathStillNamesDescriptor(directoryFD: directoryFD, descriptor: descriptor) else {
            throw AuthenticatedStationaryCaptureSignerRendezvousOutboxError
                .subjectCustodyRejected
        }
        completed = true
        return data
    }

    /// Retires the exact published inode before a returned envelope is accepted. This prevents a
    /// stale rendezvous from being mistaken for a later attempt and never grants authority itself.
    public func retirePublishedRendezvous() throws {
        let directoryFD = try openFieldAuthorizationDirectory(createIfMissing: false)
        defer { Darwin.close(directoryFD) }

        let descriptor = Darwin.openat(
            directoryFD,
            Self.filename,
            O_RDONLY | O_NOFOLLOW | O_CLOEXEC
        )
        guard descriptor >= 0 else {
            throw AuthenticatedStationaryCaptureSignerRendezvousOutboxError.retirementFailed
        }
        defer { Darwin.close(descriptor) }

        var before = stat()
        guard Darwin.fstat(descriptor, &before) == 0,
              (before.st_mode & S_IFMT) == S_IFREG,
              before.st_nlink == 1,
              before.st_uid == getuid(),
              pathStillNamesDescriptor(directoryFD: directoryFD, descriptor: descriptor) else {
            throw AuthenticatedStationaryCaptureSignerRendezvousOutboxError
                .subjectCustodyRejected
        }
        guard Darwin.unlinkat(directoryFD, Self.filename, 0) == 0 else {
            throw AuthenticatedStationaryCaptureSignerRendezvousOutboxError.retirementFailed
        }

        var after = stat()
        guard Darwin.fstat(descriptor, &after) == 0,
              sameInode(before, after),
              after.st_nlink == 0 else {
            throw AuthenticatedStationaryCaptureSignerRendezvousOutboxError.retirementFailed
        }
    }

    private func openFieldAuthorizationDirectory(createIfMissing: Bool) throws -> Int32 {
        let baseFD = applicationSupportURL.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard baseFD >= 0 else {
            throw AuthenticatedStationaryCaptureSignerRendezvousOutboxError
                .applicationSupportUnavailable
        }

        var baseMetadata = stat()
        guard Darwin.fstat(baseFD, &baseMetadata) == 0,
              (baseMetadata.st_mode & S_IFMT) == S_IFDIR,
              baseMetadata.st_uid == getuid(),
              (baseMetadata.st_mode & mode_t(0o022)) == 0 else {
            Darwin.close(baseFD)
            throw AuthenticatedStationaryCaptureSignerRendezvousOutboxError
                .directoryCustodyRejected("Application Support")
        }

        var currentFD = baseFD
        do {
            for component in AuthenticatedStationaryCaptureAuthorizationInbox.directoryName
                .split(separator: "/").map(String.init) {
                let nextFD = try openOwnedDirectory(
                    parentFD: currentFD,
                    name: component,
                    createIfMissing: createIfMissing
                )
                Darwin.close(currentFD)
                currentFD = nextFD
            }
            return currentFD
        } catch {
            Darwin.close(currentFD)
            throw error
        }
    }

    private func openOwnedDirectory(
        parentFD: Int32,
        name: String,
        createIfMissing: Bool
    ) throws -> Int32 {
        if createIfMissing, Darwin.mkdirat(parentFD, name, mode_t(0o700)) != 0, errno != EEXIST {
            throw AuthenticatedStationaryCaptureSignerRendezvousOutboxError
                .directoryCustodyRejected(name)
        }

        let descriptor = Darwin.openat(
            parentFD,
            name,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard descriptor >= 0 else {
            throw AuthenticatedStationaryCaptureSignerRendezvousOutboxError
                .directoryCustodyRejected(name)
        }

        var metadata = stat()
        guard Darwin.fstat(descriptor, &metadata) == 0,
              (metadata.st_mode & S_IFMT) == S_IFDIR,
              metadata.st_uid == getuid(),
              (metadata.st_mode & mode_t(0o022)) == 0 else {
            Darwin.close(descriptor)
            throw AuthenticatedStationaryCaptureSignerRendezvousOutboxError
                .directoryCustodyRejected(name)
        }
        return descriptor
    }

    private func pathStillNamesDescriptor(directoryFD: Int32, descriptor: Int32) -> Bool {
        var opened = stat()
        var published = stat()
        guard Darwin.fstat(descriptor, &opened) == 0,
              Darwin.fstatat(directoryFD, Self.filename, &published, AT_SYMLINK_NOFOLLOW) == 0,
              (published.st_mode & S_IFMT) == S_IFREG else {
            return false
        }
        return sameInode(opened, published)
    }

    private func sameInode(_ lhs: stat, _ rhs: stat) -> Bool {
        lhs.st_dev == rhs.st_dev && lhs.st_ino == rhs.st_ino
    }
}
