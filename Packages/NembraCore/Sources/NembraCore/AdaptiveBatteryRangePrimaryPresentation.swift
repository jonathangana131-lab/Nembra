/// Explains why a learned-range estimate is intentionally withheld from Nembra's
/// unqualified primary numeric readout.
///
/// These reasons are presentation metadata only. They are never battery evidence,
/// range-learning input, persisted telemetry, or physical ES80 claims.
public enum AdaptiveRangePrimaryPresentationReason: Equatable, Sendable {
    /// No receipt-bound live estimate is currently available.
    case noEstimate
    /// The estimate was valid when produced, but its exact source receipt is no
    /// longer the validator's current accepted battery evidence.
    case retainedEstimateRequiresQualifier
    /// A conservative cold-start seed is still being used instead of learned
    /// vehicle history.
    case provisionalSeed
    /// Learned history has not yet accumulated the policy's low-confidence floor.
    case learningConfidence
    /// Some learned history exists, but the primary unqualified number remains
    /// withheld until normal confidence is reached.
    case lowConfidenceRequiresQualifier
}

/// Truth-preserving projection from receipt-bound adaptive range into a primary
/// battery/range instrument.
public enum AdaptiveRangePrimaryPresentationDecision: Equatable, Sendable {
    case valueMeters(Double)
    case learning(AdaptiveRangePrimaryPresentationReason)
    case unavailable(AdaptiveRangePrimaryPresentationReason)
}

/// Conservative policy for Nembra's unqualified primary learned-range number.
///
/// The input is deliberately `AdaptiveBatteryRangeLiveEstimate`, not a raw
/// `AdaptiveBatteryRangeEstimate` plus whole-vehicle connection state. The live
/// wrapper is minted only from an accepted SoC anchor and carries the exact source
/// receipt identity used to calculate the estimate. Rechecking that receipt against
/// the owning `BatteryEvidenceStreamValidator` prevents a cached estimate from
/// becoming fresh-looking merely because the vehicle reconnects or some unrelated
/// field is live.
///
/// A numeric primary value is eligible only when the exact source receipt remains
/// current, the estimate is learned rather than provisional, and confidence is
/// normal/high. Retained, provisional, learning, and low-confidence values fail
/// closed without inventing an advertised-range × battery-percent fallback.
public struct AdaptiveBatteryRangePrimaryPresentationPolicy: Equatable, Sendable {
    public init() {}

    public func resolve(
        liveEstimate: AdaptiveBatteryRangeLiveEstimate?,
        acceptedBy validator: BatteryEvidenceStreamValidator
    ) -> AdaptiveRangePrimaryPresentationDecision {
        guard let liveEstimate else {
            return .unavailable(.noEstimate)
        }

        guard liveEstimate.isCurrent(in: validator) else {
            return .unavailable(.retainedEstimateRequiresQualifier)
        }

        let estimate = liveEstimate.estimate

        // `AdaptiveBatteryRangeLiveEstimate` is itself sealed around a model-produced
        // estimate, so presentation does not need a second caller-supplied freshness or
        // provenance flag. Keep the decision surface limited to product-relevant states.
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