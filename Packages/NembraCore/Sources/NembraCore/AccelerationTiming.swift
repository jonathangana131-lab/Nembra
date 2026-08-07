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
        stationaryMaximumMetersPerSecond: Double,
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

/// Identifies the clock/evidence basis of an acceleration result.
///
/// `receiveObservationUptime` means the result is expressed only in the app's
/// monotonic packet-receipt timeline. It is not a physical scooter crossing-time
/// clock and does not compensate for source-to-app delivery latency.
public enum AccelerationTimingBasis: Equatable, Sendable {
    case receiveObservationUptime
}

/// A span between two accepted observations on the app's monotonic receive clock.
///
/// This is an observation-evidence window, not a guarantee that the scooter's
/// physical threshold crossing occurred inside the same uptime interval. Variable
/// delivery latency can move physical measurement/crossing time outside a receive
/// interval, and an unsampled excursion can precede a later observed transition.
public struct AccelerationTimingWindow: Equatable, Sendable {
    public let earliestUptimeNanoseconds: UInt64
    public let latestUptimeNanoseconds: UInt64

    /// Timing windows are output evidence created only from accepted monotonic
    /// observations. Keep construction internal so external callers cannot
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
    public let timingBasis: AccelerationTimingBasis

    /// Last accepted stationary observation -> first accepted moving observation.
    /// This brackets the change in observed samples, not physical scooter launch.
    public let launchObservationWindow: AccelerationTimingWindow

    /// Last accepted below-target observation -> first accepted at/above-target
    /// observation. This is the final observed below->at/above pair and does not
    /// prove that the scooter never reached target earlier between samples.
    public let targetTransitionObservationWindow: AccelerationTimingWindow

    /// Monotonic receive-clock interval from the last accepted stationary packet
    /// receipt to the first accepted at/above-target packet receipt.
    ///
    /// This is a directly observed app-timeline interval only. It is deliberately
    /// not named or modeled as first-reach time, acceleration time, or a physical
    /// upper/lower bound because unsampled excursions and variable delivery latency
    /// prevent those stronger claims without additional validated evidence.
    public let stationaryToTargetObservationElapsedSeconds: Double

    /// Count of accepted measurements actually retained by the final timing
    /// trace: the last stationary launch anchor plus accepted post-launch samples.
    /// Earlier stationary samples that were superseded by a newer anchor are not
    /// represented in this count.
    public let timingEvidenceSampleCount: Int
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
    public let launchObservationWindow: AccelerationTimingWindow
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

/// Measurement-bounded acceleration observation evidence.
///
/// The evaluator consumes only authoritative absolute speed measurements and
/// never converts display interpolation or motion-assisted estimates into run
/// evidence. It records accepted transitions on the monotonic packet-receipt
/// clock. It deliberately does not claim those receive timestamps are physical
/// scooter threshold-crossing times.
public struct AccelerationRunEvaluator: Sendable {
    public let policy: AccelerationRunPolicy
    public private(set) var state: AccelerationRunState = .waitingForStandstill

    private var lockedSource: SpeedTelemetrySource?
    /// Advances for every monotonic observation from the locked/required source,
    /// even when that observation is later rejected by accuracy policy. Rejected
    /// quality cannot erase chronology and let an older callback look fresh.
    private var lastObservedUptimeNanoseconds: UInt64?
    /// Advances only for accepted measurements. The optional maximum sample-gap
    /// policy is measured between timing evidence that must be continuous. Long
    /// idle time between stationary anchors is allowed because a newer stationary
    /// sample simply replaces the old launch anchor.
    private var lastAcceptedUptimeNanoseconds: UInt64?
    private var lastStationarySample: SpeedTelemetrySample?
    private var previousRunningSample: SpeedTelemetrySample?
    private var launchObservationWindow: AccelerationTimingWindow?
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
        launchObservationWindow = nil
        timingEvidenceSampleCount = 0
    }

    public mutating func interrupt(_ interruption: AccelerationRunInterruption) {
        if interruption == .operatorCancelled {
            switch state {
            case .waitingForStandstill, .armed, .running:
                invalidate(.interruption(interruption))
            case .completed, .invalidated:
                break
            }
            return
        }

        switch state {
        case .armed, .running:
            invalidate(.interruption(interruption))
        case .waitingForStandstill, .completed, .invalidated:
            break
        }
    }

