import Foundation

public enum PropulsionPowerSampleAuthority: String, Codable, Sendable {
    /// Production-only authority. Construction is package-sealed so UI or generic clients cannot mint it.
    case verifiedVehicleMeasurement
    /// Explicitly synthetic evidence for Simulator/runtime visual QA.
    case simulator
}

public struct PropulsionGaugeIdentity: Hashable, Codable, Sendable {
    public let vehicleID: String
    public let modeKey: String?

    public init(vehicleID: String, modeKey: String? = nil) {
        self.vehicleID = vehicleID
        self.modeKey = modeKey
    }
}

public enum PropulsionPowerSampleError: Error, Equatable, Sendable {
    case invalidWatts
}

/// One accepted propulsion-power observation. This is intentionally distinct from every render frame.
///
/// The type currently models nonnegative propulsion output only. Regenerative/reverse presentation must
/// remain unavailable until a separate authoritative negative-current/power semantic is physically verified.
public struct PropulsionPowerSample: Equatable, Sendable {
    public let identity: PropulsionGaugeIdentity
    public let watts: Double
    public let receivedAtUptimeNanoseconds: UInt64
    public let continuityGeneration: UInt64
    public let authority: PropulsionPowerSampleAuthority

    private init(
        identity: PropulsionGaugeIdentity,
        watts: Double,
        receivedAtUptimeNanoseconds: UInt64,
        continuityGeneration: UInt64,
        authority: PropulsionPowerSampleAuthority
    ) {
        self.identity = identity
        self.watts = watts
        self.receivedAtUptimeNanoseconds = receivedAtUptimeNanoseconds
        self.continuityGeneration = continuityGeneration
        self.authority = authority
    }

    public static func simulator(
        identity: PropulsionGaugeIdentity,
        watts: Double,
        receivedAtUptimeNanoseconds: UInt64,
        continuityGeneration: UInt64
    ) throws -> Self {
        try validated(
            identity: identity,
            watts: watts,
            receivedAtUptimeNanoseconds: receivedAtUptimeNanoseconds,
            continuityGeneration: continuityGeneration,
            authority: .simulator
        )
    }

    #if SWIFT_PACKAGE
    package static func verifiedVehicleMeasurement(
        identity: PropulsionGaugeIdentity,
        watts: Double,
        receivedAtUptimeNanoseconds: UInt64,
        continuityGeneration: UInt64
    ) throws -> Self {
        try validated(
            identity: identity,
            watts: watts,
            receivedAtUptimeNanoseconds: receivedAtUptimeNanoseconds,
            continuityGeneration: continuityGeneration,
            authority: .verifiedVehicleMeasurement
        )
    }
    #else
    fileprivate static func verifiedVehicleMeasurement(
        identity: PropulsionGaugeIdentity,
        watts: Double,
        receivedAtUptimeNanoseconds: UInt64,
        continuityGeneration: UInt64
    ) throws -> Self {
        try validated(
            identity: identity,
            watts: watts,
            receivedAtUptimeNanoseconds: receivedAtUptimeNanoseconds,
            continuityGeneration: continuityGeneration,
            authority: .verifiedVehicleMeasurement
        )
    }
    #endif

    private static func validated(
        identity: PropulsionGaugeIdentity,
        watts: Double,
        receivedAtUptimeNanoseconds: UInt64,
        continuityGeneration: UInt64,
        authority: PropulsionPowerSampleAuthority
    ) throws -> Self {
        guard watts.isFinite, watts >= 0 else {
            throw PropulsionPowerSampleError.invalidWatts
        }

        return Self(
            identity: identity,
            watts: watts,
            receivedAtUptimeNanoseconds: receivedAtUptimeNanoseconds,
            continuityGeneration: continuityGeneration,
            authority: authority
        )
    }
}

public enum PropulsionGaugeScaleOrigin: String, Equatable, Sendable {
    /// A visual ceiling learned only from repeated verified vehicle observations.
    case learnedObservedPowerCeiling
    /// Explicitly synthetic scale for Simulator/runtime visual QA.
    case simulator
}

public enum PropulsionGaugeScaleError: Error, Equatable, Sendable {
    case invalidCeiling
}

