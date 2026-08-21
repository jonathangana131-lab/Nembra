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
    case committedByteCountMismatch(String)
    case committedDigestMismatch(String)
    case readFailed(String)
}

/// Non-authorizing app-container handoff for the retained install manifest and the later signed
/// authorization envelope.
///
/// The field Mac publishes each subject in two phases: immutable digest-addressed staging bytes
/// first, then a tiny commit record. The live app never consumes staging bytes without a complete,
/// canonical commit record, so polling cannot mistake a quiescent transfer prefix for a finished
/// authority artifact. File presence still grants no physical authority: returned bytes must pass
/// the existing canonical runtime cross-binding/signature/current-attempt/replay verifiers.
public struct AuthenticatedStationaryCaptureAuthorizationInbox: Sendable {
    public static let directoryName = "NembraCapture/FieldAuthorization"

    public static let installManifestFilename = "retained-install-manifest.json"
    public static let authorizationEnvelopeFilename = "authorization-envelope.json"
    public static let installManifestCommitFilename = "retained-install-manifest.commit-v1"
    public static let authorizationEnvelopeCommitFilename = "authorization-envelope.commit-v1"

    private static let commitVersion = "NEMBRA-FIELD-HANDOFF-V1"
    private static let maximumCommitByteCount = 256

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

    /// Takes a completely published retained-install manifest. A missing, partial, or noncanonical
    /// commit record is treated as not-yet-published so an app polling during `devicectl copy` does
    /// not promote an intermediate prefix. Returned bytes remain non-authorizing.
    public func takeInstallManifest() throws -> Data {
        try takeCommitted(
            logicalFilename: Self.installManifestFilename,
            commitFilename: Self.installManifestCommitFilename,
            stagingStem: "retained-install-manifest",
            maximumByteCount: AuthenticatedStationaryCaptureInstallManifestVerifier
                .maximumManifestByteCount
        )
    }

    /// Takes a completely published signer response. Returned bytes remain non-authorizing and must
    /// still pass `AuthenticatedStationaryCaptureAppSession.acceptEnvelope(_:)`.
    public func takeAuthorizationEnvelope() throws -> Data {
        try takeCommitted(
            logicalFilename: Self.authorizationEnvelopeFilename,
            commitFilename: Self.authorizationEnvelopeCommitFilename,
            stagingStem: "authorization-envelope",
            maximumByteCount: AuthenticatedStationaryCaptureFieldAuthorizationVerifier
                .maximumEnvelopeByteCount
        )
    }

