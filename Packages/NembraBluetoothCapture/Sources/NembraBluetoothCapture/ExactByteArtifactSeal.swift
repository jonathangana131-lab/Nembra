import CryptoKit
import Foundation

/// An immutable snapshot and integrity identity for one exact sequence of artifact bytes.
///
/// The seal answers only a software-integrity question: whether bytes presented later are
/// exactly the bytes captured here. Its SHA-256 digest and byte count do not establish where
/// the bytes came from, whether a Bluetooth observation was complete, or any physical truth.
public struct ExactByteArtifactSeal: Equatable, Sendable {
    public let sha256: String
    public let byteCount: Int

    private let exactBytes: Data

    /// Takes an independent snapshot of `exactBytes` and records its byte identity.
    public init(sealing exactBytes: Data) {
        let snapshot = exactBytes.withUnsafeBytes { Data($0) }
        self.exactBytes = snapshot
        sha256 = Self.sha256Hex(of: snapshot)
        byteCount = snapshot.count
    }

    /// Returns an independent copy of the sealed bytes after checking the seal's invariants.
    ///
    /// The check makes retrieval fail closed if the stored byte count or digest ever stops
    /// matching the private snapshot.
    public func verifiedBytes() throws -> Data {
        guard verifies(exactBytes) else {
            throw ExactByteArtifactSealError.sealedBytesIntegrityMismatch
        }

        return exactBytes.withUnsafeBytes { Data($0) }
    }

    /// Decodes the verified snapshot and requires its canonical encoding to reproduce the
    /// exact sealed bytes.
    ///
    /// `strictDecode` is responsible for rejecting malformed, trailing, or otherwise invalid
    /// input for the caller's format. Errors from either closure propagate unchanged. This
    /// method adds only two software-integrity guarantees: decoding is not attempted until the
    /// private snapshot passes `verifiedBytes()`, and the value's canonical encoding is exactly
    /// the sealed byte sequence. It does not establish schema semantics, evidence provenance,
    /// or physical truth.
    public func verifiedCanonicalValue<Value>(
        strictlyDecoding strictDecode: (Data) throws -> Value,
        canonicalEncoding canonicalEncode: (Value) throws -> Data
    ) throws -> Value {
        let bytes = try verifiedBytes()
        let value = try strictDecode(bytes)
        let canonicalBytes = try canonicalEncode(value)

        guard verifies(canonicalBytes) else {
            throw ExactByteArtifactSealError.canonicalRoundTripMismatch
        }

        return value
    }

    /// Returns `true` only when `candidate` is byte-for-byte identical to the sealed snapshot.
    ///
    /// The byte count and SHA-256 checks provide the reportable integrity identity. The final
    /// equality check keeps this API's claim narrower and stronger than digest equality alone.
    public func verifies(_ candidate: Data) -> Bool {
        guard candidate.count == byteCount else { return false }
        guard Self.sha256Hex(of: candidate) == sha256 else { return false }
        return candidate == exactBytes
    }

    private static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { byte in
            String(format: "%02x", byte)
        }.joined()
    }
}

public enum ExactByteArtifactSealError: Error, Equatable, Sendable {
    case sealedBytesIntegrityMismatch
    case canonicalRoundTripMismatch
}
