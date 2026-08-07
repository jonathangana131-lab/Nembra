import Foundation
import NembraCore

/// Structural readiness for target-scoped offline stock-app correlation.
///
/// This describes whether an immutable passive-capture artifact contains enough
/// local evidence to run meaningful correlation tooling. It never verifies the
/// selected peripheral as an AOVOPRO ES80, assigns protocol semantics, or turns
/// temporal proximity into a decoded field claim.
public enum PassiveBluetoothCaptureCorrelationReadinessDisposition: String, Equatable, Sendable {
    /// At least one human stock-app marker has nearby raw value evidence from the
    /// explicitly selected target inside the parent's continuity-safe window.
    case readyForOfflineCorrelation

    /// The requested target is blank or absent from correlation-attributable
    /// connection/GATT/value evidence in this artifact.
    case invalidPeripheralScope

    /// The target is attributable, but the artifact contains no stock-app marker.
    case noStockAppMarkers

    /// The target is attributable and markers exist, but no raw value observation
    /// from that target exists anywhere in the artifact.
    case noTargetValueObservations

    /// Target values and markers both exist, but no marker has target value
    /// evidence inside its requested continuity-safe correlation window.
    case noMarkerLocalTargetValues
}

/// Operator-facing structural summary for one immutable passive-capture artifact.
///
/// Counts remain descriptive evidence only. In particular, `supportedMarkerCount`
/// means only that a marker has at least one nearby target value callback after
/// continuity filtering. It is not protocol-field confidence, repeatability,
/// payload decoding, or physical hardware verification.
public struct PassiveBluetoothCaptureCorrelationReadinessReport: Equatable, Sendable {
    public let disposition: PassiveBluetoothCaptureCorrelationReadinessDisposition
    public let peripheralIdentifier: String
    public let sessionRecordCount: Int
    public let stockAppMarkerCount: Int
    public let supportedMarkerCount: Int
    public let targetValueObservationCount: Int
    public let targetContinuityBreakCount: Int
    public let distinctMarkerFields: Set<String>
    public let targetValueOrigins: Set<PassiveBluetoothValueOrigin>

    public init(
        disposition: PassiveBluetoothCaptureCorrelationReadinessDisposition,
        peripheralIdentifier: String,
        sessionRecordCount: Int,
        stockAppMarkerCount: Int,
        supportedMarkerCount: Int,
        targetValueObservationCount: Int,
        targetContinuityBreakCount: Int,
        distinctMarkerFields: Set<String>,
        targetValueOrigins: Set<PassiveBluetoothValueOrigin>
    ) {
        self.disposition = disposition
        self.peripheralIdentifier = peripheralIdentifier
        self.sessionRecordCount = sessionRecordCount
        self.stockAppMarkerCount = stockAppMarkerCount
        self.supportedMarkerCount = supportedMarkerCount
        self.targetValueObservationCount = targetValueObservationCount
        self.targetContinuityBreakCount = targetContinuityBreakCount
        self.distinctMarkerFields = distinctMarkerFields
        self.targetValueOrigins = targetValueOrigins
    }

    public var unsupportedMarkerCount: Int {
        max(0, stockAppMarkerCount - supportedMarkerCount)
    }

    public var markerSupportFraction: Double {
        guard stockAppMarkerCount > 0 else { return 0 }
        return Double(supportedMarkerCount) / Double(stockAppMarkerCount)
    }

    public var isReadyForOfflineCorrelation: Bool {
        disposition == .readyForOfflineCorrelation
    }
}

