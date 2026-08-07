import NembraCore

// Test-target-only compatibility fixtures for adapter tests that predate the
// newer ambiguity-duration/gap evidence requirements in NembraCore. These
// overloads are intentionally internal to this test target: Nembra production
// code still has no default outdoor navigation thresholds.
extension NavigationRouteGeometryMatchingPolicy {
    init(
        maximumRouteDistanceMeters: Double,
        minimumStepAmbiguitySeparationMeters: Double
    ) throws {
        try self.init(
            maximumRouteDistanceMeters: maximumRouteDistanceMeters,
            minimumStepAmbiguitySeparationMeters: minimumStepAmbiguitySeparationMeters,
            minimumWithinGeometryProgressSeparationMeters: minimumStepAmbiguitySeparationMeters
        )
    }
}

extension NavigationReroutePolicy {
    init(
        minimumDeviationDistanceMeters: Double,
        requiredConsecutiveAcceptedSamples: Int,
        rerouteCooldownNanoseconds: UInt64
    ) throws {
        try self.init(
            minimumDeviationDistanceMeters: minimumDeviationDistanceMeters,
            requiredConsecutiveAcceptedSamples: requiredConsecutiveAcceptedSamples,
            minimumConsecutiveDeviationDurationNanoseconds: 1,
            maximumAcceptedObservationGapNanoseconds: max(1, rerouteCooldownNanoseconds),
            rerouteCooldownNanoseconds: rerouteCooldownNanoseconds
        )
    }
}