    public mutating func accept(_ sample: SpeedTelemetrySample) {
        guard canAcceptMoreEvidence else { return }
        // Defense in depth: this evidence consumer never accepts motion-assisted
        // data as authoritative, even if an import or persistence boundary is
        // malformed. A hardened upstream decoder may reject that sample earlier;
        // this guard remains safe redundancy rather than relying on decode policy.
        guard sample.source != .motionAssist else { return }
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

        if shouldEnforceAcceptedMeasurementGap(for: sample),
           let lastAcceptedUptimeNanoseconds,
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

    /// A long idle period while the scooter remains stationary does not weaken a
    /// future run: the newest stationary sample becomes the launch anchor. The
    /// gap ceiling becomes evidence-critical only when crossing from stationary
    /// to moving, and for every accepted sample once the run is in progress.
    private func shouldEnforceAcceptedMeasurementGap(for sample: SpeedTelemetrySample) -> Bool {
        switch state {
        case .running:
            true
        case .armed:
            sample.metersPerSecond > policy.stationaryMaximumMetersPerSecond
        case .waitingForStandstill, .completed, .invalidated:
            false
        }
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

        let launchObservation = AccelerationTimingWindow(
            earliestUptimeNanoseconds: lastStationarySample.receivedAtUptimeNanoseconds,
            latestUptimeNanoseconds: sample.receivedAtUptimeNanoseconds
        )
        launchObservationWindow = launchObservation
        previousRunningSample = sample
        // Only the latest stationary sample and the first moving sample are
        // retained by the final launch observation window.
        timingEvidenceSampleCount = 2

        if sample.metersPerSecond >= policy.targetMetersPerSecond {
            complete(
                source: sample.source,
                targetTransitionObservationWindow: launchObservation,
                timingEvidenceSampleCount: timingEvidenceSampleCount
            )
            return
        }

        state = .running(AccelerationRunProgress(
            source: sample.source,
            targetMetersPerSecond: policy.targetMetersPerSecond,
            launchObservationWindow: launchObservation,
            latestMeasuredMetersPerSecond: sample.metersPerSecond,
            timingEvidenceSampleCount: timingEvidenceSampleCount
        ))
    }

    private mutating func acceptRunning(_ sample: SpeedTelemetrySample) {
        guard sample.metersPerSecond > policy.stationaryMaximumMetersPerSecond else {
            invalidate(.returnedToStationary)
            return
        }
        guard let previousRunningSample, let launchObservationWindow else {
            invalidate(.rollingStart)
            return
        }

        timingEvidenceSampleCount += 1

        if sample.metersPerSecond >= policy.targetMetersPerSecond {
            let targetTransitionObservation = AccelerationTimingWindow(
                earliestUptimeNanoseconds: previousRunningSample.receivedAtUptimeNanoseconds,
                latestUptimeNanoseconds: sample.receivedAtUptimeNanoseconds
            )
            complete(
                source: sample.source,
                targetTransitionObservationWindow: targetTransitionObservation,
                timingEvidenceSampleCount: timingEvidenceSampleCount
            )
            return
        }

        self.previousRunningSample = sample
        state = .running(AccelerationRunProgress(
            source: sample.source,
            targetMetersPerSecond: policy.targetMetersPerSecond,
            launchObservationWindow: launchObservationWindow,
            latestMeasuredMetersPerSecond: sample.metersPerSecond,
            timingEvidenceSampleCount: timingEvidenceSampleCount
        ))
    }

    private mutating func complete(
        source: SpeedTelemetrySource,
        targetTransitionObservationWindow: AccelerationTimingWindow,
        timingEvidenceSampleCount: Int
    ) {
        guard let launchObservationWindow else {
            invalidate(.rollingStart)
            return
        }

        let observationElapsedNanoseconds = targetTransitionObservationWindow.latestUptimeNanoseconds
            - launchObservationWindow.earliestUptimeNanoseconds

        state = .completed(AccelerationRunResult(
            source: source,
            targetMetersPerSecond: policy.targetMetersPerSecond,
            timingBasis: .receiveObservationUptime,
            launchObservationWindow: launchObservationWindow,
            targetTransitionObservationWindow: targetTransitionObservationWindow,
            stationaryToTargetObservationElapsedSeconds: Double(observationElapsedNanoseconds) / 1_000_000_000,
            timingEvidenceSampleCount: timingEvidenceSampleCount
        ))
    }

    private mutating func invalidate(_ reason: AccelerationRunInvalidationReason) {
        state = .invalidated(reason)
    }
}
