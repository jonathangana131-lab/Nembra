import CryptoKit
import Foundation
import NembraCore

/// Exact-file integrity facts for one already-finalized passive Capture artifact.
///
/// This report is intentionally narrow. It proves that the exact bytes supplied to the
/// inspector are readable by the current Capture schema and records file/event counts
/// plus a deterministic SHA-256 digest. It does not prove RF completeness, scooter
/// identity, GATT/Tuya semantics, telemetry meaning, or physical authorization.
public struct PassiveBluetoothFinalizedArtifactIntegrityReport: Equatable, Sendable {
    public let sha256: String
    public let byteCount: Int
    public let captureSessionID: UUID
    public let recordCount: Int
    public let rawValueRecordCount: Int

    // This value represents an earned decode/readability result, so construction stays inside the
    // package inspector while public clients retain read-only access to the verified facts.
    init(
        sha256: String,
        byteCount: Int,
        captureSessionID: UUID,
        recordCount: Int,
        rawValueRecordCount: Int
    ) {
        self.sha256 = sha256
        self.byteCount = byteCount
        self.captureSessionID = captureSessionID
        self.recordCount = recordCount
        self.rawValueRecordCount = rawValueRecordCount
    }
}

public enum PassiveBluetoothFinalizedArtifactIntegrity {
    /// Decodes the exact immutable JSON bytes and returns deterministic file/event facts.
    ///
    /// Callers must preserve and share the same `data` bytes; re-encoding a decoded
    /// session would create a different artifact and therefore a different digest.
    public static func inspect(
        _ data: Data
    ) throws -> PassiveBluetoothFinalizedArtifactIntegrityReport {
        let session = try PassiveBluetoothCaptureJSON.decode(data)
        let valueRecordCount = session.records.reduce(into: 0) { count, record in
            if case .value = record.event {
                count += 1
            }
        }

        return PassiveBluetoothFinalizedArtifactIntegrityReport(
            sha256: sha256Hex(of: data),
            byteCount: data.count,
            captureSessionID: session.id,
            recordCount: session.records.count,
            rawValueRecordCount: valueRecordCount
        )
    }

    /// SHA-256 of the exact artifact bytes, with lowercase hexadecimal encoding.
    public static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { byte in
            String(format: "%02x", byte)
        }.joined()
    }
}
