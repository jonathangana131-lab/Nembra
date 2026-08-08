import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum PassiveBluetoothCaptureArtifactInputPolicyError: Error, Equatable, Sendable {
    case invalidMaximumArtifactBytes(Int)
    case sourceArtifactExceedsMaximumBytes(maximumBytes: Int)
    case sourceArtifactIsNotRegularFile
    case sourceArtifactChangedWhileReading
}

extension PassiveBluetoothCaptureArtifactInputPolicyError: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .invalidMaximumArtifactBytes(value):
            "maximum source-artifact byte limit must be between 1 and Int.max - 1, got: \(value)"
        case let .sourceArtifactExceedsMaximumBytes(maximumBytes):
            "source capture exceeds configured offline artifact limit of \(maximumBytes) bytes"
        case .sourceArtifactIsNotRegularFile:
            "source capture must be one regular file"
        case .sourceArtifactChangedWhileReading:
            "source capture changed while its exact offline-analysis bytes were being admitted"
        }
    }
}

struct PassiveBluetoothCaptureArtifactInputIdentity: Equatable, Sendable {
    let device: UInt64
    let inode: UInt64
    let mode: UInt64
    let ownerUser: UInt64
    let ownerGroup: UInt64
    let byteCount: Int64
    let modifiedSeconds: Int64
    let modifiedNanoseconds: Int64
    let changedSeconds: Int64
    let changedNanoseconds: Int64
}

/// Durable cross-phase receipt for one exact admitted raw-capture filesystem subject.
///
/// The exact bytes are retained together with descriptor identity measured before
/// and after two matching reads. Offline report publication can therefore prove
/// it is still protecting the same source subject instead of reopening a path and
/// silently accepting a replacement inode between admission and publication.
public struct PassiveBluetoothCaptureArtifactInputReceipt: Sendable {
    public let bytes: Data
    let admittedSourceIdentity: PassiveBluetoothCaptureArtifactInputIdentity

    init(
        bytes: Data,
        admittedSourceIdentity: PassiveBluetoothCaptureArtifactInputIdentity
    ) {
        self.bytes = bytes
        self.admittedSourceIdentity = admittedSourceIdentity
    }
}

/// Offline process-safety policy for loading passive-capture artifacts.
///
/// These byte ceilings protect the operator tool from materializing or decoding
/// arbitrarily large input. They are tooling resource limits only: they do not
/// describe an ES80 packet, message, session, transport, or physical capture
/// maximum.
public enum PassiveBluetoothCaptureArtifactInputPolicy {
    public static let defaultMaximumArtifactBytes = 64 * 1024 * 1024
    private static let readChunkBytes = 1024 * 1024

    public static func readExactReceipt(
        at inputURL: URL,
        maximumBytes: Int = defaultMaximumArtifactBytes
    ) throws -> PassiveBluetoothCaptureArtifactInputReceipt {
        try readExactReceipt(
            at: inputURL,
            maximumBytes: maximumBytes,
            afterFirstReadChunk: nil,
            betweenVerificationPasses: nil
        )
    }

    public static func readExactBytes(
        at inputURL: URL,
        maximumBytes: Int = defaultMaximumArtifactBytes
    ) throws -> Data {
        try readExactReceipt(at: inputURL, maximumBytes: maximumBytes).bytes
    }

    static func readExactBytes(
        at inputURL: URL,
        maximumBytes: Int,
        afterFirstReadChunk: (() throws -> Void)? = nil,
        betweenVerificationPasses: (() throws -> Void)?
    ) throws -> Data {
        try readExactReceipt(
            at: inputURL,
            maximumBytes: maximumBytes,
            afterFirstReadChunk: afterFirstReadChunk,
            betweenVerificationPasses: betweenVerificationPasses
        ).bytes
    }

    static func readExactReceipt(
        at inputURL: URL,
        maximumBytes: Int,
        afterFirstReadChunk: (() throws -> Void)? = nil,
        betweenVerificationPasses: (() throws -> Void)?
    ) throws -> PassiveBluetoothCaptureArtifactInputReceipt {
        try validateMaximum(maximumBytes)

        let handle = try FileHandle(forReadingFrom: inputURL)
        defer { try? handle.close() }

        let admittedIdentity = try descriptorIdentity(of: handle)
        guard admittedIdentity.byteCount <= Int64(maximumBytes) else {
            throw PassiveBluetoothCaptureArtifactInputPolicyError
                .sourceArtifactExceedsMaximumBytes(maximumBytes: maximumBytes)
        }

        let firstPass = try readBoundedPass(
            from: handle,
            maximumBytes: maximumBytes,
            afterFirstReadChunk: afterFirstReadChunk
        )
        guard firstPass.count == Int(admittedIdentity.byteCount),
              try descriptorIdentity(of: handle) == admittedIdentity else {
            throw PassiveBluetoothCaptureArtifactInputPolicyError
                .sourceArtifactChangedWhileReading
        }

        try betweenVerificationPasses?()
        guard try descriptorIdentity(of: handle) == admittedIdentity else {
            throw PassiveBluetoothCaptureArtifactInputPolicyError
                .sourceArtifactChangedWhileReading
        }

        try handle.seek(toOffset: 0)
        try requireSecondPassMatches(
            firstPass,
            from: handle,
            maximumBytes: maximumBytes
        )
        guard try descriptorIdentity(of: handle) == admittedIdentity else {
            throw PassiveBluetoothCaptureArtifactInputPolicyError
                .sourceArtifactChangedWhileReading
        }

        return PassiveBluetoothCaptureArtifactInputReceipt(
            bytes: firstPass,
            admittedSourceIdentity: admittedIdentity
        )
    }

