import Foundation

public enum AccelerationRunPolicyError: Error, Equatable, Sendable {
    case invalidTargetSpeed
    case invalidStationaryThreshold
    case invalidMaximumSpeedAccuracy
    case invalidMaximumSampleInterval
    case invalidRequiredSource
}

public struct AccelerationRunPolicy: Equatable, Sendable {
    public let targetMetersPerSecond: Double
    public let stationaryMaximumMetersPerSecond: Double
    public let requiredSource: SpeedTelemetrySource?
    public let maximumSpeedAccuracyMetersPerSecond: Double?
    public let maximumSampleIntervalNanoseconds: UInt64?

    public init(
        targetMetersPerSecond: Double,
        stationaryMaximumMetersPerSecond: Double = 0.5,
        requiredSource: SpeedTelemetrySource? = nil,
        maximumSpeedAccuracyMetersPerSecond: Double? = nil,
        maximumSampleIntervalNanoseconds: UInt64? = nil
    ) throws {
        guard targetMetersPerSecond.isFinite, targetMetersPerSecond > 0 else {
            throw AccelerationRunPolicyError.invalidTargetSpeed
        }
        guard stationaryMaximumMetersPerSecond.isFinite,
              stationaryMaximumMetersPerSecond >= 0,
              stationaryMaximumMetersPerSecond < targetMetersPerSecond else {
            throw AccelerationRunPolicyError.invalidStationaryThreshold
        }
        if requiredSource == .motionAssist {
            throw AccelerationRunPolicyError.invalidRequiredSource
        }
        if let maximumSpeedAccuracyMetersPerSecond {
            guard maximumSpeedAccuracyMetersPerSecond.isFinite,
                  maximumSpeedAccuracyMetersPerSecond >= 0 else {
                throw AccelerationRunPolicyError.invalidMaximumSpeedAccuracy
            }
        }
        if let maximumSampleIntervalNanoseconds {
            guard maximumSampleIntervalNanoseconds > 0 else {
                throw AccelerationRunPolicyError.invalidMaximumSampleInterval
            }
        }

        self.targetMetersPerSecond = targetMetersPerSecond
        self.stationaryMaximumMetersPerSecond = stationaryMaximumMetersPerSecond
        self.requiredSource = requiredSource
        self.maximumSpeedAccuracyMetersPerSecond = maximumSpeedAccuracyMetersPerSecond
        self.maximumSampleIntervalNanoseconds = maximumSampleIntervalNanoseconds
    }
}

public struct AccelerationTimingWindow: Equatable, Sendable {
    public let earliestUptimeNanoseconds: UInt64
    public let latestUptimeNanoseconds: UInt64

    /// Timing windows are output evidence created only from accepted monotonic
    /// measurements. Keep construction internal so external callers cannot
    /// manufacture impossible windows or trigger a public precondition trap.
    init(earliestUptimeNanoseconds: UInt64, latestUptimeNanoseconds: UInt64) {
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
    /// Count of accepted measurements actually retained by the final timing
    /// trace: the last stationary launch anchor plus accepted post-launch samples.
    /// Earlier stationary samples that were superseded by a newer anchor are not
    /// represented in this count.
    public let timingEvidenceSampleCount: Int

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
    case measurementGapExceeded
    case measurementSourceChanged
    case returnedToStationary
    case interruption(AccelerationRunInterruption)
}

public struct AccelerationRunProgress: Equatable, Sendable {
    public let source: SpeedTelemetrySource
    public let targetMetersPerSecond: Double
    public let launchWindow: AccelerationTimingWindow
    public let latestMeasuredMetersPerSecond: Double
    /// Same retained timing-evidence count used by the eventual completed result.
    public let timingEvidenceSampleCount: Int
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
    /// Advances for every monotonic observation from the locked/required source,
    /// even when that observation is later rejected by accuracy policy. Rejected
    /// quality cannot erase chronology and let an older callback look fresh.
    private var lastObservedUptimeNanoseconds: UInt64?
    /// Advances only for accepted measurements. The optional maximum sample-gap
    /// policy is intentionally measured between usable timing evidence, not
    /// between callbacks that failed quality screening.
    private var lastAcceptedUptimeNanoseconds: UInt64?
    private var lastStationarySample: SpeedTelemetrySample?
    private var previousRunningSample: SpeedTelemetrySample?
    private var launchWindow: AccelerationTimingWindow?
    private var timingEvidenceSampleCount = 0

