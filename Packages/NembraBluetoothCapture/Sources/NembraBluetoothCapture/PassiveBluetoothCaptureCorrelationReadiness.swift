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
    /// explicitly selected target without crossing a known raw-byte continuity break.
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
    /// evidence inside its requested time window and the same known byte-continuity segment.
    case noMarkerLocalTargetValues
}

/// Operator-facing structural summary for one immutable passive-capture artifact.
///
/// Counts remain descriptive evidence only. In particular, `supportedMarkerCount`
/// means only that a marker has at least one nearby target value callback after
/// the authoritative raw-byte continuity policy is applied under the retained
/// lookback/lookahead window. It is not protocol-field confidence, repeatability,
/// payload decoding, or physical hardware verification.
public struct PassiveBluetoothCaptureCorrelationReadinessReport: Equatable, Sendable {
    public let disposition: PassiveBluetoothCaptureCorrelationReadinessDisposition
    public let peripheralIdentifier: String
    public let sessionRecordCount: Int
    public let stockAppMarkerCount: Int
    public let supportedMarkerCount: Int
    public let targetValueObservationCount: Int

    /// Backward-compatible descriptive count from the original readiness API.
    ///
    /// This counts explicit disconnects attributed to the selected target plus
    /// generic capture interruptions. It is useful attribution provenance, but it
    /// is NOT the raw-byte continuity authority because another peripheral's
    /// structured disconnect is still a capture-wide known byte-continuity break.
    public let targetContinuityBreakCount: Int

    /// Number of captured events that NembraCore classifies as raw-byte continuity breaks.
    ///
    /// This deliberately follows `PassiveBluetoothCaptureEvent.breaksByteContinuity`
    /// for the complete artifact. Identity attribution is a separate question: a
    /// structured disconnect from another peripheral still proves that the capture
    /// has a known raw-byte continuity break and must not be erased here.
    public let knownByteContinuityBreakCount: Int

    public let correlationLookbackNanoseconds: UInt64
    public let correlationLookaheadNanoseconds: UInt64
    public let distinctMarkerFields: Set<String>
    public let targetValueOrigins: Set<PassiveBluetoothValueOrigin>

