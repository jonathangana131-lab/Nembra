import Foundation

public enum TelemetryBenchmarkRejection: Equatable, Sendable {
    case sourceMismatch
    case nonMonotonicTimestamp
    case nonFiniteSpeedConversion
}

public enum TelemetryBenchmarkRecordResult: Equatable, Sendable {
    case accepted
    case rejected(TelemetryBenchmarkRejection)
}

/// Compact diagnostics for one telemetry source. This summarizes packet/sample
/// behavior without storing display-interpolated frames as if they were sensor
/// measurements.
public struct TelemetryBenchmarkSummary: Equatable, Sendable {
    public let source: SpeedTelemetrySource
    public let acceptedSampleCount: Int
    public let rejectedSampleCount: Int
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
    private var firstUptimeNanoseconds: UInt64?
    private var previousUptimeNanoseconds: UInt64?
    private var previousSpeedKilometersPerHour: Double?
    private var duplicateSpeedValueCount = 0
    private var minimumNonzeroSpeedStepKilometersPerHour: Double?
    private var intervalMoments = RunningMoments()
    private var latencyMoments = RunningMoments()

    public init(source: SpeedTelemetrySource) {
        self.source = source
    }

    @discardableResult
    public mutating func record(_ sample: SpeedTelemetrySample) -> TelemetryBenchmarkRecordResult {
        guard sample.source == source else {
            rejectedSampleCount += 1
            return .rejected(.sourceMismatch)
        }

        if let previousUptimeNanoseconds,
           sample.receivedAtUptimeNanoseconds <= previousUptimeNanoseconds {
            rejectedSampleCount += 1
            return .rejected(.nonMonotonicTimestamp)
        }

        // `SpeedTelemetrySample` guarantees that its stored m/s value is finite,
        // but multiplying a very large finite Double by the km/h conversion
        // factor can still overflow. Benchmark diagnostics must never accept an
        // infinite derived speed or let `inf - inf` become NaN resolution evidence.
        let speedKPH = sample.kilometersPerHour
        guard speedKPH.isFinite else {
            rejectedSampleCount += 1
            return .rejected(.nonFiniteSpeedConversion)
        }

        if firstUptimeNanoseconds == nil {
            firstUptimeNanoseconds = sample.receivedAtUptimeNanoseconds
        }

        if let previousUptimeNanoseconds {
            let intervalNanoseconds = sample.receivedAtUptimeNanoseconds - previousUptimeNanoseconds
            intervalMoments.record(Double(intervalNanoseconds) / 1_000_000)
        }

        if let previousSpeedKilometersPerHour {
            let delta = abs(speedKPH - previousSpeedKilometersPerHour)
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
        previousUptimeNanoseconds = sample.receivedAtUptimeNanoseconds
        previousSpeedKilometersPerHour = speedKPH
        return .accepted
    }

    public var summary: TelemetryBenchmarkSummary {
        let durationSeconds: Double
        if let firstUptimeNanoseconds, let previousUptimeNanoseconds {
            durationSeconds = Double(previousUptimeNanoseconds - firstUptimeNanoseconds) / 1_000_000_000
        } else {
            durationSeconds = 0
        }

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
