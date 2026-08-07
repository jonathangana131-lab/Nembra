import NembraCore

// Simulation-test-only compatibility fixtures for adapter tests that predate
// NembraCore's newer ambiguity-duration/gap evidence requirements. These
// overloads never enter a product target and must not be read as outdoor policy.
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
