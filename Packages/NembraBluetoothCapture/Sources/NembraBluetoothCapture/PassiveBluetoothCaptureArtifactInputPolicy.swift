import Foundation

public enum PassiveBluetoothCaptureArtifactInputPolicyError: Error, Equatable, Sendable {
    case invalidMaximumArtifactBytes(Int)
    case sourceArtifactExceedsMaximumBytes(maximumBytes: Int)
    case sourceArtifactChangedWhileReading
}

extension PassiveBluetoothCaptureArtifactInputPolicyError: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .invalidMaximumArtifactBytes(value):
            "maximum source-artifact byte limit must be between 1 and Int.max - 1, got: \(value)"
        case let .sourceArtifactExceedsMaximumBytes(maximumBytes):
            "source capture exceeds configured offline artifact limit of \(maximumBytes) bytes"
        case .sourceArtifactChangedWhileReading:
            "source capture changed while its exact offline-analysis bytes were being admitted"
        }
    }
}

/// Offline process-safety policy for loading passive-capture artifacts.
///
/// These byte ceilings protect the operator tool from materializing or decoding
/// arbitrarily large input. They are tooling resource limits only: they do not
/// describe an ES80 packet, message, session, transport, or physical capture
/// maximum.
public enum PassiveBluetoothCaptureArtifactInputPolicy {
    /// A deliberately generous default for the offline tool, not a protocol
    /// expectation. Callers may choose another explicit positive ceiling.
    public static let defaultMaximumArtifactBytes = 64 * 1024 * 1024

    private static let readChunkBytes = 1024 * 1024

    /// Reads one stable exact source byte sequence while never retaining more
    /// than the configured ceiling plus the one byte required to prove that the
    /// source is oversized.
    ///
    /// The source is read twice through the same open file handle. Pass one is
    /// the exact byte subject returned to the caller; pass two must match it
    /// byte-for-byte and terminate at the same offset. This prevents an in-place
    /// mutation during admission from silently producing a mixed artifact whose
    /// digest would look authoritative even though no stable file state had those
    /// bytes. A later replacement of the path does not alter the already-open
    /// subject and therefore cannot retarget the admitted bytes.
    ///
    /// Unlike a whole-file `Data(contentsOf:)` load followed by a size check,
    /// this bounds file materialization before JSON decode. The returned bytes are
    /// unchanged and remain suitable for exact SHA-256 provenance.
    public static func readExactBytes(
        at inputURL: URL,
        maximumBytes: Int = defaultMaximumArtifactBytes
    ) throws -> Data {
        try readExactBytes(
            at: inputURL,
            maximumBytes: maximumBytes,
            betweenVerificationPasses: nil
        )
    }

    /// Internal deterministic seam used only by package tests to prove that a
    /// same-length in-place mutation between verification passes fails closed.
    static func readExactBytes(
        at inputURL: URL,
        maximumBytes: Int,
        betweenVerificationPasses: (() throws -> Void)?
    ) throws -> Data {
        try validateMaximum(maximumBytes)

        let handle = try FileHandle(forReadingFrom: inputURL)
        defer { try? handle.close() }

        let firstPass = try readBoundedPass(
            from: handle,
            maximumBytes: maximumBytes
        )

        try betweenVerificationPasses?()
        try handle.seek(toOffset: 0)
        try requireSecondPassMatches(
            firstPass,
            from: handle,
            maximumBytes: maximumBytes
        )
        return firstPass
    }

    /// Bounds already-materialized input before the much larger decoded capture
    /// object graph can be created. File-based callers should also use
    /// `readExactBytes(at:maximumBytes:)` so the source `Data` itself is bounded.
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

    private static func readBoundedPass(
        from handle: FileHandle,
        maximumBytes: Int
    ) throws -> Data {
        var data = Data()
        data.reserveCapacity(min(maximumBytes, readChunkBytes))

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
