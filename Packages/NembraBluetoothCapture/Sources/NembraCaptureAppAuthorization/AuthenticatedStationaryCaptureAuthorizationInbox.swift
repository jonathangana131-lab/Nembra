import CryptoKit
import Darwin
import Foundation
import NembraBluetoothCapture

public enum AuthenticatedStationaryCaptureAuthorizationInboxError: Error, Equatable, Sendable {
    case applicationSupportUnavailable
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
/// The field Mac never publishes authority-bearing bytes at a filename this inbox consumes directly.
/// It first copies a bounded `.incoming` file, then copies a 65-byte lowercase SHA-256 commit record.
/// Until that commit record is complete and matches stable staged bytes, the subject is treated as
/// absent/retryable. This prevents a polling app from unlinking a partially transferred inode.
/// Matching bytes remain non-authorizing: manifest bytes still pass canonical runtime cross-binding
/// and envelope bytes still pass the independently pinned signature/current-attempt/replay verifier.
public struct AuthenticatedStationaryCaptureAuthorizationInbox: Sendable {
    public static let directoryName = "NembraCapture/FieldAuthorization"

    // Semantic subject names remain stable for controller retry/error handling. Transport uses the
    // paired incoming/commit names below and never writes these semantic names directly.
    public static let installManifestFilename = "retained-install-manifest.json"
    public static let authorizationEnvelopeFilename = "authorization-envelope.json"
    public static let installManifestIncomingFilename = "retained-install-manifest.incoming"
    public static let installManifestCommitFilename = "retained-install-manifest.commit"
    public static let authorizationEnvelopeIncomingFilename = "authorization-envelope.incoming"
    public static let authorizationEnvelopeCommitFilename = "authorization-envelope.commit"

    private static let commitRecordByteCount = 65
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

    /// Takes the stable retained-install manifest only after its completion record matches the
    /// staged bytes. The returned bytes remain non-authorizing and must be passed to
    /// `AuthenticatedStationaryCaptureAppSession.prepare(installManifestData:)`.
    public func takeInstallManifest() throws -> Data {
        try takeCommitted(
            subjectFilename: Self.installManifestFilename,
            incomingFilename: Self.installManifestIncomingFilename,
            commitFilename: Self.installManifestCommitFilename,
            maximumByteCount: AuthenticatedStationaryCaptureInstallManifestVerifier
                .maximumManifestByteCount
        )
    }

    /// Takes the post-install signer response only after its completion record matches the staged
    /// bytes. The returned bytes remain non-authorizing and must be passed to
    /// `AuthenticatedStationaryCaptureAppSession.acceptEnvelope(_:)`.
    public func takeAuthorizationEnvelope() throws -> Data {
        try takeCommitted(
            subjectFilename: Self.authorizationEnvelopeFilename,
            incomingFilename: Self.authorizationEnvelopeIncomingFilename,
            commitFilename: Self.authorizationEnvelopeCommitFilename,
            maximumByteCount: AuthenticatedStationaryCaptureFieldAuthorizationVerifier
                .maximumEnvelopeByteCount
        )
    }

    private func takeCommitted(
        subjectFilename: String,
        incomingFilename: String,
        commitFilename: String,
        maximumByteCount: Int
    ) throws -> Data {
        let directoryFD = try openDirectoryNoFollow(subjectFilename: subjectFilename)
        defer { Darwin.close(directoryFD) }

        let commitDescriptor: Int32
        do {
            commitDescriptor = try openSubjectNoFollow(
                directoryFD: directoryFD,
                filename: commitFilename
            )
        } catch AuthenticatedStationaryCaptureAuthorizationInboxError.missingSubject {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.missingSubject(subjectFilename)
        }
        defer { Darwin.close(commitDescriptor) }

        // A commit file may itself be visible while devicectl is still copying it. Any incomplete,
        // changing, or syntactically unfinished record is a retryable wait state, not a failed
        // authorization subject. Symlink/ownership/custody violations still throw terminal errors.
        guard let expectedSHA256 = try stableCommitDigest(
            descriptor: commitDescriptor,
            filename: commitFilename
        ) else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.missingSubject(subjectFilename)
        }

        let incomingDescriptor: Int32
        do {
            incomingDescriptor = try openSubjectNoFollow(
                directoryFD: directoryFD,
                filename: incomingFilename
            )
        } catch AuthenticatedStationaryCaptureAuthorizationInboxError.missingSubject {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.missingSubject(subjectFilename)
        }
        defer { Darwin.close(incomingDescriptor) }

