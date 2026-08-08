import CryptoKit
import Foundation
import NembraCore

/// Fail-closed target selection errors for one versioned passive-capture
/// artifact. Automatic selection is allowed only when target-attributable
/// evidence identifies exactly one peripheral.
public enum PassiveBluetoothTuyaCaptureArtifactReportError: Error, Equatable, Sendable {
    case noAttributablePeripheral
    case ambiguousPeripherals([String])
    case requestedPeripheralNotPresent(requested: String, available: [String])
}

extension PassiveBluetoothTuyaCaptureArtifactReportError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .noAttributablePeripheral:
            "capture contains no target-attributable connection/GATT/value peripheral evidence"
        case let .ambiguousPeripherals(identifiers):
            "capture contains multiple attributable peripherals; pass --peripheral with one exact identifier: \(identifiers.joined(separator: ", "))"
        case let .requestedPeripheralNotPresent(requested, available):
            "requested peripheral \(requested) is not present in target-attributable capture evidence; available: \(available.joined(separator: ", "))"
        }
    }
}

/// Durable wrapper that cryptographically binds a deterministic framing report
/// to the exact capture JSON bytes that produced it.
///
/// The SHA-256 is an artifact-integrity/provenance identifier only. It does not
/// authenticate the scooter, prove who recorded the capture, or verify any ES80
/// protocol/telemetry meaning.
public struct PassiveBluetoothTuyaCaptureArtifactReport: Equatable, Codable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let sourceArtifact: SourceArtifactSummary
    public let analysis: PassiveBluetoothTuyaCaptureReport

    public struct SourceArtifactSummary: Equatable, Codable, Sendable {
        public let sha256: String
        public let byteCount: Int
    }

    public func jsonData(prettyPrinted: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try encoder.encode(self)
    }
}

public enum PassiveBluetoothTuyaCaptureArtifactReportBuilder {
    /// Validates the exact source-artifact byte count before decode, then decodes
    /// the versioned capture artifact, selects one target without guessing, runs
    /// the bounded candidate analyzer, and binds the output to the original input
    /// bytes with SHA-256.
    ///
    /// `maximumArtifactBytes` is an offline process-safety ceiling only. It is not
    /// an ES80 protocol/session/message-size claim. File-based callers should use
    /// `PassiveBluetoothCaptureArtifactInputPolicy.readExactBytes` first so the
    /// source `Data` itself is also bounded before materialization.
    public static func make(
        captureJSON: Data,
        peripheralIdentifier requestedPeripheralIdentifier: String? = nil,
        policy: TuyaCandidateFragmentReassemblyPolicy,
        maximumArtifactBytes: Int = PassiveBluetoothCaptureArtifactInputPolicy.defaultMaximumArtifactBytes
    ) throws -> PassiveBluetoothTuyaCaptureArtifactReport {
        try PassiveBluetoothCaptureArtifactInputPolicy.validateByteCount(
            captureJSON.count,
            maximumBytes: maximumArtifactBytes
        )

        let session = try PassiveBluetoothCaptureJSON.decode(captureJSON)
        let available = PassiveBluetoothTuyaCaptureReportBuilder
            .attributablePeripheralIdentifiers(in: session)
        let selected = try selectPeripheral(
            requested: requestedPeripheralIdentifier,
            available: available
        )
        let analysis = try PassiveBluetoothTuyaCaptureReportBuilder.make(
            session: session,
            peripheralIdentifier: selected,
            policy: policy
        )

        return PassiveBluetoothTuyaCaptureArtifactReport(
            schemaVersion: PassiveBluetoothTuyaCaptureArtifactReport.currentSchemaVersion,
            sourceArtifact: .init(
                sha256: sha256Hex(of: captureJSON),
                byteCount: captureJSON.count
            ),
            analysis: analysis
        )
    }

    public static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { byte in
            String(format: "%02x", byte)
        }.joined()
    }

    private static func selectPeripheral(
        requested: String?,
        available: [String]
    ) throws -> String {
        if let requested {
            guard available.contains(requested) else {
                throw PassiveBluetoothTuyaCaptureArtifactReportError
                    .requestedPeripheralNotPresent(
                        requested: requested,
                        available: available
                    )
            }
            return requested
        }

        switch available.count {
        case 0:
            throw PassiveBluetoothTuyaCaptureArtifactReportError.noAttributablePeripheral
        case 1:
            return available[0]
        default:
            throw PassiveBluetoothTuyaCaptureArtifactReportError.ambiguousPeripherals(available)
        }
    }
}
