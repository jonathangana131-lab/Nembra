import Darwin
import Foundation
import NembraBluetoothCapture

public enum AuthenticatedStationaryCaptureAuthorizationInboxError: Error, Equatable, Sendable {
    case applicationSupportUnavailable
    case missingSubject(String)
    case symbolicLinkRejected(String)
    case nonRegularFile(String)
    case multipleLinksRejected(String)
    case ownerMismatch(String)
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
        let directoryDescriptor = try openDirectory(for: filename)
        defer { Darwin.close(directoryDescriptor) }

        let openFlags = O_RDONLY | O_CLOEXEC | O_NOFOLLOW
        let descriptor = filename.withCString {
            Darwin.openat(directoryDescriptor, $0, openFlags)
        }
        guard descriptor >= 0 else {
            let failure = errno
            if failure == ELOOP {
                throw AuthenticatedStationaryCaptureAuthorizationInboxError
                    .symbolicLinkRejected(filename)
            }
            if failure == ENOENT {
                throw AuthenticatedStationaryCaptureAuthorizationInboxError
                    .missingSubject(filename)
            }
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.readFailed(filename)
        }
        defer { Darwin.close(descriptor) }

        var before = stat()
        guard Darwin.fstat(descriptor, &before) == 0 else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.readFailed(filename)
        }
        guard (before.st_mode & S_IFMT) == S_IFREG else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.nonRegularFile(filename)
        }
        guard before.st_nlink == 1 else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError
                .multipleLinksRejected(filename)
        }
        guard before.st_uid == Darwin.getuid() else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.ownerMismatch(filename)
        }
        guard before.st_size > 0,
              before.st_size <= off_t(maximumByteCount) else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.byteLimitExceeded(filename)
        }

        let expectedIdentity = SubjectIdentity(before)
        let expectedSize = Int(before.st_size)
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        var data = Data()
        data.reserveCapacity(expectedSize)
        do {
            while data.count <= maximumByteCount {
                let remaining = maximumByteCount + 1 - data.count
                guard remaining > 0 else { break }
                guard let block = try handle.read(upToCount: min(65_536, remaining)),
                      !block.isEmpty else {
                    break
                }
                data.append(block)
            }
        } catch {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.readFailed(filename)
        }
        guard data.count == expectedSize, data.count <= maximumByteCount else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError
                .subjectChangedDuringRead(filename)
        }

        var afterRead = stat()
        guard Darwin.fstat(descriptor, &afterRead) == 0,
              SubjectIdentity(afterRead) == expectedIdentity else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError
                .subjectChangedDuringRead(filename)
        }

        // Retire through the same already-open directory descriptor used for admission. A path swap
        // after `openat` cannot change the bytes read from `descriptor`. If a different pathname is
        // substituted before `unlinkat`, the opened subject keeps a link and the final fstat below
        // fails closed instead of returning bytes that were not actually consumed one-shot.
        let unlinkStatus = filename.withCString {
            Darwin.unlinkat(directoryDescriptor, $0, 0)
        }
        guard unlinkStatus == 0 else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.readFailed(filename)
        }

        var afterRetirement = stat()
        guard Darwin.fstat(descriptor, &afterRetirement) == 0,
              afterRetirement.st_dev == before.st_dev,
              afterRetirement.st_ino == before.st_ino,
              afterRetirement.st_nlink == 0 else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError
                .subjectChangedDuringRead(filename)
        }
        return data
    }

    private func openDirectory(for filename: String) throws -> Int32 {
        let flags = O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        let descriptor = directoryURL.path.withCString { Darwin.open($0, flags) }
        guard descriptor >= 0 else {
            let failure = errno
            if failure == ELOOP {
                throw AuthenticatedStationaryCaptureAuthorizationInboxError
                    .symbolicLinkRejected(Self.directoryName)
            }
            if failure == ENOENT || failure == ENOTDIR {
                throw AuthenticatedStationaryCaptureAuthorizationInboxError
                    .missingSubject(filename)
            }
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.readFailed(filename)
        }
        return descriptor
    }

    private struct SubjectIdentity: Equatable {
        let device: dev_t
        let inode: ino_t
        let mode: mode_t
        let userID: uid_t
        let linkCount: nlink_t
        let size: off_t
        let modificationSeconds: Int
        let modificationNanoseconds: Int
        let changeSeconds: Int
        let changeNanoseconds: Int

        init(_ status: stat) {
            device = status.st_dev
            inode = status.st_ino
            mode = status.st_mode
            userID = status.st_uid
            linkCount = status.st_nlink
            size = status.st_size
            modificationSeconds = Int(status.st_mtimespec.tv_sec)
            modificationNanoseconds = Int(status.st_mtimespec.tv_nsec)
            changeSeconds = Int(status.st_ctimespec.tv_sec)
            changeNanoseconds = Int(status.st_ctimespec.tv_nsec)
        }
    }
}