    /// Readiness is evidence-derived authority, not a scalar value callers may
    /// mint. Keep construction inside this file so every public report originates
    /// from `PassiveBluetoothCaptureCorrelationReadiness.assess(...)`.
    fileprivate init(
        disposition: PassiveBluetoothCaptureCorrelationReadinessDisposition,
        peripheralIdentifier: String,
        sessionRecordCount: Int,
        stockAppMarkerCount: Int,
        supportedMarkerCount: Int,
        targetValueObservationCount: Int,
        targetContinuityBreakCount: Int,
        knownByteContinuityBreakCount: Int,
        correlationLookbackNanoseconds: UInt64,
        correlationLookaheadNanoseconds: UInt64,
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
        self.knownByteContinuityBreakCount = knownByteContinuityBreakCount
        self.correlationLookbackNanoseconds = correlationLookbackNanoseconds
        self.correlationLookaheadNanoseconds = correlationLookaheadNanoseconds
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

/// Produces a conservative target-scoped readiness summary.
///
/// Target attribution and coarse time-window construction stay delegated to
/// `PassiveBluetoothCorrelation`. This layer then reapplies NembraCore's stronger,
/// capture-wide raw-byte continuity authority before any candidate can count as
/// readiness support. That is intentional: a downstream readiness classifier may
/// become more conservative than a legacy target-scoped research convenience, but
/// it must never weaken an upstream known continuity break.
public enum PassiveBluetoothCaptureCorrelationReadiness {
    public static func assess(
        _ session: PassiveBluetoothCaptureSession,
        peripheralIdentifier: String,
        lookbackNanoseconds: UInt64 = 2_000_000_000,
        lookaheadNanoseconds: UInt64 = 2_000_000_000
    ) -> PassiveBluetoothCaptureCorrelationReadinessReport {
        let isBlankPeripheralIdentifier = peripheralIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        let sessionSummary = summarizeSession(
            session,
            peripheralIdentifier: peripheralIdentifier
        )

        guard !isBlankPeripheralIdentifier,
              let windows = PassiveBluetoothCorrelation.windows(
                in: session,
                peripheralIdentifier: peripheralIdentifier,
                lookbackNanoseconds: lookbackNanoseconds,
                lookaheadNanoseconds: lookaheadNanoseconds
              ) else {
            return makeReport(
                disposition: .invalidPeripheralScope,
                peripheralIdentifier: peripheralIdentifier,
                session: session,
                sessionSummary: sessionSummary,
                supportedMarkerCount: 0,
                lookbackNanoseconds: lookbackNanoseconds,
                lookaheadNanoseconds: lookaheadNanoseconds
            )
        }

        let segmentBySequence = byteContinuitySegmentBySequence(in: session)
        let supportedMarkerCount = windows.reduce(into: 0) { count, window in
            guard let markerSegment = segmentBySequence[window.markerSequenceNumber] else {
                return
            }

            let hasContinuitySafeCandidate = window.candidates.contains { candidate in
                segmentBySequence[candidate.sequenceNumber] == markerSegment
            }
            if hasContinuitySafeCandidate {
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
            peripheralIdentifier: peripheralIdentifier,
            session: session,
            sessionSummary: sessionSummary,
            supportedMarkerCount: supportedMarkerCount,
            lookbackNanoseconds: lookbackNanoseconds,
            lookaheadNanoseconds: lookaheadNanoseconds
        )
    }

    private struct SessionSummary {
        var stockAppMarkerCount = 0
        var distinctMarkerFields: Set<String> = []
        var targetValueObservationCount = 0
        var targetContinuityBreakCount = 0
        var knownByteContinuityBreakCount = 0
        var targetValueOrigins: Set<PassiveBluetoothValueOrigin> = []
    }

    private static func summarizeSession(
        _ session: PassiveBluetoothCaptureSession,
        peripheralIdentifier: String
    ) -> SessionSummary {
        var summary = SessionSummary()

        for record in session.records {
            if record.event.breaksByteContinuity {
                summary.knownByteContinuityBreakCount += 1
            }

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

    /// Assigns every immutable record to the capture-wide raw-byte continuity
    /// segment established by NembraCore. The breaking event closes the segment
    /// before the following record, matching the capture/analyzer convention.
    private static func byteContinuitySegmentBySequence(
        in session: PassiveBluetoothCaptureSession
    ) -> [UInt64: Int] {
        var segment = 0
        var result: [UInt64: Int] = [:]
        result.reserveCapacity(session.records.count)

        for record in session.records {
            result[record.sequenceNumber] = segment
            if record.event.breaksByteContinuity {
                segment += 1
            }
        }

        return result
    }

    private static func makeReport(
        disposition: PassiveBluetoothCaptureCorrelationReadinessDisposition,
        peripheralIdentifier: String,
        session: PassiveBluetoothCaptureSession,
        sessionSummary: SessionSummary,
        supportedMarkerCount: Int,
        lookbackNanoseconds: UInt64,
        lookaheadNanoseconds: UInt64
    ) -> PassiveBluetoothCaptureCorrelationReadinessReport {
        PassiveBluetoothCaptureCorrelationReadinessReport(
            disposition: disposition,
            peripheralIdentifier: peripheralIdentifier,
            sessionRecordCount: session.records.count,
            stockAppMarkerCount: sessionSummary.stockAppMarkerCount,
            supportedMarkerCount: supportedMarkerCount,
            targetValueObservationCount: sessionSummary.targetValueObservationCount,
            targetContinuityBreakCount: sessionSummary.targetContinuityBreakCount,
            knownByteContinuityBreakCount: sessionSummary.knownByteContinuityBreakCount,
            correlationLookbackNanoseconds: lookbackNanoseconds,
            correlationLookaheadNanoseconds: lookaheadNanoseconds,
            distinctMarkerFields: sessionSummary.distinctMarkerFields,
            targetValueOrigins: sessionSummary.targetValueOrigins
        )
    }
}
