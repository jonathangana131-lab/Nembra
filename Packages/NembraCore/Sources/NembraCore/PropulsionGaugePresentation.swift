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

    fileprivate var isStructurallyValid: Bool {
        guard !vehicleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return modeKey.map {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ?? true
    }
}

public enum PropulsionPowerSampleError: Error, Equatable, Sendable {
    case invalidIdentity
    case invalidWatts
}

/// One accepted propulsion-power observation. This is intentionally distinct from every render frame.
///
/// The type currently models nonnegative propulsion output only. Regenerative/reverse presentation must
/// remain unavailable until a separate authoritative negative-current/power semantic is physically verified.
public struct PropulsionPowerSample: Equatable, Sendable {
    public let identity: PropulsionGaugeIdentity
    public let watts: Double
    /// Source-owned total-order receipt identity inside one continuity generation.
    /// This is chronology evidence, not power evidence.
    public let receiptSequenceNumber: UInt64
    public let receivedAtUptimeNanoseconds: UInt64
    /// Source-owned continuity/clock generation. A strictly newer generation may
    /// legitimately restart its receipt-sequence and uptime epochs.
    public let continuityGeneration: UInt64
    public let authority: PropulsionPowerSampleAuthority

    private init(
        identity: PropulsionGaugeIdentity,
        watts: Double,
        receiptSequenceNumber: UInt64,
        receivedAtUptimeNanoseconds: UInt64,
        continuityGeneration: UInt64,
        authority: PropulsionPowerSampleAuthority
    ) {
        self.identity = identity
        self.watts = watts
        self.receiptSequenceNumber = receiptSequenceNumber
        self.receivedAtUptimeNanoseconds = receivedAtUptimeNanoseconds
        self.continuityGeneration = continuityGeneration
        self.authority = authority
    }

    /// Simulator convenience: when no explicit synthetic sequence is supplied,
    /// uptime is reused only as Simulator-owned ordering metadata. Production
    /// verified samples must always provide their real source-owned receipt order.
    public static func simulator(
        identity: PropulsionGaugeIdentity,
        watts: Double,
        receiptSequenceNumber: UInt64? = nil,
        receivedAtUptimeNanoseconds: UInt64,
        continuityGeneration: UInt64
    ) throws -> Self {
        try validated(
            identity: identity,
            watts: watts,
            receiptSequenceNumber: receiptSequenceNumber ?? receivedAtUptimeNanoseconds,
            receivedAtUptimeNanoseconds: receivedAtUptimeNanoseconds,
            continuityGeneration: continuityGeneration,
            authority: .simulator
        )
    }

#if SWIFT_PACKAGE
    package static func verifiedVehicleMeasurement(
        identity: PropulsionGaugeIdentity,
        watts: Double,
        receiptSequenceNumber: UInt64,
        receivedAtUptimeNanoseconds: UInt64,
        continuityGeneration: UInt64
    ) throws -> Self {
        try validated(
            identity: identity,
            watts: watts,
            receiptSequenceNumber: receiptSequenceNumber,
            receivedAtUptimeNanoseconds: receivedAtUptimeNanoseconds,
            continuityGeneration: continuityGeneration,
            authority: .verifiedVehicleMeasurement
        )
    }
#else
    fileprivate static func verifiedVehicleMeasurement(
        identity: PropulsionGaugeIdentity,
        watts: Double,
        receiptSequenceNumber: UInt64,
        receivedAtUptimeNanoseconds: UInt64,
        continuityGeneration: UInt64
    ) throws -> Self {
        try validated(
            identity: identity,
            watts: watts,
            receiptSequenceNumber: receiptSequenceNumber,
            receivedAtUptimeNanoseconds: receivedAtUptimeNanoseconds,
            continuityGeneration: continuityGeneration,
            authority: .verifiedVehicleMeasurement
        )
    }
#endif

    private static func validated(
        identity: PropulsionGaugeIdentity,
        watts: Double,
        receiptSequenceNumber: UInt64,
        receivedAtUptimeNanoseconds: UInt64,
        continuityGeneration: UInt64,
        authority: PropulsionPowerSampleAuthority
    ) throws -> Self {
        guard identity.isStructurallyValid else {
            throw PropulsionPowerSampleError.invalidIdentity
        }
        guard watts.isFinite, watts >= 0 else {
            throw PropulsionPowerSampleError.invalidWatts
        }

        return Self(
            identity: identity,
            watts: watts,
            receiptSequenceNumber: receiptSequenceNumber,
            receivedAtUptimeNanoseconds: receivedAtUptimeNanoseconds,
            continuityGeneration: continuityGeneration,
            authority: authority
        )
    }
}