/// Presentation scale only. A learned observed ceiling is not a rated/certified motor or controller maximum.
/// Every scale is bound to the same vehicle/mode identity as the observations that produced or exercise it.
public struct PropulsionGaugeScale: Equatable, Sendable {
    public let identity: PropulsionGaugeIdentity
    public let ceilingWatts: Double
    public let origin: PropulsionGaugeScaleOrigin

    private init(
        identity: PropulsionGaugeIdentity,
        ceilingWatts: Double,
        origin: PropulsionGaugeScaleOrigin
    ) {
        self.identity = identity
        self.ceilingWatts = ceilingWatts
        self.origin = origin
    }

    public static func simulator(
        identity: PropulsionGaugeIdentity,
        ceilingWatts: Double
    ) throws -> Self {
        guard ceilingWatts.isFinite, ceilingWatts > 0 else {
            throw PropulsionGaugeScaleError.invalidCeiling
        }
        return Self(identity: identity, ceilingWatts: ceilingWatts, origin: .simulator)
    }

    fileprivate static func learnedObserved(
        identity: PropulsionGaugeIdentity,
        ceilingWatts: Double
    ) -> Self {
        Self(
            identity: identity,
            ceilingWatts: ceilingWatts,
            origin: .learnedObservedPowerCeiling
        )
    }
}

public enum PropulsionGaugeMotionPolicyError: Error, Equatable, Sendable {
    case invalidRiseSettlingDuration
    case invalidFallSettlingDuration
    case invalidStaleInterval
}

/// Display-clock timing only. These values do not define BLE cadence or physical scooter dynamics.
public struct PropulsionGaugeMotionPolicy: Equatable, Sendable {
    public let riseSettlingDurationNanoseconds: UInt64
    public let fallSettlingDurationNanoseconds: UInt64
    public let staleAfterNanoseconds: UInt64
    public let acceptedPeakHoldNanoseconds: UInt64

    public init(
        riseSettlingDurationNanoseconds: UInt64,
        fallSettlingDurationNanoseconds: UInt64,
        staleAfterNanoseconds: UInt64,
        acceptedPeakHoldNanoseconds: UInt64
    ) throws {
        guard riseSettlingDurationNanoseconds > 0 else {
            throw PropulsionGaugeMotionPolicyError.invalidRiseSettlingDuration
        }
        guard fallSettlingDurationNanoseconds > 0 else {
            throw PropulsionGaugeMotionPolicyError.invalidFallSettlingDuration
        }
        guard staleAfterNanoseconds > 0 else {
            throw PropulsionGaugeMotionPolicyError.invalidStaleInterval
        }

        self.riseSettlingDurationNanoseconds = riseSettlingDurationNanoseconds
        self.fallSettlingDurationNanoseconds = fallSettlingDurationNanoseconds
        self.staleAfterNanoseconds = staleAfterNanoseconds
        self.acceptedPeakHoldNanoseconds = acceptedPeakHoldNanoseconds
    }
}

public enum PropulsionGaugeAvailability: String, Equatable, Sendable {
    case live
    /// The last accepted numeric observation is preserved, but the active gauge is no longer animated.
    case retained
    /// Explicit source/session unavailability. Disconnect is never converted into measured zero.
    case unavailable
}

public enum PropulsionGaugeFrameOrigin: String, Equatable, Sendable {
    /// The rendered value equals the latest accepted measurement.
    case acceptedMeasurement
    /// Render-only motion between accepted measurements.
    case visuallyInterpolated
    /// Exact last accepted measurement retained after its live window expired.
    case retainedAcceptedMeasurement
    case unavailable
}

/// Render-only gauge state. `displayWatts` and normalized fractions must never enter telemetry evidence,
/// ride statistics, persistence, peak evidence, battery learning, or protocol claims.
public struct PropulsionGaugeFrame: Equatable, Sendable {
    public let availability: PropulsionGaugeAvailability
    public let origin: PropulsionGaugeFrameOrigin
    public let displayWatts: Double?
    public let latestAcceptedWatts: Double?
    public let latestAcceptedUptimeNanoseconds: UInt64?
    public let latestAuthority: PropulsionPowerSampleAuthority?
    public let normalizedPropulsion: Double?
    public let acceptedPeakNormalized: Double?
    public let scaleOrigin: PropulsionGaugeScaleOrigin?
}

