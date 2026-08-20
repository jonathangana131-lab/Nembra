import Darwin
import Foundation

public enum AuthenticatedStationaryCaptureSignerRendezvousOutboxError: Error, Equatable, Sendable {
    case applicationSupportUnavailable
    case directoryPreparationFailed(String)
    case directoryCustodyRejected(String)
    case temporaryFileCreationFailed
    case temporaryFileCustodyRejected
    case writeFailed
    case publishFailed
    case publishedSubjectMismatch
}

/// Non-authorizing, descriptor-bound publication point for the fresh signer rendezvous.
///
/// The installed app writes one complete canonical document into the same app-container directory
/// used by the manifest/envelope inbox. The field Mac may copy this file FROM the still-running app.
/// File presence is never authority: it contains only fresh challenge rendezvous facts and the
/// independently signed response still has to pass the package-pinned verifier for this process.
public struct AuthenticatedStationaryCaptureSignerRendezvousOutbox: Sendable {
    public static let rendezvousFilename = "signer-rendezvous.json"

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

    public func publish(
        _ rendezvous: AuthenticatedStationaryCaptureAppSession.SignerRendezvous
    ) throws {
        let data = try AuthenticatedStationaryCaptureSignerRendezvousDocument.encode(rendezvous)
        let directoryFD = try openOrCreateHandoffDirectory()
        defer { Darwin.close(directoryFD) }

        let temporaryName = ".signer-rendezvous-\(UUID().uuidString.lowercased()).tmp"
        let descriptor = Darwin.openat(
            directoryFD,
            temporaryName,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            mode_t(0o600)
        )
        guard descriptor >= 0 else {
            throw AuthenticatedStationaryCaptureSignerRendezvousOutboxError
                .temporaryFileCreationFailed
        }

        var temporaryStillExists = true
        defer {
            Darwin.close(descriptor)
            if temporaryStillExists {
                _ = Darwin.unlinkat(directoryFD, temporaryName, 0)
            }
        }

        var initial = stat()
        guard Darwin.fstat(descriptor, &initial) == 0,
              (initial.st_mode & S_IFMT) == S_IFREG,
              initial.st_nlink == 1,
              initial.st_uid == getuid(),
              (initial.st_mode & mode_t(0o777)) == mode_t(0o600) else {
            throw AuthenticatedStationaryCaptureSignerRendezvousOutboxError
                .temporaryFileCustodyRejected
        }

        try data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else {
                throw AuthenticatedStationaryCaptureSignerRendezvousOutboxError.writeFailed
            }
            var offset = 0
            while offset < rawBuffer.count {
                let result = Darwin.write(
                    descriptor,
                    base.advanced(by: offset),
                    rawBuffer.count - offset
                )
                if result < 0 {
                    if errno == EINTR { continue }
                    throw AuthenticatedStationaryCaptureSignerRendezvousOutboxError.writeFailed
                }
                guard result > 0 else {
                    throw AuthenticatedStationaryCaptureSignerRendezvousOutboxError.writeFailed
                }
                offset += result
            }
        }

        guard Darwin.fsync(descriptor) == 0 else {
            throw AuthenticatedStationaryCaptureSignerRendezvousOutboxError.writeFailed
        }
        var written = stat()
        guard Darwin.fstat(descriptor, &written) == 0,
              (written.st_mode & S_IFMT) == S_IFREG,
              written.st_nlink == 1,
              written.st_uid == getuid(),
              written.st_size == off_t(data.count) else {
            throw AuthenticatedStationaryCaptureSignerRendezvousOutboxError
                .temporaryFileCustodyRejected
        }

        // Replacing an old process's stale *complete* rendezvous is safe: an envelope produced from
        // stale bytes still fails this process-local challenge. `renameat` prevents partial reads.
        guard Darwin.renameat(
            directoryFD,
            temporaryName,
            directoryFD,
            Self.rendezvousFilename
        ) == 0 else {
            throw AuthenticatedStationaryCaptureSignerRendezvousOutboxError.publishFailed
        }
        temporaryStillExists = false

        let publishedFD = Darwin.openat(
            directoryFD,
            Self.rendezvousFilename,
            O_RDONLY | O_NOFOLLOW | O_CLOEXEC
        )
        guard publishedFD >= 0 else {
            throw AuthenticatedStationaryCaptureSignerRendezvousOutboxError
                .publishedSubjectMismatch
        }
        defer { Darwin.close(publishedFD) }

        var published = stat()
        guard Darwin.fstat(publishedFD, &published) == 0,
              published.st_dev == written.st_dev,
              published.st_ino == written.st_ino,
              published.st_uid == written.st_uid,
              published.st_size == written.st_size,
              published.st_nlink == 1 else {
            throw AuthenticatedStationaryCaptureSignerRendezvousOutboxError
                .publishedSubjectMismatch
        }
        guard Darwin.fsync(directoryFD) == 0 else {
            throw AuthenticatedStationaryCaptureSignerRendezvousOutboxError.publishFailed
        }
    }

    private func openOrCreateHandoffDirectory() throws -> Int32 {
        do {
            try FileManager.default.createDirectory(
                at: applicationSupportURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: 0o700)]
            )
        } catch {
            throw AuthenticatedStationaryCaptureSignerRendezvousOutboxError
                .directoryPreparationFailed("Application Support")
        }

        var directoryFD = applicationSupportURL.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard directoryFD >= 0 else {
            throw AuthenticatedStationaryCaptureSignerRendezvousOutboxError
                .directoryPreparationFailed("Application Support")
        }

        do {
            try validateDirectory(directoryFD, label: "Application Support", requirePrivateMode: false)
            for component in AuthenticatedStationaryCaptureAuthorizationInbox.directoryName
                .split(separator: "/")
                .map(String.init)
            {
                if Darwin.mkdirat(directoryFD, component, mode_t(0o700)) != 0,
                   errno != EEXIST {
                    throw AuthenticatedStationaryCaptureSignerRendezvousOutboxError
                        .directoryPreparationFailed(component)
                }
                let next = Darwin.openat(
                    directoryFD,
                    component,
                    O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
                )
                guard next >= 0 else {
                    throw AuthenticatedStationaryCaptureSignerRendezvousOutboxError
                        .directoryPreparationFailed(component)
                }
                Darwin.close(directoryFD)
                directoryFD = next
                try validateDirectory(directoryFD, label: component, requirePrivateMode: true)
            }
            return directoryFD
        } catch {
            Darwin.close(directoryFD)
            throw error
        }
    }

    private func validateDirectory(
        _ descriptor: Int32,
        label: String,
        requirePrivateMode: Bool
    ) throws {
        var metadata = stat()
        guard Darwin.fstat(descriptor, &metadata) == 0,
              (metadata.st_mode & S_IFMT) == S_IFDIR,
              metadata.st_uid == getuid() else {
            throw AuthenticatedStationaryCaptureSignerRendezvousOutboxError
                .directoryCustodyRejected(label)
        }
        if requirePrivateMode,
           (metadata.st_mode & mode_t(0o077)) != 0 {
            throw AuthenticatedStationaryCaptureSignerRendezvousOutboxError
                .directoryCustodyRejected(label)
        }
    }
}
