import CryptoKit
import Darwin
import Foundation

/// Non-authorizing proof that the package-owned app session accepted one exact envelope byte string.
///
/// The initializer is package-scoped so app code cannot invent a receipt. Production receives this
/// value only after `AuthenticatedStationaryCaptureAppSession.acceptEnvelope(_:)` has successfully
/// verified the source-pinned signature, current process-local challenge/runtime bindings, clocks,
/// and replay consumption. The receipt itself carries no capability, signature, GO decision, device
/// identifier, manifest, or Bluetooth authority.
public struct AuthenticatedStationaryCaptureVerifiedEnvelopeTransportReceipt: Equatable, Sendable {
    public static let schema =
        "nembra.es80-authenticated-stationary-verified-envelope-transport-receipt"
    public static let schemaVersion = 1

    public let procedureID: String
    public let attemptChallengeSHA256: String
    public let authorizationEnvelopeSHA256: String

    package init(
        envelopeData: Data,
        attemptChallengeSHA256: String,
        procedureID: String
    ) {
        self.procedureID = procedureID
        self.attemptChallengeSHA256 = attemptChallengeSHA256
        self.authorizationEnvelopeSHA256 = Self.sha256Hex(envelopeData)
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public enum AuthenticatedStationaryCaptureAuthorizationEnvelopeReceiptOutboxError:
    Error, Equatable, Sendable
{
    case applicationSupportUnavailable
    case directoryCustodyRejected
    case alreadyPublished
    case encodingFailed
    case subjectCustodyRejected
    case writeFailed
    case retirementFailed
}

/// Owner-only app-container publication boundary for the exact-envelope acceptance receipt.
///
/// This closes the field transport race where the descriptor-bound inbox legitimately unlinks the
/// signed envelope immediately after reading it. The field Mac can copy this receipt FROM the
/// still-running app and compare `authorizationEnvelopeSHA256` with the exact envelope it sent.
/// File presence is diagnostic evidence only and is never consulted by the authorization session.
public struct AuthenticatedStationaryCaptureAuthorizationEnvelopeReceiptOutbox: Sendable {
    public static let filename = "authorization-envelope-receipt.json"
    public static let maximumReceiptByteCount = 2_048

    private let directoryURL: URL

    public init() throws {
        guard let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw AuthenticatedStationaryCaptureAuthorizationEnvelopeReceiptOutboxError
                .applicationSupportUnavailable
        }
        directoryURL = applicationSupportURL.appendingPathComponent(
            AuthenticatedStationaryCaptureAuthorizationInbox.directoryName,
            isDirectory: true
        )
    }

    package init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    /// Publishes exactly one canonical receipt without replacing any earlier attempt's subject.
    /// Returns the exact bytes written so tests can bind the durable file to the typed receipt.
    @discardableResult
    public func publish(
        _ receipt: AuthenticatedStationaryCaptureVerifiedEnvelopeTransportReceipt
    ) throws -> Data {
        let data = try encode(receipt)
        let directoryFD = try openDirectoryNoFollow()
        defer { Darwin.close(directoryFD) }

        let descriptor = Darwin.openat(
            directoryFD,
            Self.filename,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            mode_t(0o600)
        )
        guard descriptor >= 0 else {
            if errno == EEXIST {
                throw AuthenticatedStationaryCaptureAuthorizationEnvelopeReceiptOutboxError
                    .alreadyPublished
            }
            throw AuthenticatedStationaryCaptureAuthorizationEnvelopeReceiptOutboxError.writeFailed
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
                    throw AuthenticatedStationaryCaptureAuthorizationEnvelopeReceiptOutboxError
                        .writeFailed
                }
                let count = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    rawBuffer.count - offset
                )
                if count < 0 {
                    if errno == EINTR { continue }
                    throw AuthenticatedStationaryCaptureAuthorizationEnvelopeReceiptOutboxError
                        .writeFailed
                }
                guard count > 0 else {
                    throw AuthenticatedStationaryCaptureAuthorizationEnvelopeReceiptOutboxError
                        .writeFailed
                }
                offset += count
            }
        }
        guard Darwin.fsync(descriptor) == 0 else {
            throw AuthenticatedStationaryCaptureAuthorizationEnvelopeReceiptOutboxError.writeFailed
        }

        var metadata = stat()
        guard Darwin.fstat(descriptor, &metadata) == 0,
              (metadata.st_mode & S_IFMT) == S_IFREG,
              metadata.st_nlink == 1,
              metadata.st_uid == getuid(),
              (metadata.st_mode & mode_t(0o777)) == mode_t(0o600),
              metadata.st_size == off_t(data.count),
              pathStillNamesDescriptor(directoryFD: directoryFD, descriptor: descriptor) else {
            throw AuthenticatedStationaryCaptureAuthorizationEnvelopeReceiptOutboxError
                .subjectCustodyRejected
        }
        completed = true
        return data
    }

    /// Retires a stale non-authorizing receipt before a new controller lifetime starts. Exact
    /// absence is success. A present subject must satisfy the same no-follow/owner/single-link
    /// custody rules before it can be unlinked.
    public func retirePublishedReceiptIfPresent() throws {
        let directoryFD = try openDirectoryNoFollow()
        defer { Darwin.close(directoryFD) }

        let descriptor = Darwin.openat(
            directoryFD,
            Self.filename,
            O_RDONLY | O_NOFOLLOW | O_CLOEXEC
        )
        if descriptor < 0 {
            if errno == ENOENT { return }
            throw AuthenticatedStationaryCaptureAuthorizationEnvelopeReceiptOutboxError
                .retirementFailed
        }
        defer { Darwin.close(descriptor) }

        var before = stat()
        guard Darwin.fstat(descriptor, &before) == 0,
              (before.st_mode & S_IFMT) == S_IFREG,
              before.st_nlink == 1,
              before.st_uid == getuid(),
              pathStillNamesDescriptor(directoryFD: directoryFD, descriptor: descriptor) else {
            throw AuthenticatedStationaryCaptureAuthorizationEnvelopeReceiptOutboxError
                .subjectCustodyRejected
        }
        guard Darwin.unlinkat(directoryFD, Self.filename, 0) == 0 else {
            throw AuthenticatedStationaryCaptureAuthorizationEnvelopeReceiptOutboxError
                .retirementFailed
        }

        var after = stat()
        guard Darwin.fstat(descriptor, &after) == 0,
              sameInode(before, after),
              after.st_nlink == 0 else {
            throw AuthenticatedStationaryCaptureAuthorizationEnvelopeReceiptOutboxError
                .retirementFailed
        }
    }

    private func encode(
        _ receipt: AuthenticatedStationaryCaptureVerifiedEnvelopeTransportReceipt
    ) throws -> Data {
        struct Wire: Encodable {
            let schema: String
            let version: Int
            let procedureID: String
            let attemptChallengeSHA256: String
            let authorizationEnvelopeSHA256: String
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data: Data
        do {
            data = try encoder.encode(
                Wire(
                    schema: AuthenticatedStationaryCaptureVerifiedEnvelopeTransportReceipt.schema,
                    version: AuthenticatedStationaryCaptureVerifiedEnvelopeTransportReceipt.schemaVersion,
                    procedureID: receipt.procedureID,
                    attemptChallengeSHA256: receipt.attemptChallengeSHA256,
                    authorizationEnvelopeSHA256: receipt.authorizationEnvelopeSHA256
                )
            )
        } catch {
            throw AuthenticatedStationaryCaptureAuthorizationEnvelopeReceiptOutboxError.encodingFailed
        }
        guard !data.isEmpty, data.count <= Self.maximumReceiptByteCount else {
            throw AuthenticatedStationaryCaptureAuthorizationEnvelopeReceiptOutboxError.encodingFailed
        }
        return data
    }

    private func openDirectoryNoFollow() throws -> Int32 {
        let descriptor = directoryURL.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard descriptor >= 0 else {
            throw AuthenticatedStationaryCaptureAuthorizationEnvelopeReceiptOutboxError
                .directoryCustodyRejected
        }
        do {
            try verifyOwnedDirectory(descriptor)
            return descriptor
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    private func verifyOwnedDirectory(_ descriptor: Int32) throws {
        var metadata = stat()
        guard Darwin.fstat(descriptor, &metadata) == 0,
              (metadata.st_mode & S_IFMT) == S_IFDIR,
              metadata.st_uid == getuid(),
              (metadata.st_mode & mode_t(0o022)) == 0 else {
            throw AuthenticatedStationaryCaptureAuthorizationEnvelopeReceiptOutboxError
                .directoryCustodyRejected
        }
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