    public init(policy: AccelerationRunPolicy) {
        self.policy = policy
    }

    public mutating func reset() {
        state = .waitingForStandstill
        lockedSource = nil
        lastObservedUptimeNanoseconds = nil
        lastAcceptedUptimeNanoseconds = nil
        lastStationarySample = nil
        previousRunningSample = nil
        launchWindow = nil
        timingEvidenceSampleCount = 0
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

        if let lockedSource {
            guard sample.source == lockedSource else {
                invalidate(.measurementSourceChanged)
                return
            }
            guard acceptObservedTimestamp(sample.receivedAtUptimeNanoseconds) else {
                return
            }
            guard accuracyIsAcceptable(sample) else { return }
        } else if policy.requiredSource != nil {
            // The policy has already selected this source. Even a quality-
            // rejected first callback is part of its real observation ordering.
            lockedSource = sample.source
            guard acceptObservedTimestamp(sample.receivedAtUptimeNanoseconds) else {
                return
            }
            guard accuracyIsAcceptable(sample) else { return }
        } else {
            // Without an explicit source requirement, only the first usable
            // measurement selects the source; unrelated low-quality providers
            // should not poison a run before it has chosen evidence.
            guard accuracyIsAcceptable(sample) else { return }
            lockedSource = sample.source
            guard acceptObservedTimestamp(sample.receivedAtUptimeNanoseconds) else {
                return
            }
        }

        if let lastAcceptedUptimeNanoseconds,
           let maximumSampleIntervalNanoseconds = policy.maximumSampleIntervalNanoseconds,
           sample.receivedAtUptimeNanoseconds - lastAcceptedUptimeNanoseconds > maximumSampleIntervalNanoseconds {
            invalidate(.measurementGapExceeded)
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

    private mutating func acceptObservedTimestamp(_ uptimeNanoseconds: UInt64) -> Bool {
        if let lastObservedUptimeNanoseconds,
           uptimeNanoseconds <= lastObservedUptimeNanoseconds {
            invalidate(.nonMonotonicMeasurement)
            return false
        }
        lastObservedUptimeNanoseconds = uptimeNanoseconds
        return true
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
        // Only the latest stationary sample and the first moving sample are
        // retained by the final launch timing window.
        timingEvidenceSampleCount = 2

        if sample.metersPerSecond >= policy.targetMetersPerSecond {
            complete(
                source: sample.source,
                targetCrossingWindow: launch,
                timingEvidenceSampleCount: timingEvidenceSampleCount
            )
            return
        }

        state = .running(AccelerationRunProgress(
            source: sample.source,
            targetMetersPerSecond: policy.targetMetersPerSecond,
            launchWindow: launch,
            latestMeasuredMetersPerSecond: sample.metersPerSecond,
            timingEvidenceSampleCount: timingEvidenceSampleCount
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

        timingEvidenceSampleCount += 1

        if sample.metersPerSecond >= policy.targetMetersPerSecond {
            let crossing = AccelerationTimingWindow(
                earliestUptimeNanoseconds: previousRunningSample.receivedAtUptimeNanoseconds,
                latestUptimeNanoseconds: sample.receivedAtUptimeNanoseconds
            )
            complete(
                source: sample.source,
                targetCrossingWindow: crossing,
                timingEvidenceSampleCount: timingEvidenceSampleCount
            )
            return
        }

        self.previousRunningSample = sample
        state = .running(AccelerationRunProgress(
            source: sample.source,
            targetMetersPerSecond: policy.targetMetersPerSecond,
            launchWindow: launchWindow,
            latestMeasuredMetersPerSecond: sample.metersPerSecond,
            timingEvidenceSampleCount: timingEvidenceSampleCount
        ))
    }

    private mutating func complete(
        source: SpeedTelemetrySource,
        targetCrossingWindow: AccelerationTimingWindow,
        timingEvidenceSampleCount: Int
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
            timingEvidenceSampleCount: timingEvidenceSampleCount
        ))
    }

    private mutating func invalidate(_ reason: AccelerationRunInvalidationReason) {
        state = .invalidated(reason)
    }
}
