/// Classifies whether the app is currently presenting live vehicle data or a retained
/// snapshot. Retained data can still be useful elsewhere, but the current primary
/// range readout has no qualifier surface that can truthfully label a retained value.
public enum AdaptiveRangePrimaryVehicleAvailability: Equatable, Sendable {
    case live
    case retained
    case unavailable
}

/// Explains why an adaptive-range estimate was intentionally withheld from the
/// unqualified primary numeric readout.
///
/// This is presentation-policy metadata only. It is never battery evidence and must
/// not be persisted as measured scooter telemetry.
public enum AdaptiveRangePrimaryPresentationReason: Equatable, Sendable {
    case vehicleDataUnavailable
    case retainedVehicleDataRequiresQualifier
    case noEstimate
    case invalidPresentedRange
    case provisionalSeed
    case estimatedSOCRequiresQualifier
    case learningConfidence
    case lowConfidenceRequiresQualifier
}

/// A truth-preserving projection from the adaptive range domain into the current
/// battery instrument contract.
public enum AdaptiveRangePrimaryPresentationDecision: Equatable, Sendable {
    case valueMeters(Double)
    case learning(AdaptiveRangePrimaryPresentationReason)
    case unavailable(AdaptiveRangePrimaryPresentationReason)

    /// Compatibility projection for `BatteryPrimaryReadoutInputs`.
    ///
    /// Detailed withholding reasons remain available on this decision for future
    /// detailed battery UI, while the existing primary readout stays deliberately
    /// simple and never receives an unqualified weak/retained estimate.
    public var primaryReadoutDisplay: BatteryEstimatedRangeDisplay {
        switch self {
        case let .valueMeters(meters):
            return .valueMeters(meters)
        case .learning:
            return .learning
        case .unavailable:
            return .unavailable
        }
    }
}

/// Conservative policy for the current unqualified primary range number.
///
/// A numeric value is eligible only when it is:
/// - based on learned history rather than a provisional cold-start seed;
/// - normal/high confidence rather than learning/low confidence;
/// - calculated from authoritative SoC rather than estimated SoC;
/// - associated with live vehicle data rather than retained/offline data; and
/// - finite and non-negative after the adaptive model's own presentation smoothing.
///
/// This type is deliberately only a presentation policy. It does not establish that
/// an upstream `.authoritativeMeasurement` claim is itself trustworthy. Production
/// integration must consume an adaptive-range parent whose authoritative SoC
/// construction/import boundary has been sealed by the accepted battery/range truth
/// pipeline before this policy's numeric decision can be treated as production truth.
///
/// States that may become displayable later with an explicit qualifier remain
/// withheld here until such a qualifier exists. This prevents UI integration from
/// silently flattening stronger provenance/confidence semantics into one number.
public struct AdaptiveBatteryRangePrimaryPresentationPolicy: Equatable, Sendable {
    public init() {}

    public func resolve(
        estimate: AdaptiveBatteryRangeEstimate?,
        vehicleAvailability: AdaptiveRangePrimaryVehicleAvailability
    ) -> AdaptiveRangePrimaryPresentationDecision {
        switch vehicleAvailability {
        case .unavailable:
            return .unavailable(.vehicleDataUnavailable)
        case .retained:
            return .unavailable(.retainedVehicleDataRequiresQualifier)
        case .live:
            break
        }

        guard let estimate else {
            return .unavailable(.noEstimate)
        }

        guard estimate.presentedRemainingMeters.isFinite,
              estimate.presentedRemainingMeters >= 0 else {
            return .unavailable(.invalidPresentedRange)
        }

        // Estimated SoC is a stronger truth qualifier than whether the range model is
        // provisional or learned. If both are true, fail closed as unavailable rather
        // than presenting a generic "learning" state that hides the weaker SoC source.
        guard estimate.socProvenance == .authoritativeMeasurement else {
            return .unavailable(.estimatedSOCRequiresQualifier)
        }

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