public enum PropulsionGaugeDisplayError: Error, Equatable, Sendable {
    case identityMismatch
    case nonMonotonicMeasurement
    case staleContinuityGeneration
}

/// Critically damped, retargetable render model for positive propulsion output.
///
/// Measurement and display clocks remain separate: accepted samples change the target, while callers may
/// ask for frames at display refresh rate. The response never predicts beyond the latest accepted target.
public struct PropulsionGaugeDisplayModel: Sendable {
    public let identity: PropulsionGaugeIdentity
    public let policy: PropulsionGaugeMotionPolicy

    private var hasMeasurement = false
    private var latestAcceptedWatts = 0.0
    private var latestAcceptedUptimeNanoseconds: UInt64 = 0
    private var latestContinuityGeneration: UInt64 = 0
    private var latestAuthority: PropulsionPowerSampleAuthority = .simulator

    private var transitionAnchorWatts = 0.0
    private var transitionTargetWatts = 0.0
    private var transitionStartUptimeNanoseconds: UInt64 = 0
    private var transitionSettlingDurationNanoseconds: UInt64 = 0

    private var acceptedPeakWatts = 0.0
    private var acceptedPeakUptimeNanoseconds: UInt64 = 0
    private var explicitlyUnavailable = false

    public init(identity: PropulsionGaugeIdentity, policy: PropulsionGaugeMotionPolicy) {
        self.identity = identity
        self.policy = policy
    }

    public mutating func accept(_ sample: PropulsionPowerSample) throws {
        guard sample.identity == identity else {
            throw PropulsionGaugeDisplayError.identityMismatch
        }

        if hasMeasurement {
            guard sample.continuityGeneration >= latestContinuityGeneration else {
                throw PropulsionGaugeDisplayError.staleContinuityGeneration
            }
            guard sample.receivedAtUptimeNanoseconds > latestAcceptedUptimeNanoseconds else {
                throw PropulsionGaugeDisplayError.nonMonotonicMeasurement
            }
        }

        let sharesContinuity: Bool
        if hasMeasurement,
           !explicitlyUnavailable,
           sample.continuityGeneration == latestContinuityGeneration {
            let gap = sample.receivedAtUptimeNanoseconds - latestAcceptedUptimeNanoseconds
            sharesContinuity = gap <= policy.staleAfterNanoseconds
        } else {
            sharesContinuity = false
        }

        let currentVisualWatts = sharesContinuity
            ? liveMotionValue(atUptimeNanoseconds: sample.receivedAtUptimeNanoseconds)
            : sample.watts

        transitionAnchorWatts = currentVisualWatts
        transitionTargetWatts = sample.watts
        transitionStartUptimeNanoseconds = sample.receivedAtUptimeNanoseconds

        // Compare the finite endpoints directly. Subtracting extreme finite values can overflow even though
        // both observations themselves are valid, and render math must never manufacture infinity/NaN.
        let hasVisualDistance = transitionTargetWatts != transitionAnchorWatts
        if sharesContinuity, hasVisualDistance {
            transitionSettlingDurationNanoseconds = transitionTargetWatts >= transitionAnchorWatts
                ? policy.riseSettlingDurationNanoseconds
                : policy.fallSettlingDurationNanoseconds
        } else {
            transitionSettlingDurationNanoseconds = 0
        }

        if !hasMeasurement
            || !sharesContinuity
            || sample.receivedAtUptimeNanoseconds - acceptedPeakUptimeNanoseconds > policy.acceptedPeakHoldNanoseconds {
            acceptedPeakWatts = sample.watts
            acceptedPeakUptimeNanoseconds = sample.receivedAtUptimeNanoseconds
        } else if sample.watts >= acceptedPeakWatts {
            acceptedPeakWatts = sample.watts
            acceptedPeakUptimeNanoseconds = sample.receivedAtUptimeNanoseconds
        }

        hasMeasurement = true
        latestAcceptedWatts = sample.watts
        latestAcceptedUptimeNanoseconds = sample.receivedAtUptimeNanoseconds
        latestContinuityGeneration = sample.continuityGeneration
        latestAuthority = sample.authority
        explicitlyUnavailable = false
    }

