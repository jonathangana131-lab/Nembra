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

    private func policy(
        count: Int = 3,
        duration: UInt64 = 2_000
    ) throws -> NavigationArrivalEvidencePolicy {
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

        #expect(
            try arrival.observe(
                observation(token: token, uptime: 100),
                guidanceTracker: &guidance
            ) == .candidate
        )
        #expect(
            try arrival.observe(
                observation(token: token, uptime: 1_100),
                guidanceTracker: &guidance
            ) == .candidate
        )
        #expect(
            try arrival.observe(
                observation(token: token, uptime: 2_100),
                guidanceTracker: &guidance
            ) == .arrived
        )

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

        #expect(
            try arrival.observe(
                observation(token: token, uptime: 100),
                guidanceTracker: &guidance
            ) == .candidate
        )
        #expect(
            try arrival.observe(
                observation(
                    token: token,
                    uptime: 1_100,
                    stepRemaining: 6,
                    routeRemaining: 7
                ),
                guidanceTracker: &guidance
            ) == .awaitingEvidence
        )
        #expect(
            try arrival.observe(
                observation(
                    token: token,
                    uptime: 2_100,
                    stepRemaining: 4,
                    routeRemaining: 9
                ),
                guidanceTracker: &guidance
            ) == .awaitingEvidence
        )
    }

    @Test("ambiguous progress and known continuity gaps reset an unconfirmed candidate")
    func ambiguityAndGapResetCandidate() throws {
        let selectedRoute = try route()
        var guidance = NavigationGuidanceProgressTracker()
        let token = try guidance.select(route: selectedRoute)
        var arrival = NavigationArrivalEvidenceTracker(policy: try policy())
        try arrival.select(token: token, route: selectedRoute)

        #expect(
            try arrival.observe(
                observation(token: token, uptime: 100),
                guidanceTracker: &guidance
            ) == .candidate
        )
        #expect(
            try arrival.observe(
                observation(token: token, uptime: 1_100, confident: false),
                guidanceTracker: &guidance
            ) == .awaitingEvidence
        )
        #expect(
            try arrival.observe(
                observation(token: token, uptime: 2_100),
                guidanceTracker: &guidance
            ) == .candidate
        )
        arrival.markKnownContinuityGap()
        guidance.markKnownContinuityGap()
        #expect(arrival.state == .awaitingEvidence(token: token))
        #expect(
            try arrival.observe(
                observation(token: token, uptime: 4_500),
                guidanceTracker: &guidance
            ) == .candidate
        )
    }

    @Test("replayed guidance observation cannot enter arrival twice")
    func replayIsRejectedBySealedGuidanceBoundary() throws {
        let selectedRoute = try route()
        var guidance = NavigationGuidanceProgressTracker()
        let token = try guidance.select(route: selectedRoute)
        var arrival = NavigationArrivalEvidenceTracker(policy: try policy())
        try arrival.select(token: token, route: selectedRoute)
        let sample = try observation(token: token, uptime: 100)

        #expect(
            try arrival.observe(sample, guidanceTracker: &guidance) == .candidate
        )
        let arrivalBefore = arrival.state
        let guidanceBefore = guidance.state

        #expect(throws: NavigationGuidanceProgressError.nonMonotonicObservation) {
            try arrival.observe(sample, guidanceTracker: &guidance)
        }
        #expect(arrival.state == arrivalBefore)
        #expect(guidance.state == guidanceBefore)
    }

    @Test("new same-tracker selection invalidates old observations without mutating current state")
    func reselectionRejectsOldGeneration() throws {
        let firstRoute = try route(name: "First")
        let secondRoute = try route(name: "Second")
        var guidance = NavigationGuidanceProgressTracker()
        let firstToken = try guidance.select(route: firstRoute)
        var arrival = NavigationArrivalEvidenceTracker(policy: try policy())
        try arrival.select(token: firstToken, route: firstRoute)

        #expect(
            try arrival.observe(
                observation(token: firstToken, uptime: 100),
                guidanceTracker: &guidance
            ) == .candidate
        )

        let secondToken = try guidance.select(route: secondRoute)
        try arrival.select(token: secondToken, route: secondRoute)
        let arrivalBefore = arrival.state
        let guidanceBefore = guidance.state

        #expect(
            try arrival.observe(
                observation(token: firstToken, uptime: 200),
                guidanceTracker: &guidance
            ) == .ignoredSupersededSelection
        )
        #expect(arrival.state == arrivalBefore)
        #expect(guidance.state == guidanceBefore)
    }

    @Test("future same-tracker observation requires explicit arrival reselection")
    func futureSelectionFailsClosed() throws {
        let firstRoute = try route(name: "First")
        let secondRoute = try route(name: "Second")
        var guidance = NavigationGuidanceProgressTracker()
        let firstToken = try guidance.select(route: firstRoute)
        var arrival = NavigationArrivalEvidenceTracker(policy: try policy())
        try arrival.select(token: firstToken, route: firstRoute)

        let secondToken = try guidance.select(route: secondRoute)
        let arrivalBefore = arrival.state
        let guidanceBefore = guidance.state

        #expect(throws: NavigationArrivalEvidenceError.observationForFutureSelection) {
            try arrival.observe(
                observation(token: secondToken, uptime: 100),
                guidanceTracker: &guidance
            )
        }
        #expect(arrival.state == arrivalBefore)
        #expect(guidance.state == guidanceBefore)
    }

    @Test("cross-tracker selection order is never inferred from sequence")
    func recreatedTrackerRequiresExplicitClearBeforeRebind() throws {
        let selectedRoute = try route()
        var firstGuidance = NavigationGuidanceProgressTracker(initialSelectionSequence: 99)
        var secondGuidance = NavigationGuidanceProgressTracker()
        let firstToken = try firstGuidance.select(route: selectedRoute)
        let secondToken = try secondGuidance.select(route: selectedRoute)
        #expect(firstToken.sequence == 100)
        #expect(secondToken.sequence == 1)
        #expect(!firstToken.sharesTrackerGeneration(with: secondToken))

        var arrival = NavigationArrivalEvidenceTracker(policy: try policy())
        try arrival.select(token: firstToken, route: selectedRoute)

        #expect(throws: NavigationArrivalEvidenceError.selectionTrackerGenerationMismatch) {
            try arrival.select(token: secondToken, route: selectedRoute)
        }

        arrival.clearSelection()
        #expect(try arrival.select(token: secondToken, route: selectedRoute))
        #expect(arrival.state == .awaitingEvidence(token: secondToken))
    }

    @Test("cross-tracker observation fails closed even when its sequence looks older")
    func recreatedTrackerObservationIsNotCalledSuperseded() throws {
        let selectedRoute = try route()
        var firstGuidance = NavigationGuidanceProgressTracker(initialSelectionSequence: 99)
        var secondGuidance = NavigationGuidanceProgressTracker()
        let firstToken = try firstGuidance.select(route: selectedRoute)
        let secondToken = try secondGuidance.select(route: selectedRoute)

        var arrival = NavigationArrivalEvidenceTracker(policy: try policy())
        try arrival.select(token: firstToken, route: selectedRoute)
        let arrivalBefore = arrival.state
        let guidanceBefore = secondGuidance.state

        #expect(throws: NavigationArrivalEvidenceError.observationTrackerGenerationMismatch) {
            try arrival.observe(
                observation(token: secondToken, uptime: 100),
                guidanceTracker: &secondGuidance
            )
        }
        #expect(arrival.state == arrivalBefore)
        #expect(secondGuidance.state == guidanceBefore)
    }

    @Test("divergent copied trackers with equal sequence are ambiguous rather than ordered")
    func divergentCopyEqualSequenceFailsClosed() throws {
        let selectedRoute = try route()
        var guidance = NavigationGuidanceProgressTracker()
        var divergent = guidance
        let currentToken = try guidance.select(route: selectedRoute)
        let divergentToken = try divergent.select(route: selectedRoute)
        #expect(currentToken.sequence == divergentToken.sequence)
        #expect(currentToken.sharesTrackerGeneration(with: divergentToken))
        #expect(currentToken != divergentToken)

        var arrival = NavigationArrivalEvidenceTracker(policy: try policy())
        try arrival.select(token: currentToken, route: selectedRoute)
        let arrivalBefore = arrival.state
        let divergentBefore = divergent.state

        #expect(throws: NavigationArrivalEvidenceError.selectionOrderAmbiguous) {
            try arrival.observe(
                observation(token: divergentToken, uptime: 100),
                guidanceTracker: &divergent
            )
        }
        #expect(arrival.state == arrivalBefore)
        #expect(divergent.state == divergentBefore)
    }

    @Test("guidance rejection and arrival rejection commit neither reducer")
    func compositeAdmissionIsTransactional() throws {
        let selectedRoute = try route()
        var guidance = NavigationGuidanceProgressTracker()
        let token = try guidance.select(route: selectedRoute)
        var arrival = NavigationArrivalEvidenceTracker(policy: try policy())
        try arrival.select(token: token, route: selectedRoute)

        let arrivalBefore = arrival.state
        let guidanceBefore = guidance.state
        let badStep = try observation(
            token: token,
            uptime: 100,
            stepIndex: 99,
            stepRemaining: 4,
            routeRemaining: 6
        )

        #expect(throws: NavigationGuidanceProgressError.invalidStepIndex) {
            try arrival.observe(badStep, guidanceTracker: &guidance)
        }
        #expect(arrival.state == arrivalBefore)
        #expect(guidance.state == guidanceBefore)
    }

    @Test("confirmed arrival remains latched for its selection")
    func confirmedArrivalLatches() throws {
        let selectedRoute = try route()
        var guidance = NavigationGuidanceProgressTracker()
        let token = try guidance.select(route: selectedRoute)
        var arrival = NavigationArrivalEvidenceTracker(
            policy: try policy(count: 2, duration: 1_000)
        )
        try arrival.select(token: token, route: selectedRoute)

        _ = try arrival.observe(
            observation(token: token, uptime: 100),
            guidanceTracker: &guidance
        )
        #expect(
            try arrival.observe(
                observation(token: token, uptime: 1_100),
                guidanceTracker: &guidance
            ) == .arrived
        )

        let confirmed = arrival.state
        arrival.markKnownContinuityGap()
        guidance.markKnownContinuityGap()
        #expect(arrival.state == confirmed)

        #expect(
            try arrival.observe(
                observation(
                    token: token,
                    uptime: 2_100,
                    stepRemaining: 20,
                    routeRemaining: 20
                ),
                guidanceTracker: &guidance
            ) == .alreadyArrived
        )
        #expect(arrival.state == confirmed)
    }
}
