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
    case invalidEstimateStructure
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
/// - structurally valid under the adaptive-range parent's own derived-range invariants;
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
/// Structural validation is repeated here as defense in depth because the current app
/// build graph can compile NembraCore sources directly into the app module. Generic
/// Codable validation upstream is necessary but cannot protect against a same-module
/// caller manually constructing a malformed estimate in memory.
///
/// This type is deliberately only a presentation policy. It does not establish that
/// an upstream `.authoritativeMeasurement` claim is itself trustworthy. Production
/// integration must consume an adaptive-range parent whose authoritative SoC,
/// learning-window, distance/classification, and derived-estimate authority boundaries
/// have been sealed by the accepted battery/range truth pipeline before this policy's
/// numeric decision can be treated as production truth.
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

        guard isStructurallyValid(estimate) else {
            return .unavailable(.invalidEstimateStructure)
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

    /// Mirrors the policy-independent structural guards already enforced by the
    /// parent's Codable restore boundary. Do not add a cap on
    /// `presentedRemainingMeters`: valid smoothing may temporarily lag a changed
    /// efficiency and exceed the current full-charge-equivalent range.
    private func isStructurallyValid(_ estimate: AdaptiveBatteryRangeEstimate) -> Bool {
        let fullChargeRange = estimate.metersPerPercentagePoint * 100
        let tolerance = max(1, abs(fullChargeRange)) * 1e-12

        return estimate.rawRemainingMeters.isFinite
            && estimate.rawRemainingMeters >= 0
            && estimate.metersPerPercentagePoint.isFinite
            && estimate.metersPerPercentagePoint > 0
            && fullChargeRange.isFinite
            && estimate.rawRemainingMeters <= fullChargeRange + tolerance
            && (estimate.basis != .provisionalSeed || estimate.confidence == .learning)
    }
}
