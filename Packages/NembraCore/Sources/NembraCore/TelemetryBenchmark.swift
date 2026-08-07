import Foundation

public enum TelemetryBenchmarkRejection: Equatable, Sendable {
    case sourceMismatch
    case nonMonotonicTimestamp
}

public enum TelemetryBenchmarkRecordResult: Equatable, Sendable {
    case accepted
    case rejected(TelemetryBenchmarkRejection)
}

/// Compact diagnostics for one telemetry source. This summarizes packet/sample
/// behavior without storing display-interpolated frames as if they were sensor
/// measurements.
///
/// Observation-segment/interruption counts reflect only explicit continuity
/// markers supplied to the collector. They do not prove that physical sampling
/// was continuous between otherwise accepted packets.
public struct TelemetryBenchmarkSummary: Equatable, Sendable {
    public let source: SpeedTelemetrySource
    public let acceptedSampleCount: Int
    public let rejectedSampleCount: Int
    public let observationSegmentCount: Int
    public let knownObservationInterruptionCount: Int
    public let intervalCount: Int
    public let observedDurationSeconds: Double
    public let effectiveSampleRateHertz: Double?
    public let meanIntervalMilliseconds: Double?
    public let minimumIntervalMilliseconds: Double?
    public let maximumIntervalMilliseconds: Double?
    public let intervalJitterStandardDeviationMilliseconds: Double?
    public let duplicateSpeedValueCount: Int
    public let empiricalMinimumNonzeroSpeedStepKilometersPerHour: Double?
    public let deliveryLatencySampleCount: Int
    public let meanDeliveryLatencyMilliseconds: Double?
    public let minimumDeliveryLatencyMilliseconds: Double?
    public let maximumDeliveryLatencyMilliseconds: Double?
    public let deliveryLatencyStandardDeviationMilliseconds: Double?
}

/// Online benchmark accumulator using constant memory.
///
/// This deliberately measures arrival behavior; it does not smooth, resample,
/// or fabricate telemetry. One collector represents exactly one source.
public struct TelemetryBenchmarkCollector: Sendable {
    public let source: SpeedTelemetrySource

    private var acceptedSampleCount = 0
    private var rejectedSampleCount = 0
    private var lastAcceptedUptimeNanoseconds: UInt64?
    private var previousContinuousUptimeNanoseconds: UInt64?
    private var previousContinuousSpeedKilometersPerHour: Double?
    private var observationSegmentCount = 0
    private var knownObservationInterruptionCount = 0
    private var observationInterruptionPending = false
    private var observedDurationNanoseconds: UInt64 = 0
    private var duplicateSpeedValueCount = 0
    private var minimumNonzeroSpeedStepKilometersPerHour: Double?
    private var intervalMoments = RunningMoments()
    private var latencyMoments = RunningMoments()

    public init(source: SpeedTelemetrySource) {
        self.source = source
    }

    /// Marks a known break in observation continuity, such as a disconnect,
    /// subscription interruption, or other source-lifecycle gap.
    ///
    /// The next accepted sample begins a new observation segment. No interval or
    /// speed-step comparison is fabricated across the missing evidence. The
    /// last accepted uptime remains the chronology anchor, so a delayed stale
    /// callback cannot become fresh merely because continuity was interrupted.
    /// Repeated marks before new accepted evidence are idempotent.
    public mutating func markContinuityInterruption() {
        guard acceptedSampleCount > 0, !observationInterruptionPending else { return }

        knownObservationInterruptionCount += 1
        observationInterruptionPending = true
        previousContinuousUptimeNanoseconds = nil
        previousContinuousSpeedKilometersPerHour = nil
    }