    /// Explicitly ends live presentation without manufacturing a zero-power sample.
    public mutating func markUnavailable() {
        explicitlyUnavailable = true
        transitionSettlingDurationNanoseconds = 0
    }

    public func frame(
        atUptimeNanoseconds now: UInt64,
        scale: PropulsionGaugeScale?
    ) -> PropulsionGaugeFrame {
        guard hasMeasurement else {
            return PropulsionGaugeFrame(
                availability: .unavailable,
                origin: .unavailable,
                displayWatts: nil,
                latestAcceptedWatts: nil,
                latestAcceptedUptimeNanoseconds: nil,
                latestAuthority: nil,
                normalizedPropulsion: nil,
                acceptedPeakNormalized: nil,
                scaleOrigin: nil
            )
        }

        if explicitlyUnavailable {
            return PropulsionGaugeFrame(
                availability: .unavailable,
                origin: .unavailable,
                displayWatts: nil,
                latestAcceptedWatts: latestAcceptedWatts,
                latestAcceptedUptimeNanoseconds: latestAcceptedUptimeNanoseconds,
                latestAuthority: latestAuthority,
                normalizedPropulsion: nil,
                acceptedPeakNormalized: nil,
                scaleOrigin: nil
            )
        }

        let effectiveNow = max(now, latestAcceptedUptimeNanoseconds)
        let age = effectiveNow - latestAcceptedUptimeNanoseconds
        if age > policy.staleAfterNanoseconds {
            return PropulsionGaugeFrame(
                availability: .retained,
                origin: .retainedAcceptedMeasurement,
                displayWatts: latestAcceptedWatts,
                latestAcceptedWatts: latestAcceptedWatts,
                latestAcceptedUptimeNanoseconds: latestAcceptedUptimeNanoseconds,
                latestAuthority: latestAuthority,
                normalizedPropulsion: nil,
                acceptedPeakNormalized: nil,
                scaleOrigin: nil
            )
        }

        let displayWatts = liveMotionValue(atUptimeNanoseconds: effectiveNow)
        let isAtAcceptedMeasurement = transitionSettlingDurationNanoseconds == 0
            || effectiveNow - transitionStartUptimeNanoseconds >= transitionSettlingDurationNanoseconds
            || displayWatts == latestAcceptedWatts

        let compatibleScale = scale.flatMap { candidate -> PropulsionGaugeScale? in
            guard candidate.identity == identity else { return nil }

            switch (candidate.origin, latestAuthority) {
            case (.learnedObservedPowerCeiling, .verifiedVehicleMeasurement),
                 (.simulator, .simulator):
                return candidate
            default:
                return nil
            }
        }

        let normalized = compatibleScale.map {
            min(1, max(0, displayWatts / $0.ceilingWatts))
        }

        let peakAge = effectiveNow >= acceptedPeakUptimeNanoseconds
            ? effectiveNow - acceptedPeakUptimeNanoseconds
            : 0
        let acceptedPeakNormalized: Double?
        if let compatibleScale,
           peakAge <= policy.acceptedPeakHoldNanoseconds {
            acceptedPeakNormalized = min(1, max(0, acceptedPeakWatts / compatibleScale.ceilingWatts))
        } else {
            acceptedPeakNormalized = nil
        }

        return PropulsionGaugeFrame(
            availability: .live,
            origin: isAtAcceptedMeasurement ? .acceptedMeasurement : .visuallyInterpolated,
            displayWatts: displayWatts,
            latestAcceptedWatts: latestAcceptedWatts,
            latestAcceptedUptimeNanoseconds: latestAcceptedUptimeNanoseconds,
            latestAuthority: latestAuthority,
            normalizedPropulsion: normalized,
            acceptedPeakNormalized: acceptedPeakNormalized,
            scaleOrigin: compatibleScale?.origin
        )
    }

