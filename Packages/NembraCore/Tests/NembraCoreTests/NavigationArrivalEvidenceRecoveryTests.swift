import Testing

@testable import NembraCore

@Suite("Navigation arrival evidence recovery")
struct NavigationArrivalEvidenceRecoveryTests {
    private func route(name: String = "Primary") throws -> NavigationRouteSnapshot {
        let a = try NavigationRouteCoordinate(latitude: 45.0, longitude: -122.0)
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

    private func policy(count: Int = 3, duration: UInt64 = 2_000) throws -> NavigationArrivalEvidencePolicy {
        try NavigationArrivalEvidencePolicy(
            maximumFinalStepDistanceRemainingMeters: 5,
            maximumRouteDistanceRemainingMeters: 8,
            minimumQualifyingObservationCount: count,
            minimumSustainedDurationNanoseconds: duration
        )
    }

    private func observation(
        token: NavigationGuidanceSelectionToken,
        uptime: UInt64,
        stepIndex: Int = 1,
        stepRemaining: Double = 4,
        routeRemaining: Double = 6,
        confident: Bool = true
    ) throws -> NavigationGuidanceProgressObservation {
        try NavigationGuidanceProgressObservation(
            selectionToken: token,
            receivedAtUptimeNanoseconds: uptime,
            stepIndex: stepIndex,
            distanceRemainingOnStepMeters: stepRemaining,
            distanceRemainingOnRouteMeters: routeRemaining,
            isProgressAssignmentConfident: confident
        )
    }

    private func accept(
        _ observation: NavigationGuidanceProgressObservation,
        guidance: inout NavigationGuidanceProgressTracker,
        arrival: inout NavigationArrivalEvidenceTracker
    ) throws -> NavigationArrivalObservationResult {
        #expect(try guidance.observe(observation))
        return try arrival.observeAccepted(observation, resultingGuidanceState: guidance.state)
    }

    @Test("policy requires repeated sustained evidence")
    func policyRejectsSingleOrInstantEvidence() {
        #expect(throws: NavigationArrivalEvidenceError.invalidPolicy) {
            try NavigationArrivalEvidencePolicy(
                maximumFinalStepDistanceRemainingMeters: 5,
                maximumRouteDistanceRemainingMeters: 8,
                minimumQualifyingObservationCount: 1,
                minimumSustainedDurationNanoseconds: 1
            )
        }
        #expect(throws: NavigationArrivalEvidenceError.invalidPolicy) {
            try NavigationArrivalEvidencePolicy(
                maximumFinalStepDistanceRemainingMeters: 5,
                maximumRouteDistanceRemainingMeters: 8,
                minimumQualifyingObservationCount: 2,
                minimumSustainedDurationNanoseconds: 0
            )
        }
    }

    @Test("arrival needs repeated final-step evidence over sustained time")
    func sustainedFinalStepEvidenceArrives() throws {
        let selectedRoute = try route()
        var guidance = NavigationGuidanceProgressTracker()
        let token = try guidance.select(route: selectedRoute)
        var arrival = NavigationArrivalEvidenceTracker(policy: try policy())
        try arrival.select(token: token, route: selectedRoute)

        #expect(try accept(try observation(token: token, uptime: 100), guidance: &guidance, arrival: &arrival) == .candidate)
        #expect(try accept(try observation(token: token, uptime: 1_100), guidance: &guidance, arrival: &arrival) == .candidate)
        #expect(try accept(try observation(token: token, uptime: 2_100), guidance: &guidance, arrival: &arrival) == .arrived)

        guard case let .arrived(evidence) = arrival.state else {
            Issue.record("Expected confirmed arrival")
            return
        }
        #expect(evidence.selectionToken == token)
        #expect(evidence.firstQualifyingObservationUptimeNanoseconds == 100)
        #expect(evidence.confirmedAtUptimeNanoseconds == 2_100)
        #expect(evidence.qualifyingObservationCount == 3)
    }

    @Test("either proximity threshold failing resets candidate evidence")
    func thresholdsFailClosedIndependently() throws {
        let selectedRoute = try route()
        var guidance = NavigationGuidanceProgressTracker()
        let token = try guidance.select(route: selectedRoute)
        var arrival = NavigationArrivalEvidenceTracker(policy: try policy())
        try arrival.select(token: token, route: selectedRoute)

        #expect(try accept(try observation(token: token, uptime: 100), guidance: &guidance, arrival: &arrival) == .candidate)
        #expect(try accept(try observation(token: token, uptime: 1_100, stepRemaining: 6, routeRemaining: 7), guidance: &guidance, arrival: &arrival) == .awaitingEvidence)
        #expect(try accept(try observation(token: token, uptime: 2_100, stepRemaining: 4, routeRemaining: 9), guidance: &guidance, arrival: &arrival) == .awaitingEvidence)
    }

    @Test("ambiguous progress and known continuity gaps reset an unconfirmed candidate")
    func ambiguityAndGapResetCandidate() throws {
        let selectedRoute = try route()
        var guidance = NavigationGuidanceProgressTracker()
        let token = try guidance.select(route: selectedRoute)
        var arrival = NavigationArrivalEvidenceTracker(policy: try policy())
        try arrival.select(token: token, route: selectedRoute)

        #expect(try accept(try observation(token: token, uptime: 100), guidance: &guidance, arrival: &arrival) == .candidate)
        #expect(try accept(try observation(token: token, uptime: 1_100, confident: false), guidance: &guidance, arrival: &arrival) == .awaitingEvidence)
        #expect(try accept(try observation(token: token, uptime: 2_100), guidance: &guidance, arrival: &arrival) == .candidate)
        arrival.markKnownContinuityGap()
        #expect(arrival.state == .awaitingEvidence(token: token))
        #expect(try accept(try observation(token: token, uptime: 4_500), guidance: &guidance, arrival: &arrival) == .candidate)
    }

    @Test("replayed accepted observation cannot count twice")
    func replayIsRejected() throws {
        let selectedRoute = try route()
        var guidance = NavigationGuidanceProgressTracker()
        let token = try guidance.select(route: selectedRoute)
        var arrival = NavigationArrivalEvidenceTracker(policy: try policy())
        try arrival.select(token: token, route: selectedRoute)
        let sample = try observation(token: token, uptime: 100)
        #expect(try guidance.observe(sample))
        let state = guidance.state
        #expect(try arrival.observeAccepted(sample, resultingGuidanceState: state) == .candidate)
        #expect(throws: NavigationArrivalEvidenceError.nonMonotonicObservation) {
            try arrival.observeAccepted(sample, resultingGuidanceState: state)
        }
    }

    @Test("new selection invalidates the old route before the new route has observations")
    func reselectionRejectsOldGeneration() throws {
        let firstRoute = try route(name: "First")
        let secondRoute = try route(name: "Second")
        var guidance = NavigationGuidanceProgressTracker()
        let firstToken = try guidance.select(route: firstRoute)
        var arrival = NavigationArrivalEvidenceTracker(policy: try policy())
        try arrival.select(token: firstToken, route: firstRoute)

        let old = try observation(token: firstToken, uptime: 100)
        #expect(try guidance.observe(old))
        let oldState = guidance.state
        #expect(try arrival.observeAccepted(old, resultingGuidanceState: oldState) == .candidate)

        let secondToken = try guidance.select(route: secondRoute)
        try arrival.select(token: secondToken, route: secondRoute)
        let before = arrival.state
        #expect(try arrival.observeAccepted(old, resultingGuidanceState: oldState) == .ignoredSupersededSelection)
        #expect(arrival.state == before)
    }

    @Test("accepted observation must match the exact resulting guidance state")
    func mismatchedGuidanceStateFailsTransactionally() throws {
        let selectedRoute = try route()
        var guidance = NavigationGuidanceProgressTracker()
        let token = try guidance.select(route: selectedRoute)
        var arrival = NavigationArrivalEvidenceTracker(policy: try policy())
        try arrival.select(token: token, route: selectedRoute)

        let first = try observation(token: token, uptime: 100)
        #expect(try guidance.observe(first))
        let firstState = guidance.state
        #expect(try arrival.observeAccepted(first, resultingGuidanceState: firstState) == .candidate)
        let before = arrival.state

        let next = try observation(token: token, uptime: 200, stepRemaining: 3, routeRemaining: 5)
        #expect(throws: NavigationArrivalEvidenceError.observationStateMismatch) {
            try arrival.observeAccepted(next, resultingGuidanceState: firstState)
        }
        #expect(arrival.state == before)
    }

    @Test("confirmed arrival remains latched for its selection")
    func confirmedArrivalLatches() throws {
        let selectedRoute = try route()
        var guidance = NavigationGuidanceProgressTracker()
        let token = try guidance.select(route: selectedRoute)
        var arrival = NavigationArrivalEvidenceTracker(policy: try policy(count: 2, duration: 1_000))
        try arrival.select(token: token, route: selectedRoute)

        _ = try accept(try observation(token: token, uptime: 100), guidance: &guidance, arrival: &arrival)
        #expect(try accept(try observation(token: token, uptime: 1_100), guidance: &guidance, arrival: &arrival) == .arrived)
        let confirmed = arrival.state
        arrival.markKnownContinuityGap()
        #expect(arrival.state == confirmed)
        #expect(try accept(try observation(token: token, uptime: 2_100, stepRemaining: 20, routeRemaining: 20), guidance: &guidance, arrival: &arrival) == .alreadyArrived)
        #expect(arrival.state == confirmed)
    }
}