    @discardableResult
    public mutating func record(_ sample: SpeedTelemetrySample) -> TelemetryBenchmarkRecordResult {
        guard sample.source == source else {
            rejectedSampleCount += 1
            return .rejected(.sourceMismatch)
        }

        if let lastAcceptedUptimeNanoseconds,
           sample.receivedAtUptimeNanoseconds <= lastAcceptedUptimeNanoseconds {
            rejectedSampleCount += 1
            return .rejected(.nonMonotonicTimestamp)
        }

        if acceptedSampleCount == 0 || observationInterruptionPending {
            observationSegmentCount += 1
            observationInterruptionPending = false
        }

        if let previousContinuousUptimeNanoseconds {
            let intervalNanoseconds = sample.receivedAtUptimeNanoseconds - previousContinuousUptimeNanoseconds
            observedDurationNanoseconds += intervalNanoseconds
            intervalMoments.record(Double(intervalNanoseconds) / 1_000_000)
        }

        let speedKPH = sample.kilometersPerHour
        if let previousContinuousSpeedKilometersPerHour {
            let delta = abs(speedKPH - previousContinuousSpeedKilometersPerHour)
            if delta <= 1e-9 {
                duplicateSpeedValueCount += 1
            } else if minimumNonzeroSpeedStepKilometersPerHour.map({ delta < $0 }) ?? true {
                minimumNonzeroSpeedStepKilometersPerHour = delta
            }
        }

        if let latency = sample.deliveryLatencyMilliseconds {
            latencyMoments.record(latency)
        }

        acceptedSampleCount += 1
        lastAcceptedUptimeNanoseconds = sample.receivedAtUptimeNanoseconds
        previousContinuousUptimeNanoseconds = sample.receivedAtUptimeNanoseconds
        previousContinuousSpeedKilometersPerHour = speedKPH
        return .accepted
    }

    public var summary: TelemetryBenchmarkSummary {
        let durationSeconds = Double(observedDurationNanoseconds) / 1_000_000_000

        let rate: Double?
        if intervalMoments.count > 0, durationSeconds > 0 {
            rate = Double(intervalMoments.count) / durationSeconds
        } else {
            rate = nil
        }

        return TelemetryBenchmarkSummary(
            source: source,
            acceptedSampleCount: acceptedSampleCount,
            rejectedSampleCount: rejectedSampleCount,
            observationSegmentCount: observationSegmentCount,
            knownObservationInterruptionCount: knownObservationInterruptionCount,
            intervalCount: intervalMoments.count,
            observedDurationSeconds: durationSeconds,
            effectiveSampleRateHertz: rate,
            meanIntervalMilliseconds: intervalMoments.meanOrNil,
            minimumIntervalMilliseconds: intervalMoments.minimum,
            maximumIntervalMilliseconds: intervalMoments.maximum,
            intervalJitterStandardDeviationMilliseconds: intervalMoments.populationStandardDeviation,
            duplicateSpeedValueCount: duplicateSpeedValueCount,
            empiricalMinimumNonzeroSpeedStepKilometersPerHour: minimumNonzeroSpeedStepKilometersPerHour,
            deliveryLatencySampleCount: latencyMoments.count,
            meanDeliveryLatencyMilliseconds: latencyMoments.meanOrNil,
            minimumDeliveryLatencyMilliseconds: latencyMoments.minimum,
            maximumDeliveryLatencyMilliseconds: latencyMoments.maximum,
            deliveryLatencyStandardDeviationMilliseconds: latencyMoments.populationStandardDeviation
        )
    }
}

private struct RunningMoments: Sendable {
    private(set) var count = 0
    private(set) var mean = 0.0
    private var squaredDeviationSum = 0.0
    private(set) var minimum: Double?
    private(set) var maximum: Double?

    mutating func record(_ value: Double) {
        count += 1
        let delta = value - mean
        mean += delta / Double(count)
        let deltaFromNewMean = value - mean
        squaredDeviationSum += delta * deltaFromNewMean
        minimum = minimum.map { Swift.min($0, value) } ?? value
        maximum = maximum.map { Swift.max($0, value) } ?? value
    }

    var meanOrNil: Double? {
        count > 0 ? mean : nil
    }

    var populationStandardDeviation: Double? {
        guard count > 0 else { return nil }
        return sqrt(squaredDeviationSum / Double(count))
    }
}
