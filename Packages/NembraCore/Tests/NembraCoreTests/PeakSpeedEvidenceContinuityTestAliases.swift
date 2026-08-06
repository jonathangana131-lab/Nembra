@testable import NembraCore

// Test-target-only aliases keep the existing focused assertions compiling while
// the production enum uses evidence-loss wording that does not imply continuous
// physical sampling. These aliases are not part of NembraCore's public API.
extension PeakSpeedObservationContinuity {
    static var uninterruptedAcceptedObservations: Self {
        .noRecordedSelectedSourceEvidenceLoss
    }

    static var partialAcceptedObservations: Self {
        .partialSelectedSourceEvidence
    }
}
