import Testing

@testable import NembraCore

@Suite("Navigation arrival threshold regressions")
struct NavigationArrivalThresholdRegressionTests {
    private func route() throws -> NavigationRouteSnapshot {
        let a = try NavigationRouteCoordinate(latitude: 45, longitude: -122)
        let b = try NavigationRouteCoordinate(latitude: 45.0005, longitude: -122.0005)
        let c = try NavigationRouteCoordinate(latitude: 45.001, longitude: -122.001)
        let first = try NavigationRouteStepSnapshot(
            geometry: [a, b],
            instructions: "Continue",
            notice: nil,
            distanceMeters: 70,
            transportMode: .cycling
        )
        let final = try NavigationRouteStepSnapshot(
            geometry: [b, c],
            instructions: "Arrive",
            notice: nil,
            distanceMeters: 30,
            transportMode: .cycling
        )
        return try NavigationRouteSnapshot(
            provenance: .appleMapKitCycling(),
            name: "Threshold route",
            geometry: [a, b, c],
            steps: [first, final],
            distanceMeters: 100,
            expectedTravelTimeSeconds: 60,
            hasHighways: false,
            hasTolls: false,
            advisoryNotices: []
        )
    }

    private func run(
        stepRemaining: Double,
        routeRemaining: Double
    ) throws -> NavigationArrivalObservationResult {
        let selectedRoute = try route()
        var guidance = NavigationGuidanceProgressTracker()
        let token = try guidance.select(route: selectedRoute)
        let policy = try NavigationArrivalEvidencePolicy(
            maximumFinalStepDistanceRemainingMeters: 5,
            maximumRouteDistanceRemainingMeters: 8,
            minimumQualifyingObservationCount: 2,
            minimumSustainedDurationNanoseconds: 1
        )
        var arrival = NavigationArrivalEvidenceTracker(policy: policy)
        try arrival.select(token: token, route: selectedRoute)
        let sample = try NavigationGuidanceProgressObservation(
            selectionToken: token,
            receivedAtUptimeNanoseconds: 100,
            stepIndex: 1,
            distanceRemainingOnStepMeters: stepRemaining,
            distanceRemainingOnRouteMeters: routeRemaining,
            isProgressAssignmentConfident: true
        )
        let accepted = try guidance.observe(sample)
        #expect(accepted)
        return try arrival.observeAccepted(
            sample,
            resultingGuidanceState: guidance.state
        )
    }

    @Test("final-step threshold is independently required")
    func finalStepThresholdRequired() throws {
        let result = try run(stepRemaining: 6, routeRemaining: 7)
        #expect(result == .awaitingEvidence)
    }

    @Test("total-route threshold is independently required")
    func routeThresholdRequired() throws {
        let result = try run(stepRemaining: 4, routeRemaining: 9)
        #expect(result == .awaitingEvidence)
    }

    @Test("both proximity thresholds must qualify together")
    func bothThresholdsQualify() throws {
        let result = try run(stepRemaining: 4, routeRemaining: 7)
        #expect(result == .candidate)
    }
}