public enum PropulsionGaugeScaleOrigin: String, Equatable, Sendable {
    /// Presentation scale produced by a separately qualified verified observed-power envelope.
    case verifiedObservedEnvelope
    /// Explicitly synthetic scale for Simulator/runtime visual QA.
    case simulator
}

public enum PropulsionGaugeScaleError: Error, Equatable, Sendable {
    case invalidIdentity
    case invalidCeiling
    case envelopeAuthorityMismatch
}

/// Presentation scale only. It does not learn a ceiling and never asserts a rated/certified hardware maximum.
/// Every scale is bound to the same vehicle/mode identity as the observations it is allowed to normalize.
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
        try validated(identity: identity, ceilingWatts: ceilingWatts, origin: .simulator)
    }

#if SWIFT_PACKAGE
    /// Adapter entry point for a separately qualified verified observed-power envelope.
    /// Package sealing prevents generic UI/client code from minting physical scale authority.
    package static func verifiedObservedEnvelope(
        identity: PropulsionGaugeIdentity,
        ceilingWatts: Double
    ) throws -> Self {
        try validated(
            identity: identity,
            ceilingWatts: ceilingWatts,
            origin: .verifiedObservedEnvelope
        )
    }
#else
    fileprivate static func verifiedObservedEnvelope(
        identity: PropulsionGaugeIdentity,
        ceilingWatts: Double
    ) throws -> Self {
        try validated(
            identity: identity,
            ceilingWatts: ceilingWatts,
            origin: .verifiedObservedEnvelope
        )
    }
#endif

    /// Maps the canonical observed-envelope capability into presentation authority
    /// without exposing a raw verified-scale factory to ordinary app/UI code.
    /// The calibration itself is the sealed authority token: mismatched identity
    /// and evidence authorities fail closed rather than being upgraded here.
    public static func observedEnvelope(
        _ calibration: ObservedPowerEnvelopeCalibration
    ) throws -> Self {
        let identity = PropulsionGaugeIdentity(
            vehicleID: calibration.scope.vehicleIdentityKey,
            modeKey: calibration.scope.confirmedModeKey
        )
        guard identity.isStructurallyValid else {
            throw PropulsionGaugeScaleError.invalidIdentity
        }

        switch (calibration.scope.identityAuthority, calibration.evidenceAuthority) {
        case (.verifiedVehicleIdentity, .verifiedVehicleMeasurement):
            return try verifiedObservedEnvelope(
                identity: identity,
                ceilingWatts: calibration.learnedGaugeScaleWatts
            )
        case (.simulatorQA, .simulatorQA):
            return try simulator(
                identity: identity,
                ceilingWatts: calibration.learnedGaugeScaleWatts
            )
        default:
            throw PropulsionGaugeScaleError.envelopeAuthorityMismatch
        }
    }

    private static func validated(
        identity: PropulsionGaugeIdentity,
        ceilingWatts: Double,
        origin: PropulsionGaugeScaleOrigin
    ) throws -> Self {
        guard identity.isStructurallyValid else {
            throw PropulsionGaugeScaleError.invalidIdentity
        }
        guard ceilingWatts.isFinite, ceilingWatts > 0 else {
            throw PropulsionGaugeScaleError.invalidCeiling
        }
        return Self(identity: identity, ceilingWatts: ceilingWatts, origin: origin)
    }
}

public enum PropulsionGaugeMotionPolicyError: Error, Equatable, Sendable {
    case invalidStaleInterval
    case fallResponseSlowerThanRise
}

/// Display-clock timing only. These values do not define BLE cadence or physical scooter dynamics.
/// A zero rise or fall settling duration deliberately snaps that direction to the accepted target,
/// allowing Reduce Motion presentation without changing measurement truth.
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
        guard staleAfterNanoseconds > 0 else {
            throw PropulsionGaugeMotionPolicyError.invalidStaleInterval
        }
        guard fallSettlingDurationNanoseconds <= riseSettlingDurationNanoseconds else {
            throw PropulsionGaugeMotionPolicyError.fallResponseSlowerThanRise
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
    /// Explicit source/session unavailability or invalid render chronology. Disconnect is never converted into measured zero.
    case unavailable
}

