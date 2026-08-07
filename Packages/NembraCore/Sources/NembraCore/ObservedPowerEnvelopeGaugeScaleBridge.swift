import Foundation

public extension PropulsionGaugeScale {
    /// Adapts a validated retained observed-envelope calibration into the same
    /// presentation-scale type used by a live calibration without reconstructing
    /// `ObservedPowerEnvelopeCalibration` or promoting retained state into fresh
    /// telemetry evidence.
    ///
    /// The restored calibration itself is the authority token. Simulator restore
    /// is public QA-only; verified physical restore is package-sealed upstream.
    static func observedEnvelope(
        _ calibration: ObservedPowerEnvelopeRestoredCalibration
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
        case (.simulatorQA, .simulatorQA):
            return try simulator(
                identity: identity,
                ceilingWatts: calibration.learnedGaugeScaleWatts
            )

        case (.verifiedVehicleIdentity, .verifiedVehicleMeasurement):
#if SWIFT_PACKAGE
            return try verifiedObservedEnvelope(
                identity: identity,
                ceilingWatts: calibration.learnedGaugeScaleWatts
            )
#else
            // Direct-source app builds intentionally cannot manufacture verified
            // presentation-scale authority from a separate file. A future trusted
            // app bridge must preserve the same explicit authority boundary.
            throw PropulsionGaugeScaleError.envelopeAuthorityMismatch
#endif

        default:
            throw PropulsionGaugeScaleError.envelopeAuthorityMismatch
        }
    }

    /// Convenience projection for the already-reconciled relaunch result. The
    /// caller can keep `effectiveCalibration.origin` separately for provenance;
    /// the resulting scale carries only presentation-scale authority and identity.
    static func observedEnvelope(
        _ effectiveCalibration: ObservedPowerEnvelopeEffectiveCalibration
    ) throws -> Self {
        try observedEnvelope(effectiveCalibration.calibration)
    }
}