    private func liveMotionValue(atUptimeNanoseconds now: UInt64) -> Double {
        guard hasMeasurement else { return 0 }
        guard transitionSettlingDurationNanoseconds > 0 else {
            return transitionTargetWatts
        }
        guard now > transitionStartUptimeNanoseconds else {
            return transitionAnchorWatts
        }

        let elapsedNanoseconds = now - transitionStartUptimeNanoseconds
        if elapsedNanoseconds >= transitionSettlingDurationNanoseconds {
            return transitionTargetWatts
        }

        let elapsedSeconds = Double(elapsedNanoseconds) / 1_000_000_000
        let settlingSeconds = Double(transitionSettlingDurationNanoseconds) / 1_000_000_000

        // omega = 8 / settling window leaves <0.31% zero-velocity step error before the exact target snap.
        let omega = 8 / settlingSeconds
        let rawProgress = 1 - (1 + omega * elapsedSeconds) * exp(-omega * elapsedSeconds)
        let progress = min(1, max(0, rawProgress))

        if progress <= 0 {
            return transitionAnchorWatts
        }
        if progress >= 1 {
            return transitionTargetWatts
        }

        // This is a convex combination of two nonnegative finite observations. Unlike
        // `anchor + (target - anchor) * progress`, it never forms an overflowing endpoint delta.
        let visualWatts = transitionAnchorWatts * (1 - progress)
            + transitionTargetWatts * progress
        if visualWatts.isFinite {
            return visualWatts
        }

        // Floating-point rounding should not overflow a convex combination, but fail closed to a real
        // accepted endpoint rather than ever exposing a fabricated non-finite render value.
        return progress < 0.5 ? transitionAnchorWatts : transitionTargetWatts
    }
}

public enum LearnedObservedPowerEnvelopePolicyError: Error, Equatable, Sendable {
    case invalidMinimumPositiveSampleCount
    case invalidWindowCapacity
    case invalidUpperPercentile
    case invalidVisualHeadroomFraction
    case invalidUpwardHysteresisFraction
    case invalidDownwardHysteresisFraction
    case invalidDownwardAdaptationFraction
}

/// Visual calibration policy only. None of these values assert a physical ES80 rating or controller limit.
public struct LearnedObservedPowerEnvelopePolicy: Equatable, Sendable {
    public let minimumPositiveSampleCount: Int
    public let windowCapacity: Int
    public let upperPercentile: Double
    public let visualHeadroomFraction: Double
    public let upwardHysteresisFraction: Double
    public let downwardHysteresisFraction: Double
    public let downwardAdaptationFraction: Double

    public init(
        minimumPositiveSampleCount: Int,
        windowCapacity: Int,
        upperPercentile: Double,
        visualHeadroomFraction: Double,
        upwardHysteresisFraction: Double,
        downwardHysteresisFraction: Double,
        downwardAdaptationFraction: Double
    ) throws {
        guard minimumPositiveSampleCount > 0 else {
            throw LearnedObservedPowerEnvelopePolicyError.invalidMinimumPositiveSampleCount
        }
        guard windowCapacity >= minimumPositiveSampleCount else {
            throw LearnedObservedPowerEnvelopePolicyError.invalidWindowCapacity
        }
        guard upperPercentile.isFinite, upperPercentile > 0, upperPercentile <= 1 else {
            throw LearnedObservedPowerEnvelopePolicyError.invalidUpperPercentile
        }
        guard visualHeadroomFraction.isFinite, visualHeadroomFraction >= 0 else {
            throw LearnedObservedPowerEnvelopePolicyError.invalidVisualHeadroomFraction
        }
        guard upwardHysteresisFraction.isFinite, upwardHysteresisFraction >= 0 else {
            throw LearnedObservedPowerEnvelopePolicyError.invalidUpwardHysteresisFraction
        }
        guard downwardHysteresisFraction.isFinite,
              downwardHysteresisFraction >= 0,
              downwardHysteresisFraction <= 1 else {
            throw LearnedObservedPowerEnvelopePolicyError.invalidDownwardHysteresisFraction
        }
        guard downwardAdaptationFraction.isFinite,
              downwardAdaptationFraction > 0,
              downwardAdaptationFraction <= 1 else {
            throw LearnedObservedPowerEnvelopePolicyError.invalidDownwardAdaptationFraction
        }

        self.minimumPositiveSampleCount = minimumPositiveSampleCount
        self.windowCapacity = windowCapacity
        self.upperPercentile = upperPercentile
        self.visualHeadroomFraction = visualHeadroomFraction
        self.upwardHysteresisFraction = upwardHysteresisFraction
        self.downwardHysteresisFraction = downwardHysteresisFraction
        self.downwardAdaptationFraction = downwardAdaptationFraction
    }
}