public enum PropulsionGaugeFrameOrigin: String, Equatable, Sendable {
    /// The rendered value equals the latest accepted measurement.
    case acceptedMeasurement
    /// Render-only motion between accepted measurements.
    case visuallyInterpolated
    /// Exact last accepted measurement retained after its live window expired.
    case retainedAcceptedMeasurement
    /// The caller requested a display frame before the newest accepted receipt existed.
    case invalidRenderClock
    case unavailable
}

/// Render-only gauge state. `displayWatts` and normalized fractions must never enter telemetry evidence,
/// ride statistics, persistence, peak evidence, battery learning, or protocol claims.
public struct PropulsionGaugeFrame: Equatable, Sendable {
    public let availability: PropulsionGaugeAvailability
    public let origin: PropulsionGaugeFrameOrigin
    public let displayWatts: Double?
    public let latestAcceptedWatts: Double?
    public let latestAcceptedReceiptSequenceNumber: UInt64?
    public let latestAcceptedUptimeNanoseconds: UInt64?
    public let latestAuthority: PropulsionPowerSampleAuthority?
    public let normalizedPropulsion: Double?
    public let acceptedPeakNormalized: Double?
    public let scaleOrigin: PropulsionGaugeScaleOrigin?
}

public enum PropulsionGaugeDisplayError: Error, Equatable, Sendable {
    case identityMismatch
    case nonIncreasingReceiptSequence
    case nonMonotonicMeasurement
    case staleContinuityGeneration
    case retiredContinuityGeneration
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
    private var latestAcceptedReceiptSequenceNumber: UInt64 = 0
    private var latestAcceptedUptimeNanoseconds: UInt64 = 0
    private var latestContinuityGeneration: UInt64 = 0
    private var latestAuthority: PropulsionPowerSampleAuthority = .simulator

    /// Receipt chronology is scoped to the source-owned continuity generation.
    /// A newer generation is an explicit clock/order epoch and may restart both
    /// sequence and uptime. Within one generation, sequence is strict and uptime
    /// is nondecreasing.
    private var lastSeenContinuityGeneration: UInt64?
    private var lastSeenReceiptSequenceNumber: UInt64?

    private var transitionAnchorWatts = 0.0
    private var transitionTargetWatts = 0.0
    private var transitionStartUptimeNanoseconds: UInt64 = 0
    private var transitionSettlingDurationNanoseconds: UInt64 = 0

    private var acceptedPeakWatts = 0.0
    private var acceptedPeakUptimeNanoseconds: UInt64 = 0
    private var explicitlyUnavailable = false
    /// Once an explicit source/session interruption occurs, callbacks from that
    /// generation or any older generation may not reopen live presentation.
    private var retiredContinuityGeneration: UInt64?

    public init(identity: PropulsionGaugeIdentity, policy: PropulsionGaugeMotionPolicy) {
        self.identity = identity
        self.policy = policy
    }

    public mutating func accept(_ sample: PropulsionPowerSample) throws {
        guard sample.identity == identity else {
            throw PropulsionGaugeDisplayError.identityMismatch
        }

        if let retiredContinuityGeneration,
           sample.continuityGeneration <= retiredContinuityGeneration {
            throw PropulsionGaugeDisplayError.retiredContinuityGeneration
        }

        if let lastSeenContinuityGeneration {
            guard sample.continuityGeneration >= lastSeenContinuityGeneration else {
                throw PropulsionGaugeDisplayError.staleContinuityGeneration
            }

            if sample.continuityGeneration == lastSeenContinuityGeneration {
                if let lastSeenReceiptSequenceNumber {
                    guard sample.receiptSequenceNumber > lastSeenReceiptSequenceNumber else {
                        throw PropulsionGaugeDisplayError.nonIncreasingReceiptSequence
                    }
                }
            } else {
                // A source-owned newer continuity generation is the mechanical
                // boundary that permits receipt-sequence and uptime epoch restart.
                self.lastSeenContinuityGeneration = sample.continuityGeneration
                self.lastSeenReceiptSequenceNumber = nil
            }
        } else {
            lastSeenContinuityGeneration = sample.continuityGeneration
        }

        // Consume the receipt identity before secondary same-generation uptime
        // validation. A newer malformed callback cannot later be rewritten, and
        // a delayed lower sequence cannot re-enter that generation.
        lastSeenReceiptSequenceNumber = sample.receiptSequenceNumber

        if hasMeasurement {
            guard sample.continuityGeneration >= latestContinuityGeneration else {
                throw PropulsionGaugeDisplayError.staleContinuityGeneration
            }
            if sample.continuityGeneration == latestContinuityGeneration {
                guard sample.receivedAtUptimeNanoseconds >= latestAcceptedUptimeNanoseconds else {
                    throw PropulsionGaugeDisplayError.nonMonotonicMeasurement
                }
            }
        }

        let sharesContinuity: Bool
        if hasMeasurement,
           !explicitlyUnavailable,
           sample.authority == latestAuthority,
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
        latestAcceptedReceiptSequenceNumber = sample.receiptSequenceNumber
        latestAcceptedUptimeNanoseconds = sample.receivedAtUptimeNanoseconds
        latestContinuityGeneration = sample.continuityGeneration
        latestAuthority = sample.authority
        explicitlyUnavailable = false
        retiredContinuityGeneration = nil
    }

