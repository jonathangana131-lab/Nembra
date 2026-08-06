import Foundation

public enum AccelerationRunPolicyError: Error, Equatable, Sendable {
    case invalidTargetSpeed
    case invalidStationaryThreshold
    case invalidMaximumSpeedAccuracy
}

public struct AccelerationRunPolicy: Equatable, Sendable {
    public let targetMetersPerSecond: Double
    public let stationaryMaximumMetersPerSecond: Double
    public let requiredSource: SpeedTelemetrySource?
    public let maximumSpeedAccuracyMetersPerSecond: Double?

    public init(
        targetMetersPerSecond: Double,
        stationaryMaximumMetersPerSecond: Double = 0.5,
        requiredSource: SpeedTelemetrySource? = nil,
        maximumSpeedAccuracyMetersPerSecond: Double? = nil
    ) throws {
        guard targetMetersPerSecond.isFinite, targetMetersPerSecond > 0 else {
            throw AccelerationRunPolicyError.invalidTargetSpeed
        }
        guard stationaryMaximumMetersPerSecond.isFinite,
              stationaryMaximumMetersPerSecond >= 0,
              stationaryMaximumMetersPerSecond < targetMetersPerSecond else {
            throw AccelerationRunPolicyError.invalidStationaryThreshold
        }
        if let maximumSpeedAccuracyMetersPerSecond {
            guard maximumSpeedAccuracyMetersPerSecond.isFinite,
                  maximumSpeedAccuracyMetersPerSecond >= 0 else {
                throw AccelerationRunPolicyError.invalidMaximumSpeedAccuracy
            }
        }

        self.targetMetersPerSecond = targetMetersPerSecond
        self.stationaryMaximumMetersPerSecond = stationaryMaximumMetersPerSecond
        self.requiredSource = requiredSource
        self.maximumSpeedAccuracyMetersPerSecond = maximumSpeedAccuracyMetersPerSecond
    }
}

public struct AccelerationTimingWindow: Equatable, Sendable {
    public let earliestUptimeNanoseconds: UInt64
    public let latestUptimeNanoseconds: UInt64

    public init(earliestUptimeNanoseconds: UInt64, latestUptimeNanoseconds: UInt64) {
        precondition(latestUptimeNanoseconds >= earliestUptimeNanoseconds)
        self.earliestUptimeNanoseconds = earliestUptimeNanoseconds
        self.latestUptimeNanoseconds = latestUptimeNanoseconds
    }

    public var widthSeconds: Double {
        Double(latestUptimeNanoseconds - earliestUptimeNanoseconds) / 1_000_000_000
    }
}

public struct AccelerationRunResult: Equatable, Sendable {
    public let source: SpeedTelemetrySource
    public let targetMetersPerSecond: Double
    public let launchWindow: AccelerationTimingWindow
    public let targetCrossingWindow: AccelerationTimingWindow
    public let elapsedLowerBoundSeconds: Double
    public let elapsedUpperBoundSeconds: Double
    public let authoritativeSampleCount: Int

    public var timingUncertaintySeconds: Double {
        max(0, elapsedUpperBoundSeconds - elapsedLowerBoundSeconds)
    }
}

public enum AccelerationRunInterruption: Equatable, Sendable {
    case vehicleConnectionLost
    case applicationLifecycleInterrupted
    case operatorCancelled
}

public enum AccelerationRunInvalidationReason: Equatable, Sendable {
    case rollingStart
    case nonMonotonicMeasurement
    case measurementSourceChanged
    case returnedToStationary
    case interruption(AccelerationRunInterruption)
}

public struct AccelerationRunProgress: Equatable, Sendable {
    public let source: SpeedTelemetrySource
    public let targetMetersPerSecond: Double
    public let launchWindow: AccelerationTimingWindow
    public let latestMeasuredMetersPerSecond: Double
    public let authoritativeSampleCount: Int
}

public enum AccelerationRunState: Equatable, Sendable {
    case waitingForStandstill
    case armed(source: SpeedTelemetrySource)
    case running(AccelerationRunProgress)
    case completed(AccelerationRunResult)
    case invalidated(AccelerationRunInvalidationReason)
}

/// Measurement-bounded acceleration timing.
///
/// The evaluator consumes only authoritative absolute speed measurements and
/// never converts display interpolation or motion-assisted estimates into run
/// evidence. Because threshold crossings occur between packets, completed runs
/// report an elapsed-time interval rather than pretending the crossing happened
/// at an exact stopwatch instant.
public struct AccelerationRunEvaluator: Sendable {
    public let policy: AccelerationRunPolicy
    public private(set) var state: AccelerationRunState = .waitingForStandstill

    private var lockedSource: SpeedTelemetrySource?
    private var lastAcceptedUptimeNanoseconds: UInt64?
    private var lastStationarySample: SpeedTelemetrySample?
    private var previousRunningSample: SpeedTelemetrySample?
    private var launchWindow: AccelerationTimingWindow?
    private var runSampleCount = 0

    public init(policy: AccelerationRunPolicy) {
        self.policy = policy
    }

    public mutating func reset() {
        state = .waitingForStandstill
        lockedSource = nil
        lastAcceptedUptimeNanoseconds = nil
        lastStationarySample = nil
        previousRunningSample = nil
        launchWindow = nil
        runSampleCount = 0
    }

    public mutating func interrupt(_ interruption: AccelerationRunInterruption) {
        switch state {
        case .armed, .running:
            invalidate(.interruption(interruption))
        case .waitingForStandstill, .completed, .invalidated:
            break
        }
    }

