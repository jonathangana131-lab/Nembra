import Foundation

public enum PeakSpeedPolicyError: Error, Equatable, Sendable {
    case nonAuthoritativeSource
    case invalidMaximumSpeedAccuracy
}

/// Selects exactly one authoritative source for observed peak-speed evidence.
/// No production source or accuracy threshold is implied by this type.
public struct PeakSpeedPolicy: Equatable, Sendable {
    public let source: SpeedTelemetrySource
    public let maximumSpeedAccuracyMetersPerSecond: Double?

    public init(
        source: SpeedTelemetrySource,
        maximumSpeedAccuracyMetersPerSecond: Double? = nil
    ) throws {
        guard source != .motionAssist else {
            throw PeakSpeedPolicyError.nonAuthoritativeSource
        }
        if let maximumSpeedAccuracyMetersPerSecond {
            guard maximumSpeedAccuracyMetersPerSecond.isFinite,
                  maximumSpeedAccuracyMetersPerSecond >= 0 else {
                throw PeakSpeedPolicyError.invalidMaximumSpeedAccuracy
            }
        }
        self.source = source
        self.maximumSpeedAccuracyMetersPerSecond = maximumSpeedAccuracyMetersPerSecond
    }
}

public struct PeakSpeedMeasurement: Equatable, Sendable {
    public let source: SpeedTelemetrySource
    public let metersPerSecond: Double
    public let receivedAtUptimeNanoseconds: UInt64
    public let speedAccuracyMetersPerSecond: Double?

    init(sample: SpeedTelemetrySample) {
        self.source = sample.source
        self.metersPerSecond = sample.metersPerSecond
        self.receivedAtUptimeNanoseconds = sample.receivedAtUptimeNanoseconds
        self.speedAccuracyMetersPerSecond = sample.speedAccuracyMetersPerSecond
    }

    public var kilometersPerHour: Double {
        metersPerSecond * 3.6
    }
}

/// This describes continuity of the accepted observation stream, not whether the
/// sampled value equals the scooter's unknowable continuous-time physical peak.
public enum PeakSpeedObservationContinuity: String, Codable, Equatable, Sendable {
    case uninterruptedAcceptedObservations
    case partialAcceptedObservations
}

public enum PeakSpeedInterruption: Equatable, Sendable {
    case vehicleConnectionLost
    case applicationLifecycleInterrupted
    case sourceUnavailable
}

public enum PeakSpeedRecordRejection: Equatable, Sendable {
    case nonAuthoritativeSample
    case sourceMismatch
    case nonIncreasingTimestamp
    case speedAccuracyUnavailable
    case speedAccuracyExceeded(maximum: Double, actual: Double)
}

public enum PeakSpeedRecordResult: Equatable, Sendable {
    case peakUpdated(PeakSpeedMeasurement)
    case acceptedWithoutPeakChange
    case rejected(PeakSpeedRecordRejection)
}

/// Session-local highest accepted speed observation plus evidence-quality flags.
///
/// `peak` means highest accepted measurement from the selected source. It does
/// not claim the exact continuous physical maximum between samples.
public struct PeakSpeedEvidence: Equatable, Sendable {
    public let peak: PeakSpeedMeasurement
    public let acceptedSampleCount: Int
    public let qualityRejectedSampleCount: Int
    public let knownInterruptionCount: Int
    public let continuity: PeakSpeedObservationContinuity
}

public struct PeakSpeedEvidenceAccumulator: Sendable {
    public let policy: PeakSpeedPolicy

    private var peak: PeakSpeedMeasurement?
    /// Advances for every monotonic authoritative observation from the selected
    /// source, including observations later rejected by accuracy policy. A low-
    /// quality sample is still real ordering evidence and cannot be erased so an
    /// older callback can later masquerade as fresh.
    private var lastObservedUptimeNanoseconds: UInt64?
    private var acceptedSampleCount = 0
    private var qualityRejectedSampleCount = 0
    private var knownInterruptionCount = 0

    public init(policy: PeakSpeedPolicy) {
        self.policy = policy
    }

    @discardableResult
    public mutating func record(_ sample: SpeedTelemetrySample) -> PeakSpeedRecordResult {
        guard sample.isAuthoritativeMeasurement else {
            return .rejected(.nonAuthoritativeSample)
        }
        guard sample.source == policy.source else {
            return .rejected(.sourceMismatch)
        }

        if let lastObservedUptimeNanoseconds,
           sample.receivedAtUptimeNanoseconds <= lastObservedUptimeNanoseconds {
            qualityRejectedSampleCount += 1
            return .rejected(.nonIncreasingTimestamp)
        }
        lastObservedUptimeNanoseconds = sample.receivedAtUptimeNanoseconds

        if let maximum = policy.maximumSpeedAccuracyMetersPerSecond {
            guard let actual = sample.speedAccuracyMetersPerSecond else {
                qualityRejectedSampleCount += 1
                return .rejected(.speedAccuracyUnavailable)
            }
            guard actual <= maximum else {
                qualityRejectedSampleCount += 1
                return .rejected(.speedAccuracyExceeded(maximum: maximum, actual: actual))
            }
        }

        acceptedSampleCount += 1
        let measurement = PeakSpeedMeasurement(sample: sample)

        if peak.map({ measurement.metersPerSecond > $0.metersPerSecond }) ?? true {
            peak = measurement
            return .peakUpdated(measurement)
        }

        return .acceptedWithoutPeakChange
    }

    /// Call when the selected observation stream has a known continuity break.
    /// The already observed peak remains valid as an observed value, but the
    /// session can no longer claim uninterrupted observation coverage.
    public mutating func recordInterruption(_ interruption: PeakSpeedInterruption) {
        _ = interruption
        knownInterruptionCount += 1
    }

    public var evidence: PeakSpeedEvidence? {
        guard let peak else { return nil }
        let continuity: PeakSpeedObservationContinuity =
            (qualityRejectedSampleCount == 0 && knownInterruptionCount == 0)
                ? .uninterruptedAcceptedObservations
                : .partialAcceptedObservations

        return PeakSpeedEvidence(
            peak: peak,
            acceptedSampleCount: acceptedSampleCount,
            qualityRejectedSampleCount: qualityRejectedSampleCount,
            knownInterruptionCount: knownInterruptionCount,
            continuity: continuity
        )
    }

    public mutating func reset() {
        peak = nil
        lastObservedUptimeNanoseconds = nil
        acceptedSampleCount = 0
        qualityRejectedSampleCount = 0
        knownInterruptionCount = 0
    }
}