    private func takeCommitted(
        logicalFilename: String,
        commitFilename: String,
        stagingStem: String,
        maximumByteCount: Int
    ) throws -> Data {
        let directoryFD = try openDirectoryNoFollow(subjectFilename: logicalFilename)
        defer { Darwin.close(directoryFD) }

        let commitDescriptor: Int32
        do {
            commitDescriptor = try openSubjectNoFollow(
                directoryFD: directoryFD,
                filename: commitFilename
            )
        } catch AuthenticatedStationaryCaptureAuthorizationInboxError.missingSubject {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.missingSubject(logicalFilename)
        }
        defer { Darwin.close(commitDescriptor) }

        let commitData: Data
        do {
            commitData = try readStable(
                descriptor: commitDescriptor,
                filename: commitFilename,
                maximumByteCount: Self.maximumCommitByteCount
            ).data
        } catch AuthenticatedStationaryCaptureAuthorizationInboxError.byteLimitExceeded {
            // The commit itself may still be in flight. Do not unlink or surface transfer prefixes
            // as a terminal app error; the next poll can observe the complete record.
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.missingSubject(logicalFilename)
        } catch AuthenticatedStationaryCaptureAuthorizationInboxError.subjectChangedDuringRead {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.missingSubject(logicalFilename)
        }

        guard let commit = Self.parseCommit(
            commitData,
            stagingStem: stagingStem,
            maximumByteCount: maximumByteCount
        ) else {
            // Partial commit publication is intentionally indistinguishable from absence.
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.missingSubject(logicalFilename)
        }

        let stagedDescriptor: Int32
        do {
            stagedDescriptor = try openSubjectNoFollow(
                directoryFD: directoryFD,
                filename: commit.stagedFilename
            )
        } catch AuthenticatedStationaryCaptureAuthorizationInboxError.missingSubject {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.missingSubject(logicalFilename)
        }
        defer { Darwin.close(stagedDescriptor) }

        let staged = try readStable(
            descriptor: stagedDescriptor,
            filename: commit.stagedFilename,
            maximumByteCount: maximumByteCount
        )
        guard staged.data.count == commit.byteCount else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError
                .committedByteCountMismatch(logicalFilename)
        }
        guard Self.sha256Hex(staged.data) == commit.sha256 else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError
                .committedDigestMismatch(logicalFilename)
        }

        // Retire the commit first while both validated inodes remain open. A concurrent second poll
        // then cannot independently promote the same staged subject. Every unlink is descriptor-
        // rebound: a same-UID replacement at either pathname makes success impossible.
        try unlinkBound(
            directoryFD: directoryFD,
            filename: commitFilename,
            descriptor: commitDescriptor,
            before: try snapshot(descriptor: commitDescriptor, filename: commitFilename)
        )
        try unlinkBound(
            directoryFD: directoryFD,
            filename: commit.stagedFilename,
            descriptor: stagedDescriptor,
            before: staged.snapshot
        )

        return staged.data
    }

    private struct StableRead {
        let data: Data
        let snapshot: stat
    }

    private struct CommitRecord {
        let stagedFilename: String
        let byteCount: Int
        let sha256: String
    }

    private func readStable(
        descriptor: Int32,
        filename: String,
        maximumByteCount: Int
    ) throws -> StableRead {
        let before = try snapshot(descriptor: descriptor, filename: filename)
        guard before.st_size > 0,
              before.st_size <= off_t(maximumByteCount) else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.byteLimitExceeded(filename)
        }

        guard Darwin.lseek(descriptor, 0, SEEK_SET) >= 0 else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.readFailed(filename)
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

        let after = try snapshot(descriptor: descriptor, filename: filename)
        guard sameSnapshot(before, after), data.count == Int(before.st_size) else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.subjectChangedDuringRead(filename)
        }
        return StableRead(data: data, snapshot: before)
    }

    private func snapshot(descriptor: Int32, filename: String) throws -> stat {
        var value = stat()
        guard Darwin.fstat(descriptor, &value) == 0 else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.readFailed(filename)
        }
        guard (value.st_mode & S_IFMT) == S_IFREG else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.nonRegularFile(filename)
        }
        guard value.st_nlink == 1 else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.multipleLinksRejected(filename)
        }
        guard value.st_uid == getuid() else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.ownershipRejected(filename)
        }
        return value
    }

    private func unlinkBound(
        directoryFD: Int32,
        filename: String,
        descriptor: Int32,
        before: stat
    ) throws {
        guard Darwin.unlinkat(directoryFD, filename, 0) == 0 else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.readFailed(filename)
        }
        var after = stat()
        guard Darwin.fstat(descriptor, &after) == 0,
              sameInode(before, after),
              after.st_nlink == 0 else {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.subjectChangedDuringRead(filename)
        }
    }

    private static func parseCommit(
        _ data: Data,
        stagingStem: String,
        maximumByteCount: Int
    ) -> CommitRecord? {
        guard let text = String(data: data, encoding: .utf8),
              text.hasSuffix("\n") else { return nil }
        let body = text.dropLast()
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count == 4,
              lines[0] == Substring(commitVersion),
              let byteCount = Int(lines[2]),
              byteCount > 0,
              byteCount <= maximumByteCount else { return nil }

        let digest = String(lines[3])
        guard digest.count == 64,
              digest.allSatisfy({ $0.isNumber || ("a"..."f").contains(String($0)) }) else {
            return nil
        }
        let expectedStagedFilename = "\(stagingStem).\(digest).staged"
        guard lines[1] == Substring(expectedStagedFilename) else { return nil }

        let canonical = "\(commitVersion)\n\(expectedStagedFilename)\n\(byteCount)\n\(digest)\n"
        guard Data(canonical.utf8) == data else { return nil }
        return CommitRecord(
            stagedFilename: expectedStagedFilename,
            byteCount: byteCount,
            sha256: digest
        )
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
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
                throw AuthenticatedStationaryCaptureAuthorizationInboxError.readFailed(subjectFilename)
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
}