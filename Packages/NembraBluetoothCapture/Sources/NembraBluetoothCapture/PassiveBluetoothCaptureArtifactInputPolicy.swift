import Foundation

public enum PassiveBluetoothCaptureArtifactInputPolicyError: Error, Equatable, Sendable {
    case invalidMaximumArtifactBytes(Int)
    case sourceArtifactExceedsMaximumBytes(maximumBytes: Int)
}

extension PassiveBluetoothCaptureArtifactInputPolicyError: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .invalidMaximumArtifactBytes(value):
            "maximum source-artifact byte limit must be between 1 and Int.max - 1, got: \(value)"
        case let .sourceArtifactExceedsMaximumBytes(maximumBytes):
            "source capture exceeds configured offline artifact limit of \(maximumBytes) bytes"
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

    /// Reads the exact source bytes while never retaining more than the configured
    /// ceiling plus the one byte required to prove that the source is oversized.
    ///
    /// Unlike a whole-file `Data(contentsOf:)` load followed by a size check,
    /// this bounds file materialization before JSON decode. The returned bytes are
    /// unchanged and remain suitable for exact SHA-256 provenance.
    public static func readExactBytes(
        at inputURL: URL,
        maximumBytes: Int = defaultMaximumArtifactBytes
    ) throws -> Data {
        try validateMaximum(maximumBytes)

        let handle = try FileHandle(forReadingFrom: inputURL)
        defer { try? handle.close() }

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

    private static func validateMaximum(_ maximumBytes: Int) throws {
        guard maximumBytes > 0, maximumBytes < Int.max else {
            throw PassiveBluetoothCaptureArtifactInputPolicyError
                .invalidMaximumArtifactBytes(maximumBytes)
        }
    }
}
