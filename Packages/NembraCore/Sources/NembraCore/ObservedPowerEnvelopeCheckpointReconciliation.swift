import Foundation

public extension ObservedPowerEnvelopeCalibrationCheckpoint {
    /// Produces the checkpoint that is safe to persist after a Simulator-QA session.
    ///
    /// Call this when a retained checkpoint already exists. It validates that the
    /// retained checkpoint and current learner share the exact same scope, policy,
    /// and Simulator authority before choosing what may replace durable state.
    /// A lower or not-yet-calibrated current session keeps the retained checkpoint;
    /// only a strictly stronger current-session calibration may replace it.
    ///
    /// This closes the persistence-write side of the retained-floor contract: a
    /// caller must not serialize a fresh lower learner checkpoint over an existing
    /// stronger checkpoint and thereby shrink the gauge on the next relaunch.
    func reconciledSimulatorQACheckpoint(
        with currentSessionLearner: ObservedPowerEnvelopeLearner
    ) throws -> Self {
        let effective = try effectiveSimulatorQACalibration(
            expectedScope: currentSessionLearner.scope,
            expectedPolicy: currentSessionLearner.policy,
            currentSessionLearner: currentSessionLearner
        )

        switch effective.origin {
        case .retainedCheckpoint:
            return self
        case .currentSession:
            return try Self.simulatorQA(from: currentSessionLearner)
        }
    }
}

#if SWIFT_PACKAGE
package extension ObservedPowerEnvelopeCalibrationCheckpoint {
    /// Package-sealed production counterpart to
    /// `reconciledSimulatorQACheckpoint(with:)`.
    ///
    /// The trusted vehicle integration should use this path whenever durable
    /// verified-physical calibration already exists. The authority/scope/policy
    /// checks happen before any replacement checkpoint can be produced.
    func reconciledVerifiedVehicleMeasurementCheckpoint(
        with currentSessionLearner: ObservedPowerEnvelopeLearner
    ) throws -> Self {
        let effective = try effectiveVerifiedVehicleCalibration(
            expectedScope: currentSessionLearner.scope,
            expectedPolicy: currentSessionLearner.policy,
            currentSessionLearner: currentSessionLearner
        )

        switch effective.origin {
        case .retainedCheckpoint:
            return self
        case .currentSession:
            return try Self.verifiedVehicleMeasurements(from: currentSessionLearner)
        }
    }
}
#endif