public enum LearnedObservedPowerEnvelopeError: Error, Equatable, Sendable {
    case identityMismatch
    case nonVerifiedEvidence
    case nonMonotonicMeasurement
    case staleContinuityGeneration
}

/// Learns a stable *observed* visual full-power region from repeated verified positive power samples.
///
/// This is not a rated motor/controller maximum. A single spike cannot become the learned ceiling unless
/// the caller deliberately configures a percentile/window policy that permits it. Downward adaptation is
/// explicitly slower than upward adaptation so the cockpit scale does not resize constantly.
public struct LearnedObservedPowerEnvelope: Sendable {
    public let identity: PropulsionGaugeIdentity
    public let policy: LearnedObservedPowerEnvelopePolicy

    private var recentPositiveWatts: [Double] = []
    private var hasObservation = false
    private var latestObservationUptimeNanoseconds: UInt64 = 0
    private var latestContinuityGeneration: UInt64 = 0
    private var learnedCeilingWatts: Double?

    public private(set) var acceptedObservationCount: Int = 0

    public init(identity: PropulsionGaugeIdentity, policy: LearnedObservedPowerEnvelopePolicy) {
        self.identity = identity
        self.policy = policy
    }

    public var currentScale: PropulsionGaugeScale? {
        learnedCeilingWatts.map {
            .learnedObserved(identity: identity, ceilingWatts: $0)
        }
    }

    public var currentLearnedCeilingWatts: Double? {
        learnedCeilingWatts
    }

    public var positiveObservationCount: Int {
        recentPositiveWatts.count
    }

    public mutating func observe(_ sample: PropulsionPowerSample) throws {
        guard sample.identity == identity else {
            throw LearnedObservedPowerEnvelopeError.identityMismatch
        }
        guard sample.authority == .verifiedVehicleMeasurement else {
            throw LearnedObservedPowerEnvelopeError.nonVerifiedEvidence
        }

        if hasObservation {
            guard sample.continuityGeneration >= latestContinuityGeneration else {
                throw LearnedObservedPowerEnvelopeError.staleContinuityGeneration
            }
            guard sample.receivedAtUptimeNanoseconds > latestObservationUptimeNanoseconds else {
                throw LearnedObservedPowerEnvelopeError.nonMonotonicMeasurement
            }
        }

        hasObservation = true
        latestObservationUptimeNanoseconds = sample.receivedAtUptimeNanoseconds
        latestContinuityGeneration = sample.continuityGeneration
        acceptedObservationCount += 1

        guard sample.watts > 0 else {
            return
        }

        recentPositiveWatts.append(sample.watts)
        if recentPositiveWatts.count > policy.windowCapacity {
            recentPositiveWatts.removeFirst(recentPositiveWatts.count - policy.windowCapacity)
        }

        guard recentPositiveWatts.count >= policy.minimumPositiveSampleCount else {
            return
        }

        let sorted = recentPositiveWatts.sorted()
        let rawRank = Int(ceil(policy.upperPercentile * Double(sorted.count))) - 1
        let rank = min(sorted.count - 1, max(0, rawRank))
        let percentileWatts = sorted[rank]
        let candidate = percentileWatts * (1 + policy.visualHeadroomFraction)
        guard candidate.isFinite, candidate > 0 else {
            return
        }

        guard let existing = learnedCeilingWatts else {
            learnedCeilingWatts = candidate
            return
        }

        if candidate > existing * (1 + policy.upwardHysteresisFraction) {
            learnedCeilingWatts = candidate
            return
        }

        if candidate < existing * (1 - policy.downwardHysteresisFraction) {
            let adapted = existing * (1 - policy.downwardAdaptationFraction)
                + candidate * policy.downwardAdaptationFraction
            if adapted.isFinite, adapted > 0 {
                learnedCeilingWatts = adapted
            }
        }
    }
}
