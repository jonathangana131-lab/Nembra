import Foundation
import NembraCore

/// Batch entry point for the repeated-correlation analyzer.
///
/// One call discovers the stock-app fields actually present in the immutable
/// capture and returns one report per case-insensitive field. This is a research
/// convenience only: batching does not strengthen temporal correlation into a
/// decoded GATT/Tuya field claim.
public enum PassiveBluetoothRepeatedCorrelationBatch {
    /// Analyze every observed stock-app field when the capture has an
    /// unambiguous GATT/value peripheral scope.
    public static func analyzeAllObservedFields(
        in session: PassiveBluetoothCaptureSession,
        lookbackNanoseconds: UInt64 = 2_000_000_000,
        lookaheadNanoseconds: UInt64 = 2_000_000_000
    ) -> [PassiveBluetoothRepeatedCorrelationReport] {
        observedFields(in: session).map { field in
            PassiveBluetoothRepeatedCorrelation.analyze(
                session,
                field: field,
                lookbackNanoseconds: lookbackNanoseconds,
                lookaheadNanoseconds: lookaheadNanoseconds
            )
        }
    }

    /// Analyze every observed stock-app field against one explicitly selected
    /// CoreBluetooth peripheral identifier in an imported/mixed capture.
    public static func analyzeAllObservedFields(
        in session: PassiveBluetoothCaptureSession,
        peripheralIdentifier: String,
        lookbackNanoseconds: UInt64 = 2_000_000_000,
        lookaheadNanoseconds: UInt64 = 2_000_000_000
    ) -> [PassiveBluetoothRepeatedCorrelationReport] {
        observedFields(in: session).map { field in
            PassiveBluetoothRepeatedCorrelation.analyze(
                session,
                peripheralIdentifier: peripheralIdentifier,
                field: field,
                lookbackNanoseconds: lookbackNanoseconds,
                lookaheadNanoseconds: lookaheadNanoseconds
            )
        }
    }

    /// Preserve the first observed spelling for display/audit traceability while
    /// grouping field names with the same case-insensitive semantics as the
    /// underlying per-field analyzer.
    private static func observedFields(
        in session: PassiveBluetoothCaptureSession
    ) -> [String] {
        var fields: [String] = []

        for record in session.records {
            guard case let .stockAppState(marker) = record.event else { continue }
            guard !fields.contains(where: {
                $0.caseInsensitiveCompare(marker.field) == .orderedSame
            }) else {
                continue
            }
            fields.append(marker.field)
        }

        return fields.sorted { lhs, rhs in
            let insensitive = lhs.caseInsensitiveCompare(rhs)
            if insensitive != .orderedSame {
                return insensitive == .orderedAscending
            }
            return lhs < rhs
        }
    }
}
