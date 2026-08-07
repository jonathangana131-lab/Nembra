import Testing

@testable import NembraCore

@Suite("Navigation arrival backward-progress regression")
struct NavigationArrivalBackwardProgressRegressionTests {
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
            name: "Arrival regression route",
            geometry: [a, b, c],
            steps: [first, final],
            distanceMeters: 100,
            expectedTravelTimeSeconds: 60,
            hasHighways: false,
            hasTolls: false,
            advisoryNotices: []
        )
    }

    private func observation(
        token: NavigationGuidanceSelectionToken,
        uptime: UInt64,
        stepIndex: Int,
        stepRemaining: Double,
        routeRemaining: Double
    ) throws -> NavigationGuidanceProgressObservation {
        try NavigationGuidanceProgressObservation(
            selectionToken: token,
            receivedAtUptimeNanoseconds: uptime,
            stepIndex: stepIndex,
            distanceRemainingOnStepMeters: stepRemaining,
            distanceRemainingOnRouteMeters: routeRemaining,
            isProgressAssignmentConfident: true
        )
    }

    @Test("confident backward-step regression invalidates arrival candidate")
    func backwardStepAmbiguityResetsCandidate() throws {
        let selectedRoute = try route()
        var guidance = NavigationGuidanceProgressTracker()
        let token = try guidance.select(route: selectedRoute)
        let policy = try NavigationArrivalEvidencePolicy(
            maximumFinalStepDistanceRemainingMeters: 5,
            maximumRouteDistanceRemainingMeters: 8,
            minimumQualifyingObservationCount: 3,
            minimumSustainedDurationNanoseconds: 2_000
        )
        var arrival = NavigationArrivalEvidenceTracker(policy: policy)
        try arrival.select(token: token, route: selectedRoute)

        let candidateSample = try observation(
            token: token,
            uptime: 100,
            stepIndex: 1,
            stepRemaining: 4,
            routeRemaining: 6
        )
        let candidateConsumed = try guidance.observe(candidateSample)
        #expect(candidateConsumed)
        let candidateResult = try arrival.observeAccepted(
            candidateSample,
            resultingGuidanceState: guidance.state
        )
        #expect(candidateResult == .candidate)

        let backwardSample = try observation(
            token: token,
            uptime: 1_100,
            stepIndex: 0,
            stepRemaining: 10,
            routeRemaining: 20
        )
        let backwardConsumed = try guidance.observe(backwardSample)
        #expect(backwardConsumed)
        #expect(
            guidance.state == .unavailable(
                token: token,
                route: selectedRoute,
                reason: .ambiguousProgress
            )
        )

        let arrivalResult = try arrival.observeAccepted(
            backwardSample,
            resultingGuidanceState: guidance.state
        )
        #expect(arrivalResult == .awaitingEvidence)
        #expect(arrival.state == .awaitingEvidence(token: token))
    }
}
