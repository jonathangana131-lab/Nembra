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
/// - backed by a `VehicleState` whose canonical `dataAvailability` is `.live`; and
/// - finite and non-negative after the adaptive model's own presentation smoothing.
///
/// The public API intentionally accepts the canonical `VehicleState` rather than a
/// caller-supplied `VehicleDataAvailability`. Freshness is derived inside NembraCore,
/// so a Dashboard integration cannot accidentally pass `.live` for retained/no-data
/// state through this presentation API. This also keeps the API valid if the app later
/// links NembraCore as a separate module, because `VehicleState.dataAvailability` does
/// not need to be exposed to the app caller.
///
/// This type is deliberately only a presentation policy. It does not establish that
/// an upstream `.authoritativeMeasurement` claim is itself trustworthy. Production
/// integration must consume an adaptive-range parent whose authoritative SoC and
/// derived-estimate construction/import boundaries have been sealed by the accepted
/// battery/range truth pipeline before this policy's numeric decision can be treated
/// as production truth.
///
/// States that may become displayable later with an explicit qualifier remain
/// withheld here until such a qualifier exists. This prevents UI integration from
/// silently flattening stronger provenance/confidence semantics into one number.
public struct AdaptiveBatteryRangePrimaryPresentationPolicy: Equatable, Sendable {
    public init() {}

    public func resolve(
        estimate: AdaptiveBatteryRangeEstimate?,
        vehicleState: VehicleState
    ) -> AdaptiveRangePrimaryPresentationDecision {
        resolve(
            estimate: estimate,
            dataAvailability: vehicleState.dataAvailability
        )
    }

    private func resolve(
        estimate: AdaptiveBatteryRangeEstimate?,
        dataAvailability: VehicleDataAvailability
    ) -> AdaptiveRangePrimaryPresentationDecision {
        // If there is no confirmed vehicle data at all, any attached range is stale or
        // otherwise detached from a legitimate vehicle snapshot. Availability wins.
        if dataAvailability == .unavailable {
            return .unavailable(.vehicleDataUnavailable)
        }

        // Retained status only explains why an otherwise-usable range is withheld.
        // Do not claim a value merely needs a "last known" qualifier when there is no
        // estimate to qualify or its presentation number is malformed.
        guard let estimate else {
            return .unavailable(.noEstimate)
        }

        guard estimate.presentedRemainingMeters.isFinite,
              estimate.presentedRemainingMeters >= 0 else {
            return .unavailable(.invalidPresentedRange)
        }

        if dataAvailability == .retained {
            return .unavailable(.retainedVehicleDataRequiresQualifier)
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
