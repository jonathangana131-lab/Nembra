/// Explains why a learned-range estimate is intentionally withheld from Nembra's
/// unqualified primary numeric readout.
///
/// These reasons are presentation metadata only. They are never battery evidence,
/// range-learning input, persisted telemetry, or physical ES80 claims.
public enum AdaptiveRangePrimaryPresentationReason: Equatable, Sendable {
    case noEstimate
    case retainedEstimateRequiresQualifier
    case provisionalSeed
    case learningConfidence
    case lowConfidenceRequiresQualifier
}

/// Truth-preserving projection from owner-bound adaptive range into a primary
/// battery/range instrument.
public enum AdaptiveRangePrimaryPresentationDecision: Equatable, Sendable {
    case valueMeters(Double)
    case learning(AdaptiveRangePrimaryPresentationReason)
    case unavailable(AdaptiveRangePrimaryPresentationReason)
}

/// Conservative policy for Nembra's unqualified primary learned-range number.
///
/// This successor intentionally does not accept a `BatteryEvidenceStreamValidator`.
/// `AdaptiveBatteryRangeLiveEstimate` already carries the opaque process-local currentness
/// lease minted by `AcceptedBatterySOCStream`; presentation may ask only whether that lease is
/// still current. A stale copied validator, matching receipt metadata under a fresh owner, or
/// persisted data therefore cannot re-mint a live primary number.
///
/// A numeric primary value is eligible only when the owner-bound estimate remains current, the
/// estimate is learned rather than provisional, and confidence is normal/high. Retained,
/// provisional, learning, and low-confidence values fail closed without inventing an advertised
/// range × battery-percent fallback.
public struct AdaptiveBatteryRangePrimaryPresentationPolicy: Equatable, Sendable {
    public init() {}

    public func resolve(
        liveEstimate: AdaptiveBatteryRangeLiveEstimate?
    ) -> AdaptiveRangePrimaryPresentationDecision {
        guard let liveEstimate else {
            return .unavailable(.noEstimate)
        }

        guard liveEstimate.isCurrent else {
            return .unavailable(.retainedEstimateRequiresQualifier)
        }

        let estimate = liveEstimate.estimate
        guard estimate.basis == .learned else {
            return .learning(.provisionalSeed)
        }

        switch estimate.confidence {
        case .learning:
            return .learning(.learningConfidence)
        case .low:
            return .learning(.lowConfidenceRequiresQualifier)
        case .normal, .high:
            return .valueMeters(estimate.presentedRemainingMeters)
        }
    }
}