        guard let (data, incomingSnapshot) = try stableIncomingData(
            descriptor: incomingDescriptor,
            filename: incomingFilename,
            maximumByteCount: maximumByteCount
        ) else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.missingSubject(subjectFilename)
        }

        // A stale commit can coexist briefly with a new incoming copy. Digest mismatch therefore
        // means "publication not committed yet" and must not consume or revoke the live attempt.
        guard sha256Hex(data) == expectedSHA256 else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.missingSubject(subjectFilename)
        }

        // Retire both directory entries while their validated descriptors remain open. Same-UID
        // replacement/rename races cannot turn into success because each descriptor-bound inode must
        // reach zero links before bytes leave this custody layer.
        guard Darwin.unlinkat(directoryFD, incomingFilename, 0) == 0 else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.readFailed(subjectFilename)
        }
        var incomingAfterUnlink = stat()
        guard Darwin.fstat(incomingDescriptor, &incomingAfterUnlink) == 0,
              sameInode(incomingSnapshot, incomingAfterUnlink),
              incomingAfterUnlink.st_nlink == 0 else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError
                .subjectChangedDuringRead(subjectFilename)
        }

        var commitBeforeUnlink = stat()
        guard Darwin.fstat(commitDescriptor, &commitBeforeUnlink) == 0 else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.readFailed(subjectFilename)
        }
        guard Darwin.unlinkat(directoryFD, commitFilename, 0) == 0 else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.readFailed(subjectFilename)
        }
        var commitAfterUnlink = stat()
        guard Darwin.fstat(commitDescriptor, &commitAfterUnlink) == 0,
              sameInode(commitBeforeUnlink, commitAfterUnlink),
              commitAfterUnlink.st_nlink == 0 else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError
                .subjectChangedDuringRead(subjectFilename)
        }
        return data
    }

    private func stableCommitDigest(descriptor: Int32, filename: String) throws -> String? {
        var before = stat()
        guard Darwin.fstat(descriptor, &before) == 0 else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.readFailed(filename)
        }
        try requireOwnedRegularSingleLink(before, filename: filename)
        guard before.st_size == off_t(Self.commitRecordByteCount) else { return nil }

        var bytes = [UInt8](repeating: 0, count: Self.commitRecordByteCount)
        var offset = 0
        while offset < bytes.count {
            let count = bytes.withUnsafeMutableBytes { rawBuffer in
                Darwin.read(
                    descriptor,
                    rawBuffer.baseAddress!.advanced(by: offset),
                    rawBuffer.count - offset
                )
            }
            if count < 0 {
                if errno == EINTR { continue }
                throw AuthenticatedStationaryCaptureAuthorizationInboxError.readFailed(filename)
            }
            if count == 0 { return nil }
            offset += count
        }

        var after = stat()
        guard Darwin.fstat(descriptor, &after) == 0 else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.readFailed(filename)
        }
        guard sameSnapshot(before, after) else { return nil }
        guard bytes.last == 0x0A else { return nil }
        let digestBytes = bytes.dropLast()
        guard digestBytes.allSatisfy({ byte in
            (0x30...0x39).contains(byte) || (0x61...0x66).contains(byte)
        }) else { return nil }
        return String(decoding: digestBytes, as: UTF8.self)
    }

    private func stableIncomingData(
        descriptor: Int32,
        filename: String,
        maximumByteCount: Int
    ) throws -> (Data, stat)? {
        var before = stat()
        guard Darwin.fstat(descriptor, &before) == 0 else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.readFailed(filename)
        }
        try requireOwnedRegularSingleLink(before, filename: filename)

        // Zero bytes can be a newly visible in-flight copy and is retryable. Oversize cannot come
        // from the bounded field transport and is therefore a terminal committed-subject violation.
        guard before.st_size > 0 else { return nil }
        guard before.st_size <= off_t(maximumByteCount) else {
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
        guard Darwin.fstat(descriptor, &afterRead) == 0 else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.readFailed(filename)
        }
        guard sameSnapshot(before, afterRead), data.count == Int(before.st_size) else { return nil }
        return (data, before)
    }

    private func requireOwnedRegularSingleLink(_ metadata: stat, filename: String) throws {
        guard (metadata.st_mode & S_IFMT) == S_IFREG else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.nonRegularFile(filename)
        }
        guard metadata.st_nlink == 1 else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.multipleLinksRejected(filename)
        }
        guard metadata.st_uid == getuid() else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.ownershipRejected(filename)
        }
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

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