    public mutating func accept(_ sample: SpeedTelemetrySample) {
        guard canAcceptMoreEvidence else { return }
        guard sample.isAuthoritativeMeasurement else { return }
        guard sourceMatchesPolicy(sample.source) else { return }
        guard accuracyIsAcceptable(sample) else { return }

        if let lockedSource, sample.source != lockedSource {
            invalidate(.measurementSourceChanged)
            return
        }
        if lockedSource == nil {
            lockedSource = sample.source
        }

        if let lastAcceptedUptimeNanoseconds,
           sample.receivedAtUptimeNanoseconds <= lastAcceptedUptimeNanoseconds {
            invalidate(.nonMonotonicMeasurement)
            return
        }
        self.lastAcceptedUptimeNanoseconds = sample.receivedAtUptimeNanoseconds

        switch state {
        case .waitingForStandstill:
            acceptInitial(sample)
        case .armed:
            acceptArmed(sample)
        case .running:
            acceptRunning(sample)
        case .completed, .invalidated:
            break
        }
    }

    private var canAcceptMoreEvidence: Bool {
        switch state {
        case .completed, .invalidated:
            false
        case .waitingForStandstill, .armed, .running:
            true
        }
    }

    private func sourceMatchesPolicy(_ source: SpeedTelemetrySource) -> Bool {
        guard let requiredSource = policy.requiredSource else { return true }
        return source == requiredSource
    }

    private func accuracyIsAcceptable(_ sample: SpeedTelemetrySample) -> Bool {
        guard let maximum = policy.maximumSpeedAccuracyMetersPerSecond else { return true }
        guard let accuracy = sample.speedAccuracyMetersPerSecond else { return false }
        return accuracy <= maximum
    }

    private mutating func acceptInitial(_ sample: SpeedTelemetrySample) {
        guard sample.metersPerSecond <= policy.stationaryMaximumMetersPerSecond else {
            invalidate(.rollingStart)
            return
        }

        lastStationarySample = sample
        state = .armed(source: sample.source)
    }

    private mutating func acceptArmed(_ sample: SpeedTelemetrySample) {
        if sample.metersPerSecond <= policy.stationaryMaximumMetersPerSecond {
            lastStationarySample = sample
            return
        }

        guard let lastStationarySample else {
            invalidate(.rollingStart)
            return
        }

        let launch = AccelerationTimingWindow(
            earliestUptimeNanoseconds: lastStationarySample.receivedAtUptimeNanoseconds,
            latestUptimeNanoseconds: sample.receivedAtUptimeNanoseconds
        )
        launchWindow = launch
        previousRunningSample = sample
        runSampleCount = 2

        if sample.metersPerSecond >= policy.targetMetersPerSecond {
            complete(
                source: sample.source,
                targetCrossingWindow: launch,
                authoritativeSampleCount: runSampleCount
            )
            return
        }

        state = .running(AccelerationRunProgress(
            source: sample.source,
            targetMetersPerSecond: policy.targetMetersPerSecond,
            launchWindow: launch,
            latestMeasuredMetersPerSecond: sample.metersPerSecond,
            authoritativeSampleCount: runSampleCount
        ))
    }

    private mutating func acceptRunning(_ sample: SpeedTelemetrySample) {
        guard sample.metersPerSecond > policy.stationaryMaximumMetersPerSecond else {
            invalidate(.returnedToStationary)
            return
        }
        guard let previousRunningSample, let launchWindow else {
            invalidate(.rollingStart)
            return
        }

        runSampleCount += 1

        if sample.metersPerSecond >= policy.targetMetersPerSecond {
            let crossing = AccelerationTimingWindow(
                earliestUptimeNanoseconds: previousRunningSample.receivedAtUptimeNanoseconds,
                latestUptimeNanoseconds: sample.receivedAtUptimeNanoseconds
            )
            complete(
                source: sample.source,
                targetCrossingWindow: crossing,
                authoritativeSampleCount: runSampleCount
            )
            return
        }

        self.previousRunningSample = sample
        state = .running(AccelerationRunProgress(
            source: sample.source,
            targetMetersPerSecond: policy.targetMetersPerSecond,
            launchWindow: launchWindow,
            latestMeasuredMetersPerSecond: sample.metersPerSecond,
            authoritativeSampleCount: runSampleCount
        ))
    }

    private mutating func complete(
        source: SpeedTelemetrySource,
        targetCrossingWindow: AccelerationTimingWindow,
        authoritativeSampleCount: Int
    ) {
        guard let launchWindow else {
            invalidate(.rollingStart)
            return
        }

        let lowerBoundNanoseconds: UInt64
        if targetCrossingWindow.earliestUptimeNanoseconds > launchWindow.latestUptimeNanoseconds {
            lowerBoundNanoseconds = targetCrossingWindow.earliestUptimeNanoseconds - launchWindow.latestUptimeNanoseconds
        } else {
            lowerBoundNanoseconds = 0
        }
        let upperBoundNanoseconds = targetCrossingWindow.latestUptimeNanoseconds - launchWindow.earliestUptimeNanoseconds

        state = .completed(AccelerationRunResult(
            source: source,
            targetMetersPerSecond: policy.targetMetersPerSecond,
            launchWindow: launchWindow,
            targetCrossingWindow: targetCrossingWindow,
            elapsedLowerBoundSeconds: Double(lowerBoundNanoseconds) / 1_000_000_000,
            elapsedUpperBoundSeconds: Double(upperBoundNanoseconds) / 1_000_000_000,
            authoritativeSampleCount: authoritativeSampleCount
        ))
    }

    private mutating func invalidate(_ reason: AccelerationRunInvalidationReason) {
        state = .invalidated(reason)
    }
}
