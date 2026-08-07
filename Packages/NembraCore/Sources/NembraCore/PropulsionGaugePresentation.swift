import Foundation

public enum PropulsionPowerSampleAuthority: String, Codable, Hashable, Sendable {
    /// Production-only authority. Construction is package-sealed so UI or generic clients cannot mint it.
    case verifiedVehicleMeasurement
    /// Explicitly synthetic evidence for Simulator/runtime visual QA.
    case simulator
}

public enum PropulsionGaugeIdentityError: Error, Equatable, Sendable {
    case invalidVehicleID
    case invalidModeKey
}

public struct PropulsionGaugeIdentity: Hashable, Codable, Sendable {
    public let vehicleID: String
    public let modeKey: String?

    private enum CodingKeys: String, CodingKey {
        case vehicleID
        case modeKey
    }

    public init(vehicleID: String, modeKey: String? = nil) throws {
        guard !vehicleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PropulsionGaugeIdentityError.invalidVehicleID
        }
        if let modeKey,
           modeKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw PropulsionGaugeIdentityError.invalidModeKey
        }
        self.vehicleID = vehicleID
        self.modeKey = modeKey
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            vehicleID: container.decode(String.self, forKey: .vehicleID),
            modeKey: container.decodeIfPresent(String.self, forKey: .modeKey)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(vehicleID, forKey: .vehicleID)
        try container.encodeIfPresent(modeKey, forKey: .modeKey)
    }

    fileprivate var isStructurallyValid: Bool {
        !vehicleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (modeKey.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? true)
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
    /// Source-owned total-order receipt identity inside one authority + continuity generation.
    /// This is chronology evidence, not power evidence.
    public let receiptSequenceNumber: UInt64
    public let receivedAtUptimeNanoseconds: UInt64
    /// Source-owned continuity/clock generation inside one authority domain. A
    /// strictly newer generation may legitimately restart its receipt-sequence
    /// and uptime epochs.
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
        let identity: PropulsionGaugeIdentity
        do {
            identity = try PropulsionGaugeIdentity(
                vehicleID: calibration.scope.vehicleIdentityKey,
                modeKey: calibration.scope.confirmedModeKey
            )
        } catch {
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

public enum PropulsionGaugeAnimationPolicyError: Error, Equatable, Sendable {
    case fallResponseSlowerThanRise
}

/// Render-clock motion only. This policy may change for visual tuning or Reduce Motion
/// without changing how long an accepted physical measurement remains live evidence.
public struct PropulsionGaugeAnimationPolicy: Equatable, Sendable {
    public let riseSettlingDurationNanoseconds: UInt64
    public let fallSettlingDurationNanoseconds: UInt64
    public let acceptedPeakHoldNanoseconds: UInt64

    public init(
        riseSettlingDurationNanoseconds: UInt64,
        fallSettlingDurationNanoseconds: UInt64,
        acceptedPeakHoldNanoseconds: UInt64
    ) throws {
        guard fallSettlingDurationNanoseconds <= riseSettlingDurationNanoseconds else {
            throw PropulsionGaugeAnimationPolicyError.fallResponseSlowerThanRise
        }

        self.riseSettlingDurationNanoseconds = riseSettlingDurationNanoseconds
        self.fallSettlingDurationNanoseconds = fallSettlingDurationNanoseconds
        self.acceptedPeakHoldNanoseconds = acceptedPeakHoldNanoseconds
    }
}

public enum PropulsionGaugeFreshnessPolicyError: Error, Equatable, Sendable {
    case invalidStaleInterval
}

/// Accepted-measurement currentness only. This is evidence/presentation admission policy,
/// not animation tuning and not a claim about the ES80's BLE publication cadence.
///
/// Once the latest accepted sample is older than this interval, the gauge retains that
/// exact accepted value but stops presenting it as live. A later sample after the same
/// gap also starts a fresh visual segment rather than interpolating across missing evidence.
public struct PropulsionGaugeFreshnessPolicy: Equatable, Sendable {
    public let staleAfterNanoseconds: UInt64

    public init(staleAfterNanoseconds: UInt64) throws {
        guard staleAfterNanoseconds > 0 else {
            throw PropulsionGaugeFreshnessPolicyError.invalidStaleInterval
        }
        self.staleAfterNanoseconds = staleAfterNanoseconds
    }
}

public enum PropulsionGaugeMotionPolicyError: Error, Equatable, Sendable {
    case invalidStaleInterval
    case fallResponseSlowerThanRise
}

/// Compatibility policy for callers that predate the explicit animation/freshness split.
/// New integration code should construct `PropulsionGaugeAnimationPolicy` and
/// `PropulsionGaugeFreshnessPolicy` independently so visual preferences cannot change
/// accepted-measurement currentness.
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

    fileprivate var splitPolicies: (animation: PropulsionGaugeAnimationPolicy, freshness: PropulsionGaugeFreshnessPolicy) {
        // This cannot fail: the compatibility initializer already validates the
        // exact invariants required by both split policies.
        let animation = try! PropulsionGaugeAnimationPolicy(
            riseSettlingDurationNanoseconds: riseSettlingDurationNanoseconds,
            fallSettlingDurationNanoseconds: fallSettlingDurationNanoseconds,
            acceptedPeakHoldNanoseconds: acceptedPeakHoldNanoseconds
        )
        let freshness = try! PropulsionGaugeFreshnessPolicy(
            staleAfterNanoseconds: staleAfterNanoseconds
        )
        return (animation, freshness)
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

private struct PropulsionGaugeChronologyState: Sendable {
    var continuityGeneration: UInt64
    var lastSeenReceiptSequenceNumber: UInt64
    /// Monotonic receive-uptime floor for this authority + generation. If a
    /// newer receipt is rejected for backwards uptime, its sequence remains
    /// consumed while this floor deliberately remains at the last valid uptime.
    var uptimeFloorNanoseconds: UInt64
}

/// Critically damped, retargetable render model for positive propulsion output.
///
/// Measurement and display clocks remain separate: accepted samples change the target, while callers may
/// ask for frames at display refresh rate. The response never predicts beyond the latest accepted target.
public struct PropulsionGaugeDisplayModel: Sendable {
    public let identity: PropulsionGaugeIdentity
    public let animationPolicy: PropulsionGaugeAnimationPolicy
    public let freshnessPolicy: PropulsionGaugeFreshnessPolicy

    /// Compatibility projection for pre-split callers. The display model itself no
    /// longer consults this combined shape for currentness or animation decisions.
    public var policy: PropulsionGaugeMotionPolicy {
        try! PropulsionGaugeMotionPolicy(
            riseSettlingDurationNanoseconds: animationPolicy.riseSettlingDurationNanoseconds,
            fallSettlingDurationNanoseconds: animationPolicy.fallSettlingDurationNanoseconds,
            staleAfterNanoseconds: freshnessPolicy.staleAfterNanoseconds,
            acceptedPeakHoldNanoseconds: animationPolicy.acceptedPeakHoldNanoseconds
        )
    }

    private var hasMeasurement = false
    private var latestAcceptedWatts = 0.0
    private var latestAcceptedReceiptSequenceNumber: UInt64 = 0
    private var latestAcceptedUptimeNanoseconds: UInt64 = 0
    private var latestContinuityGeneration: UInt64 = 0
    private var latestAuthority: PropulsionPowerSampleAuthority = .simulator

    /// Receipt chronology belongs to the authority/source domain that minted it.
    /// Simulator and verified physical streams cannot poison each other's numeric
    /// sequence/generation namespace. Within one authority + generation, receipt
    /// sequence is strict and uptime is nondecreasing. A newer generation resets
    /// that authority's sequence/uptime epoch.
    private var chronologyByAuthority: [PropulsionPowerSampleAuthority: PropulsionGaugeChronologyState] = [:]

    private var transitionAnchorWatts = 0.0
    private var transitionTargetWatts = 0.0
    private var transitionStartUptimeNanoseconds: UInt64 = 0
    private var transitionSettlingDurationNanoseconds: UInt64 = 0

    private var acceptedPeakWatts = 0.0
    private var acceptedPeakUptimeNanoseconds: UInt64 = 0
    private var explicitlyUnavailable = false
    /// An explicit interruption retires only the currently active authority's
    /// source generation. A foreign authority has its own generation namespace.
    private var retiredContinuityGenerationByAuthority: [PropulsionPowerSampleAuthority: UInt64] = [:]

    /// Preferred initializer. Motion and accepted-measurement freshness are deliberately
    /// separate so accessibility/Reduce Motion or visual tuning cannot alter evidence currentness.
    public init(
        identity: PropulsionGaugeIdentity,
        animationPolicy: PropulsionGaugeAnimationPolicy,
        freshnessPolicy: PropulsionGaugeFreshnessPolicy
    ) {
        self.identity = identity
        self.animationPolicy = animationPolicy
        self.freshnessPolicy = freshnessPolicy
    }

    /// Source-compatible adapter for the original combined policy shape.
    public init(identity: PropulsionGaugeIdentity, policy: PropulsionGaugeMotionPolicy) {
        let split = policy.splitPolicies
        self.init(
            identity: identity,
            animationPolicy: split.animation,
            freshnessPolicy: split.freshness
        )
    }

    public mutating func accept(_ sample: PropulsionPowerSample) throws {
        guard sample.identity == identity else {
            throw PropulsionGaugeDisplayError.identityMismatch
        }

        if let retiredGeneration = retiredContinuityGenerationByAuthority[sample.authority],
           sample.continuityGeneration <= retiredGeneration {
            throw PropulsionGaugeDisplayError.retiredContinuityGeneration
        }

        if var chronology = chronologyByAuthority[sample.authority] {
            guard sample.continuityGeneration >= chronology.continuityGeneration else {
                throw PropulsionGaugeDisplayError.staleContinuityGeneration
            }

            if sample.continuityGeneration == chronology.continuityGeneration {
                guard sample.receiptSequenceNumber > chronology.lastSeenReceiptSequenceNumber else {
                    throw PropulsionGaugeDisplayError.nonIncreasingReceiptSequence
                }

                // Consume source-owned receipt identity before the secondary
                // uptime check so a malformed newer callback cannot be rewritten.
                chronology.lastSeenReceiptSequenceNumber = sample.receiptSequenceNumber
                chronologyByAuthority[sample.authority] = chronology

                guard sample.receivedAtUptimeNanoseconds >= chronology.uptimeFloorNanoseconds else {
                    throw PropulsionGaugeDisplayError.nonMonotonicMeasurement
                }

                chronology.uptimeFloorNanoseconds = sample.receivedAtUptimeNanoseconds
                chronologyByAuthority[sample.authority] = chronology
            } else {
                // Strictly newer source generation establishes a fresh clock/order
                // epoch for this authority only.
                chronologyByAuthority[sample.authority] = PropulsionGaugeChronologyState(
                    continuityGeneration: sample.continuityGeneration,
                    lastSeenReceiptSequenceNumber: sample.receiptSequenceNumber,
                    uptimeFloorNanoseconds: sample.receivedAtUptimeNanoseconds
                )
            }
        } else {
            chronologyByAuthority[sample.authority] = PropulsionGaugeChronologyState(
                continuityGeneration: sample.continuityGeneration,
                lastSeenReceiptSequenceNumber: sample.receiptSequenceNumber,
                uptimeFloorNanoseconds: sample.receivedAtUptimeNanoseconds
            )
        }

        let sharesContinuity: Bool
        if hasMeasurement,
           !explicitlyUnavailable,
           sample.authority == latestAuthority,
           sample.continuityGeneration == latestContinuityGeneration {
            // Same-authority chronology validation above guarantees this
            // subtraction cannot underflow.
            let gap = sample.receivedAtUptimeNanoseconds - latestAcceptedUptimeNanoseconds
            sharesContinuity = gap <= freshnessPolicy.staleAfterNanoseconds
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
                ? animationPolicy.riseSettlingDurationNanoseconds
                : animationPolicy.fallSettlingDurationNanoseconds
        } else {
            transitionSettlingDurationNanoseconds = 0
        }

        if !hasMeasurement
            || !sharesContinuity
            || sample.receivedAtUptimeNanoseconds - acceptedPeakUptimeNanoseconds > animationPolicy.acceptedPeakHoldNanoseconds {
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
        retiredContinuityGenerationByAuthority.removeValue(forKey: sample.authority)
    }

    /// Explicitly ends live presentation without manufacturing a zero-power sample.
    /// If a generation has already produced accepted evidence, it is retired only
    /// inside the active authority/source domain. A delayed same-authority callback
    /// cannot resurrect the gauge; a foreign authority does not inherit that floor.
    public mutating func markUnavailable() {
        explicitlyUnavailable = true
        if hasMeasurement {
            let existing = retiredContinuityGenerationByAuthority[latestAuthority]
            retiredContinuityGenerationByAuthority[latestAuthority] = max(
                existing ?? latestContinuityGeneration,
                latestContinuityGeneration
            )
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
        if age > freshnessPolicy.staleAfterNanoseconds {
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
           peakAge <= animationPolicy.acceptedPeakHoldNanoseconds {
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