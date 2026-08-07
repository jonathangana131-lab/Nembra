import Foundation

public extension ObservedPowerEnvelopeCalibrationCheckpoint {
    /// Safe replacement path when a Simulator-QA checkpoint already exists.
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
    /// Package-sealed production counterpart to the Simulator reconciliation path.
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