    public static func validateByteCount(
        _ byteCount: Int,
        maximumBytes: Int = defaultMaximumArtifactBytes
    ) throws {
        try validateMaximum(maximumBytes)
        guard byteCount <= maximumBytes else {
            throw PassiveBluetoothCaptureArtifactInputPolicyError
                .sourceArtifactExceedsMaximumBytes(maximumBytes: maximumBytes)
        }
    }

    private static func descriptorIdentity(
        of handle: FileHandle
    ) throws -> PassiveBluetoothCaptureArtifactInputIdentity {
        #if canImport(Darwin) || canImport(Glibc)
        var metadata = stat()
        guard fstat(handle.fileDescriptor, &metadata) == 0 else {
            throw PassiveBluetoothCaptureArtifactInputPolicyError
                .sourceArtifactChangedWhileReading
        }

        let fileType = mode_t(metadata.st_mode) & mode_t(S_IFMT)
        guard fileType == mode_t(S_IFREG) else {
            throw PassiveBluetoothCaptureArtifactInputPolicyError
                .sourceArtifactIsNotRegularFile
        }
        guard metadata.st_size >= 0 else {
            throw PassiveBluetoothCaptureArtifactInputPolicyError
                .sourceArtifactChangedWhileReading
        }

        #if canImport(Darwin)
        let modifiedSeconds = Int64(metadata.st_mtimespec.tv_sec)
        let modifiedNanoseconds = Int64(metadata.st_mtimespec.tv_nsec)
        let changedSeconds = Int64(metadata.st_ctimespec.tv_sec)
        let changedNanoseconds = Int64(metadata.st_ctimespec.tv_nsec)
        #else
        let modifiedSeconds = Int64(metadata.st_mtim.tv_sec)
        let modifiedNanoseconds = Int64(metadata.st_mtim.tv_nsec)
        let changedSeconds = Int64(metadata.st_ctim.tv_sec)
        let changedNanoseconds = Int64(metadata.st_ctim.tv_nsec)
        #endif

        return PassiveBluetoothCaptureArtifactInputIdentity(
            device: UInt64(metadata.st_dev),
            inode: UInt64(metadata.st_ino),
            mode: UInt64(metadata.st_mode),
            ownerUser: UInt64(metadata.st_uid),
            ownerGroup: UInt64(metadata.st_gid),
            byteCount: Int64(metadata.st_size),
            modifiedSeconds: modifiedSeconds,
            modifiedNanoseconds: modifiedNanoseconds,
            changedSeconds: changedSeconds,
            changedNanoseconds: changedNanoseconds
        )
        #else
        throw PassiveBluetoothCaptureArtifactInputPolicyError
            .sourceArtifactChangedWhileReading
        #endif
    }

    private static func readBoundedPass(
        from handle: FileHandle,
        maximumBytes: Int,
        afterFirstReadChunk: (() throws -> Void)?
    ) throws -> Data {
        var data = Data()
        data.reserveCapacity(min(maximumBytes, readChunkBytes))
        var invokedFirstChunkSeam = false

        while true {
            let remaining = maximumBytes - data.count
            let requested = min(readChunkBytes, remaining + 1)
            guard let chunk = try handle.read(upToCount: requested), !chunk.isEmpty else {
                return data
            }

            data.append(chunk)
            guard data.count <= maximumBytes else {
                throw PassiveBluetoothCaptureArtifactInputPolicyError
                    .sourceArtifactExceedsMaximumBytes(maximumBytes: maximumBytes)
            }

            if !invokedFirstChunkSeam {
                invokedFirstChunkSeam = true
                try afterFirstReadChunk?()
            }
        }
    }

    private static func requireSecondPassMatches(
        _ expected: Data,
        from handle: FileHandle,
        maximumBytes: Int
    ) throws {
        var offset = 0

        while true {
            let remainingLimit = maximumBytes - offset
            let requested = min(readChunkBytes, remainingLimit + 1)
            guard let chunk = try handle.read(upToCount: requested), !chunk.isEmpty else {
                guard offset == expected.count else {
                    throw PassiveBluetoothCaptureArtifactInputPolicyError
                        .sourceArtifactChangedWhileReading
                }
                return
            }

            let end = offset + chunk.count
            guard end <= expected.count,
                  chunk.elementsEqual(expected[offset..<end]) else {
                throw PassiveBluetoothCaptureArtifactInputPolicyError
                    .sourceArtifactChangedWhileReading
            }
            offset = end
        }
    }

    private static func validateMaximum(_ maximumBytes: Int) throws {
        guard maximumBytes > 0, maximumBytes < Int.max else {
            throw PassiveBluetoothCaptureArtifactInputPolicyError
                .invalidMaximumArtifactBytes(maximumBytes)
        }
    }
}