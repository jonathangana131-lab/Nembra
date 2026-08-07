import Testing

@testable import NembraCore

@Suite("Navigation arrival route binding")
struct NavigationArrivalRouteBindingTests {
    private func route(name: String) throws -> NavigationRouteSnapshot {
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
            name: name,
            geometry: [a, b, c],
            steps: [first, final],
            distanceMeters: 100,
            expectedTravelTimeSeconds: 60,
            hasHighways: false,
            hasTolls: false,
            advisoryNotices: []
        )
    }

    private func policy() throws -> NavigationArrivalEvidencePolicy {
        try NavigationArrivalEvidencePolicy(
            maximumFinalStepDistanceRemainingMeters: 5,
            maximumRouteDistanceRemainingMeters: 8,
            minimumQualifyingObservationCount: 2,
            minimumSustainedDurationNanoseconds: 1_000
        )
    }

    @Test("a token bound to the wrong route cannot advance either reducer")
    func wrongInitialRouteFailsTransactionally() throws {
        let guidanceRoute = try route(name: "Guidance")
        let wrongArrivalRoute = try route(name: "Wrong arrival route")
        var guidance = NavigationGuidanceProgressTracker()
        let token = try guidance.select(route: guidanceRoute)
        var arrival = NavigationArrivalEvidenceTracker(policy: try policy())
        try arrival.select(token: token, route: wrongArrivalRoute)

        let observation = try NavigationGuidanceProgressObservation(
            selectionToken: token,
            receivedAtUptimeNanoseconds: 100,
            stepIndex: 1,
            distanceRemainingOnStepMeters: 4,
            distanceRemainingOnRouteMeters: 6,
            isProgressAssignmentConfident: true
        )
        let guidanceBefore = guidance.state
        let arrivalBefore = arrival.state

        #expect(throws: NavigationArrivalEvidenceError.observationStateMismatch) {
            try arrival.observe(observation, guidanceTracker: &guidance)
        }
        #expect(guidance.state == guidanceBefore)
        #expect(arrival.state == arrivalBefore)
    }

    @Test("an existing token cannot be rebound to a different route")
    func sameTokenDifferentRouteFailsTransactionally() throws {
        let selectedRoute = try route(name: "Selected")
        let conflictingRoute = try route(name: "Conflicting")
        var guidance = NavigationGuidanceProgressTracker()
        let token = try guidance.select(route: selectedRoute)
        var arrival = NavigationArrivalEvidenceTracker(policy: try policy())
        try arrival.select(token: token, route: selectedRoute)
        let before = arrival.state

        #expect(throws: NavigationArrivalEvidenceError.selectionIdentityMismatch) {
            try arrival.select(token: token, route: conflictingRoute)
        }
        #expect(arrival.state == before)
    }
}
