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

        let candidateSample = try NavigationGuidanceProgressObservation(
            selectionToken: token,
            receivedAtUptimeNanoseconds: 100,
            stepIndex: 1,
            distanceRemainingOnStepMeters: 4,
            distanceRemainingOnRouteMeters: 6,
            isProgressAssignmentConfident: true
        )
        #expect(try guidance.observe(candidateSample))
        #expect(
            try arrival.observeAccepted(candidateSample, resultingGuidanceState: guidance.state)
                == .candidate
        )

        let backwardSample = try NavigationGuidanceProgressObservation(
            selectionToken: token,
            receivedAtUptimeNanoseconds: 1_100,
            stepIndex: 0,
            distanceRemainingOnStepMeters: 10,
            distanceRemainingOnRouteMeters: 20,
            isProgressAssignmentConfident: true
        )
        #expect(try guidance.observe(backwardSample))
        #expect(
            guidance.state == .unavailable(
                token: token,
                route: selectedRoute,
                reason: .ambiguousProgress
            )
        )
        #expect(
            try arrival.observeAccepted(backwardSample, resultingGuidanceState: guidance.state)
                == .awaitingEvidence
        )
        #expect(arrival.state == .awaitingEvidence(token: token))
    }
}