    /// Explicitly ends live presentation without manufacturing a zero-power sample.
    /// If a generation has already produced accepted evidence, it is retired: a
    /// delayed callback from that disconnected/interrupted generation cannot
    /// resurrect the gauge. Resume requires a genuinely newer source generation.
    public mutating func markUnavailable() {
        explicitlyUnavailable = true
        if hasMeasurement {
            retiredContinuityGeneration = latestContinuityGeneration
        }
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
                latestAcceptedReceiptSequenceNumber: nil,
                latestAcceptedUptimeNanoseconds: nil,
                latestAuthority: nil,
                normalizedPropulsion: nil,
                acceptedPeakNormalized: nil,
                scaleOrigin: nil
            )
        }

        if now < latestAcceptedUptimeNanoseconds {
            return PropulsionGaugeFrame(
                availability: .unavailable,
                origin: .invalidRenderClock,
                displayWatts: nil,
                latestAcceptedWatts: nil,
                latestAcceptedReceiptSequenceNumber: nil,
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
                latestAcceptedReceiptSequenceNumber: latestAcceptedReceiptSequenceNumber,
                latestAcceptedUptimeNanoseconds: latestAcceptedUptimeNanoseconds,
                latestAuthority: latestAuthority,
                normalizedPropulsion: nil,
                acceptedPeakNormalized: nil,
                scaleOrigin: nil
            )
        }

        let age = now - latestAcceptedUptimeNanoseconds
        if age > policy.staleAfterNanoseconds {
            return PropulsionGaugeFrame(
                availability: .retained,
                origin: .retainedAcceptedMeasurement,
                displayWatts: latestAcceptedWatts,
                latestAcceptedWatts: latestAcceptedWatts,
                latestAcceptedReceiptSequenceNumber: latestAcceptedReceiptSequenceNumber,
                latestAcceptedUptimeNanoseconds: latestAcceptedUptimeNanoseconds,
                latestAuthority: latestAuthority,
                normalizedPropulsion: nil,
                acceptedPeakNormalized: nil,
                scaleOrigin: nil
            )
        }

        let displayWatts = liveMotionValue(atUptimeNanoseconds: now)
        let isAtAcceptedMeasurement = transitionSettlingDurationNanoseconds == 0
            || now - transitionStartUptimeNanoseconds >= transitionSettlingDurationNanoseconds
            || displayWatts == latestAcceptedWatts

        let compatibleScale = scale.flatMap { candidate -> PropulsionGaugeScale? in
            guard candidate.identity == identity else { return nil }

            switch (candidate.origin, latestAuthority) {
            case (.verifiedObservedEnvelope, .verifiedVehicleMeasurement),
                 (.simulator, .simulator):
                return candidate
            default:
                return nil
            }
        }

        let normalized = compatibleScale.map {
            min(1, max(0, displayWatts / $0.ceilingWatts))
        }

        let peakAge = now >= acceptedPeakUptimeNanoseconds
            ? now - acceptedPeakUptimeNanoseconds
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
            latestAcceptedReceiptSequenceNumber: latestAcceptedReceiptSequenceNumber,
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

        let visualWatts = transitionAnchorWatts * (1 - progress)
            + transitionTargetWatts * progress
        if visualWatts.isFinite {
            return visualWatts
        }

        // Fail closed to real accepted endpoints rather than ever exposing a fabricated non-finite frame.
        return progress < 0.5 ? transitionAnchorWatts : transitionTargetWatts
    }
}