/// Produces a conservative target-scoped readiness summary by reusing the parent
/// correlation authority instead of rebuilding target attribution or continuity
/// semantics in a second layer.
public enum PassiveBluetoothCaptureCorrelationReadiness {
    public static func assess(
        _ session: PassiveBluetoothCaptureSession,
        peripheralIdentifier: String,
        lookbackNanoseconds: UInt64 = 2_000_000_000,
        lookaheadNanoseconds: UInt64 = 2_000_000_000
    ) -> PassiveBluetoothCaptureCorrelationReadinessReport {
        let normalizedPeripheralIdentifier = peripheralIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let sessionSummary = summarizeSession(
            session,
            peripheralIdentifier: normalizedPeripheralIdentifier
        )

        guard !normalizedPeripheralIdentifier.isEmpty,
              let windows = PassiveBluetoothCorrelation.windows(
                in: session,
                peripheralIdentifier: normalizedPeripheralIdentifier,
                lookbackNanoseconds: lookbackNanoseconds,
                lookaheadNanoseconds: lookaheadNanoseconds
              ) else {
            return makeReport(
                disposition: .invalidPeripheralScope,
                peripheralIdentifier: normalizedPeripheralIdentifier,
                session: session,
                sessionSummary: sessionSummary,
                supportedMarkerCount: 0
            )
        }

        let supportedMarkerCount = windows.reduce(into: 0) { count, window in
            if !window.candidates.isEmpty {
                count += 1
            }
        }

        let disposition: PassiveBluetoothCaptureCorrelationReadinessDisposition
        if windows.isEmpty {
            disposition = .noStockAppMarkers
        } else if sessionSummary.targetValueObservationCount == 0 {
            disposition = .noTargetValueObservations
        } else if supportedMarkerCount == 0 {
            disposition = .noMarkerLocalTargetValues
        } else {
            disposition = .readyForOfflineCorrelation
        }

        return makeReport(
            disposition: disposition,
            peripheralIdentifier: normalizedPeripheralIdentifier,
            session: session,
            sessionSummary: sessionSummary,
            supportedMarkerCount: supportedMarkerCount
        )
    }

    private struct SessionSummary {
        var stockAppMarkerCount = 0
        var distinctMarkerFields: Set<String> = []
        var targetValueObservationCount = 0
        var targetContinuityBreakCount = 0
        var targetValueOrigins: Set<PassiveBluetoothValueOrigin> = []
    }

    private static func summarizeSession(
        _ session: PassiveBluetoothCaptureSession,
        peripheralIdentifier: String
    ) -> SessionSummary {
        var summary = SessionSummary()

        for record in session.records {
            switch record.event {
            case let .stockAppState(marker):
                summary.stockAppMarkerCount += 1
                summary.distinctMarkerFields.insert(marker.field)

            case let .value(value) where value.peripheralIdentifier == peripheralIdentifier:
                summary.targetValueObservationCount += 1
                summary.targetValueOrigins.insert(value.origin)

            case let .connection(observation)
                where observation.state == .disconnected
                    && observation.peripheralIdentifier == peripheralIdentifier:
                summary.targetContinuityBreakCount += 1

            case .interruption:
                summary.targetContinuityBreakCount += 1

            default:
                continue
            }
        }

        return summary
    }

    private static func makeReport(
        disposition: PassiveBluetoothCaptureCorrelationReadinessDisposition,
        peripheralIdentifier: String,
        session: PassiveBluetoothCaptureSession,
        sessionSummary: SessionSummary,
        supportedMarkerCount: Int
    ) -> PassiveBluetoothCaptureCorrelationReadinessReport {
        PassiveBluetoothCaptureCorrelationReadinessReport(
            disposition: disposition,
            peripheralIdentifier: peripheralIdentifier,
            sessionRecordCount: session.records.count,
            stockAppMarkerCount: sessionSummary.stockAppMarkerCount,
            supportedMarkerCount: supportedMarkerCount,
            targetValueObservationCount: sessionSummary.targetValueObservationCount,
            targetContinuityBreakCount: sessionSummary.targetContinuityBreakCount,
            distinctMarkerFields: sessionSummary.distinctMarkerFields,
            targetValueOrigins: sessionSummary.targetValueOrigins
        )
    }
}
