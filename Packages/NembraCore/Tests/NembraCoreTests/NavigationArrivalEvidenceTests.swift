import Testing

@testable import NembraCore

@Suite("Navigation arrival evidence")
struct NavigationArrivalEvidenceTests {
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
        stepMeters: Double = 5,
        routeMeters: Double = 8,
        count: Int = 3,
        duration: UInt64 = 2_000
    ) throws -> NavigationArrivalEvidencePolicy {
        try NavigationArrivalEvidencePolicy(
            maximumFinalStepDistanceRemainingMeters: stepMeters,
            maximumRouteDistanceRemainingMeters: routeMeters,
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

    private func accepted(
        _ observation: NavigationGuidanceProgressObservation,
        by tracker: inout NavigationGuidanceProgressTracker
    ) throws -> NavigationGuidanceProgressState {
        let accepted = try tracker.observe(observation)
        #expect(accepted)
        return tracker.state
    }

    @Test("policy cannot permit a single sample or instantaneous burst")
    func policyRequiresSustainedEvidence() {
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
        #expect(throws: NavigationArrivalEvidenceError.invalidPolicy) {
            try NavigationArrivalEvidencePolicy(
                maximumFinalStepDistanceRemainingMeters: -.infinity,
                maximumRouteDistanceRemainingMeters: 8,
                minimumQualifyingObservationCount: 2,
                minimumSustainedDurationNanoseconds: 1
            )
        }
    }

    @Test("arrival requires explicit selected route identity")
    func observationWithoutSelectionRejected() throws {
        let selectedRoute = try route()
        var guidance = NavigationGuidanceProgressTracker()
        let token = try guidance.select(route: selectedRoute)
        let sample = try observation(token: token, uptime: 100)
        let state = try accepted(sample, by: &guidance)
        var arrival = NavigationArrivalEvidenceTracker(policy: try policy())

        #expect(throws: NavigationArrivalEvidenceError.observationWithoutSelectedRoute) {
            try arrival.observeAccepted(sample, resultingGuidanceState: state)
        }
        #expect(arrival.state == .idle)
    }

    @Test("sustained final-step evidence is required before arrival")
    func sustainedEvidenceConfirmsArrival() throws {
        let selectedRoute = try route()
        var guidance = NavigationGuidanceProgressTracker()
        let token = try guidance.select(route: selectedRoute)
        var arrival = NavigationArrivalEvidenceTracker(policy: try policy())
        try arrival.select(token: token, route: selectedRoute)

        let first = try observation(token: token, uptime: 100)
        let firstState = try accepted(first, by: &guidance)
        let firstResult = try arrival.observeAccepted(first, resultingGuidanceState: firstState)
        #expect(firstResult == .candidate)

        let second = try observation(token: token, uptime: 1_100)
        let secondState = try accepted(second, by: &guidance)
        let secondResult = try arrival.observeAccepted(second, resultingGuidanceState: secondState)
        #expect(secondResult == .candidate)

        let third = try observation(token: token, uptime: 2_100)
        let thirdState = try accepted(third, by: &guidance)
        let thirdResult = try arrival.observeAccepted(third, resultingGuidanceState: thirdState)
        #expect(thirdResult == .arrived)

        guard case let .arrived(evidence) = arrival.state else {
            Issue.record("Expected confirmed arrival evidence")
            return
        }
        #expect(evidence.selectionToken == token)
        #expect(evidence.firstQualifyingObservationUptimeNanoseconds == 100)
        #expect(evidence.confirmedAtUptimeNanoseconds == 2_100)
        #expect(evidence.qualifyingObservationCount == 3)
    }

    @Test("observation count alone cannot bypass sustained duration")
    func durationThresholdIsIndependent() throws {
        let selectedRoute = try route()
        var guidance = NavigationGuidanceProgressTracker()
        let token = try guidance.select(route: selectedRoute)
        var arrival = NavigationArrivalEvidenceTracker(
            policy: try policy(count: 2, duration: 5_000)
        )
        try arrival.select(token: token, route: selectedRoute)

        for uptime in [UInt64(100), 1_000, 2_000, 3_000] {
            let sample = try observation(token: token, uptime: uptime)
            let state = try accepted(sample, by: &guidance)
            let result = try arrival.observeAccepted(sample, resultingGuidanceState: state)
            #expect(result == .candidate)
        }
    }

    @Test("near-zero progress on an earlier route step is not arrival evidence")
    func finalStepIsRequired() throws {
        let selectedRoute = try route()
        var guidance = NavigationGuidanceProgressTracker()
        let token = try guidance.select(route: selectedRoute)
        var arrival = NavigationArrivalEvidenceTracker(policy: try policy())
        try arrival.select(token: token, route: selectedRoute)

        let sample = try observation(
            token: token,
            uptime: 100,
            stepIndex: 0,
            stepRemaining: 1,
            routeRemaining: 2
        )
        let state = try accepted(sample, by: &guidance)
        let result = try arrival.observeAccepted(sample, resultingGuidanceState: state)

        #expect(result == .awaitingEvidence)
        #expect(arrival.state == .awaitingEvidence(token: token))
    }

    @Test("leaving the arrival threshold resets the candidate window")
    func nonQualifyingSampleResetsCandidate() throws {
        let selectedRoute = try route()
        var guidance = NavigationGuidanceProgressTracker()
        let token = try guidance.select(route: selectedRoute)
        var arrival = NavigationArrivalEvidenceTracker(policy: try policy())
        try arrival.select(token: token, route: selectedRoute)

        let first = try observation(token: token, uptime: 100)
        let firstState = try accepted(first, by: &guidance)
        _ = try arrival.observeAccepted(first, resultingGuidanceState: firstState)

        let outside = try observation(
            token: token,
            uptime: 1_100,
            stepRemaining: 6,
            routeRemaining: 7
        )
        let outsideState = try accepted(outside, by: &guidance)
        let outsideResult = try arrival.observeAccepted(outside, resultingGuidanceState: outsideState)
        #expect(outsideResult == .awaitingEvidence)

        let restarted = try observation(token: token, uptime: 2_100)
        let restartedState = try accepted(restarted, by: &guidance)
        let restartedResult = try arrival.observeAccepted(
            restarted,
            resultingGuidanceState: restartedState
        )
        #expect(restartedResult == .candidate)
        guard case let .candidate(candidate) = arrival.state else {
            Issue.record("Expected restarted arrival candidate")
            return
        }
        #expect(candidate.firstQualifyingObservationUptimeNanoseconds == 2_100)
        #expect(candidate.qualifyingObservationCount == 1)
    }

    @Test("ambiguous guidance fails closed and resets candidate evidence")
    func ambiguousGuidanceResetsCandidate() throws {
        let selectedRoute = try route()
        var guidance = NavigationGuidanceProgressTracker()
        let token = try guidance.select(route: selectedRoute)
        var arrival = NavigationArrivalEvidenceTracker(policy: try policy())
        try arrival.select(token: token, route: selectedRoute)

        let first = try observation(token: token, uptime: 100)
        let firstState = try accepted(first, by: &guidance)
        _ = try arrival.observeAccepted(first, resultingGuidanceState: firstState)

        let ambiguous = try observation(
            token: token,
            uptime: 1_100,
            confident: false
        )
        let ambiguousState = try accepted(ambiguous, by: &guidance)
        let result = try arrival.observeAccepted(
            ambiguous,
            resultingGuidanceState: ambiguousState
        )

        #expect(result == .awaitingEvidence)
        #expect(arrival.state == .awaitingEvidence(token: token))
    }

    @Test("known continuity gap discards an in-flight candidate")
    func continuityGapResetsCandidate() throws {
        let selectedRoute = try route()
        var guidance = NavigationGuidanceProgressTracker()
        let token = try guidance.select(route: selectedRoute)
        var arrival = NavigationArrivalEvidenceTracker(policy: try policy())
        try arrival.select(token: token, route: selectedRoute)

        let first = try observation(token: token, uptime: 100)
        let firstState = try accepted(first, by: &guidance)
        _ = try arrival.observeAccepted(first, resultingGuidanceState: firstState)
        arrival.markKnownContinuityGap()

        #expect(arrival.state == .awaitingEvidence(token: token))

        let next = try observation(token: token, uptime: 3_000)
        let nextState = try accepted(next, by: &guidance)
        let result = try arrival.observeAccepted(next, resultingGuidanceState: nextState)
        #expect(result == .candidate)
        guard case let .candidate(candidate) = arrival.state else {
            Issue.record("Expected new candidate after continuity gap")
            return
        }
        #expect(candidate.firstQualifyingObservationUptimeNanoseconds == 3_000)
        #expect(candidate.qualifyingObservationCount == 1)
    }

    @Test("new selection invalidates old generation before its first new observation")
    func lateOldGenerationIgnoredAfterReselection() throws {
        let firstRoute = try route(name: "First")
        let secondRoute = try route(name: "Second")
        var guidance = NavigationGuidanceProgressTracker()
        let firstToken = try guidance.select(route: firstRoute)
        var arrival = NavigationArrivalEvidenceTracker(policy: try policy())
        try arrival.select(token: firstToken, route: firstRoute)

        let oldSample = try observation(token: firstToken, uptime: 100)
        let oldState = try accepted(oldSample, by: &guidance)
        _ = try arrival.observeAccepted(oldSample, resultingGuidanceState: oldState)

        let secondToken = try guidance.select(route: secondRoute)
        try arrival.select(token: secondToken, route: secondRoute)
        let before = arrival.state

        let result = try arrival.observeAccepted(
            oldSample,
            resultingGuidanceState: oldState
        )

        #expect(result == .ignoredSupersededSelection)
        #expect(arrival.state == before)
    }

    @Test("same token cannot be rebound to different route facts")
    func tokenRouteIdentityMismatchRejected() throws {
        let firstRoute = try route(name: "First")
        let differentRoute = try route(name: "Different")
        var guidance = NavigationGuidanceProgressTracker()
        let token = try guidance.select(route: firstRoute)
        var arrival = NavigationArrivalEvidenceTracker(policy: try policy())
        try arrival.select(token: token, route: firstRoute)
        let before = arrival.state

        #expect(throws: NavigationArrivalEvidenceError.selectionIdentityMismatch) {
            try arrival.select(token: token, route: differentRoute)
        }
        #expect(arrival.state == before)
    }

    @Test("future generation observation requires explicit arrival selection first")
    func futureGenerationObservationRejected() throws {
        let firstRoute = try route(name: "First")
        let secondRoute = try route(name: "Second")
        var guidance = NavigationGuidanceProgressTracker()
        let firstToken = try guidance.select(route: firstRoute)
        var arrival = NavigationArrivalEvidenceTracker(policy: try policy())
        try arrival.select(token: firstToken, route: firstRoute)

        let secondToken = try guidance.select(route: secondRoute)
        let future = try observation(token: secondToken, uptime: 200)
        let futureState = try accepted(future, by: &guidance)
        let before = arrival.state

        #expect(throws: NavigationArrivalEvidenceError.observationForFutureSelection) {
            try arrival.observeAccepted(future, resultingGuidanceState: futureState)
        }
        #expect(arrival.state == before)
    }

    @Test("accepted observation must match the exact resulting guidance state")
    func mismatchedGuidanceStateRejectedTransactionally() throws {
        let selectedRoute = try route()
        var guidance = NavigationGuidanceProgressTracker()
        let token = try guidance.select(route: selectedRoute)
        var arrival = NavigationArrivalEvidenceTracker(policy: try policy())
        try arrival.select(token: token, route: selectedRoute)

        let first = try observation(token: token, uptime: 100)
        let firstState = try accepted(first, by: &guidance)
        _ = try arrival.observeAccepted(first, resultingGuidanceState: firstState)
        let before = arrival.state

        let mismatched = try observation(
            token: token,
            uptime: 200,
            stepRemaining: 3,
            routeRemaining: 5
        )
        #expect(throws: NavigationArrivalEvidenceError.observationStateMismatch) {
            try arrival.observeAccepted(mismatched, resultingGuidanceState: firstState)
        }
        #expect(arrival.state == before)
    }

    @Test("replayed accepted observation cannot count twice")
    func replayedObservationRejected() throws {
        let selectedRoute = try route()
        var guidance = NavigationGuidanceProgressTracker()
        let token = try guidance.select(route: selectedRoute)
        var arrival = NavigationArrivalEvidenceTracker(policy: try policy())
        try arrival.select(token: token, route: selectedRoute)

        let sample = try observation(token: token, uptime: 100)
        let state = try accepted(sample, by: &guidance)
        _ = try arrival.observeAccepted(sample, resultingGuidanceState: state)
        let before = arrival.state

        #expect(throws: NavigationArrivalEvidenceError.nonMonotonicObservation) {
            try arrival.observeAccepted(sample, resultingGuidanceState: state)
        }
        #expect(arrival.state == before)
    }

    @Test("confirmed arrival stays latched until route selection changes")
    func arrivalLatchesForSelection() throws {
        let selectedRoute = try route()
        var guidance = NavigationGuidanceProgressTracker()
        let token = try guidance.select(route: selectedRoute)
        var arrival = NavigationArrivalEvidenceTracker(
            policy: try policy(count: 2, duration: 1_000)
        )
        try arrival.select(token: token, route: selectedRoute)

        for uptime in [UInt64(100), 1_100] {
            let sample = try observation(token: token, uptime: uptime)
            let state = try accepted(sample, by: &guidance)
            _ = try arrival.observeAccepted(sample, resultingGuidanceState: state)
        }
        let arrivedState = arrival.state

        let movedAway = try observation(
            token: token,
            uptime: 2_100,
            stepRemaining: 20,
            routeRemaining: 20
        )
        let movedAwayState = try accepted(movedAway, by: &guidance)
        let result = try arrival.observeAccepted(
            movedAway,
            resultingGuidanceState: movedAwayState
        )

        #expect(result == .alreadyArrived)
        #expect(arrival.state == arrivedState)
        arrival.markKnownContinuityGap()
        #expect(arrival.state == arrivedState)
    }

    @Test("idempotent selection does not erase a candidate")
    func repeatedSelectionPreservesEvidence() throws {
        let selectedRoute = try route()
        var guidance = NavigationGuidanceProgressTracker()
        let token = try guidance.select(route: selectedRoute)
        var arrival = NavigationArrivalEvidenceTracker(policy: try policy())
        try arrival.select(token: token, route: selectedRoute)

        let sample = try observation(token: token, uptime: 100)
        let state = try accepted(sample, by: &guidance)
        _ = try arrival.observeAccepted(sample, resultingGuidanceState: state)
        let before = arrival.state

        let selected = try arrival.select(token: token, route: selectedRoute)
        #expect(selected)
        #expect(arrival.state == before)
    }

    @Test("clear selection removes all arrival authority")
    func clearSelectionResetsEvidence() throws {
        let selectedRoute = try route()
        var guidance = NavigationGuidanceProgressTracker()
        let token = try guidance.select(route: selectedRoute)
        var arrival = NavigationArrivalEvidenceTracker(policy: try policy())
        try arrival.select(token: token, route: selectedRoute)

        let sample = try observation(token: token, uptime: 100)
        let state = try accepted(sample, by: &guidance)
        _ = try arrival.observeAccepted(sample, resultingGuidanceState: state)
        arrival.clearSelection()

        #expect(arrival.state == .idle)
        #expect(throws: NavigationArrivalEvidenceError.observationWithoutSelectedRoute) {
            try arrival.observeAccepted(sample, resultingGuidanceState: state)
        }
    }
}
