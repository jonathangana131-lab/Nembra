import Testing
@testable import NembraCore

@Suite("Navigation guidance progress")
struct NavigationGuidanceProgressTests {
    private func coordinate(_ latitude: Double, _ longitude: Double) throws -> NavigationRouteCoordinate {
        try NavigationRouteCoordinate(latitude: latitude, longitude: longitude)
    }

    private func route() throws -> NavigationRouteSnapshot {
        let a = try coordinate(45.6380, -122.6615)
        let b = try coordinate(45.6385, -122.6600)
        let c = try coordinate(45.6390, -122.6585)
        let first = try NavigationRouteStepSnapshot(
            geometry: [a, b],
            instructions: "Continue on Main Street",
            notice: nil,
            distanceMeters: 120,
            transportMode: .cycling
        )
        let second = try NavigationRouteStepSnapshot(
            geometry: [b, c],
            instructions: "Turn right onto River Road",
            notice: "Use caution",
            distanceMeters: 80,
            transportMode: .cycling
        )
        return try NavigationRouteSnapshot(
            provenance: .appleMapKitCycling(),
            name: "Cycling route",
            geometry: [a, b, c],
            steps: [first, second],
            distanceMeters: 200,
            expectedTravelTimeSeconds: 90,
            hasHighways: false,
            hasTolls: false,
            advisoryNotices: []
        )
    }

    private func observation(
        token: NavigationGuidanceSelectionToken,
        uptime: UInt64 = 10,
        stepIndex: Int = 0,
        stepRemaining: Double = 80,
        routeRemaining: Double = 160,
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

    @Test("route selection starts unavailable until accepted progress evidence arrives")
    func selectionAwaitsEvidence() throws {
        var tracker = NavigationGuidanceProgressTracker()
        let selectedRoute = try route()
        let token = try tracker.select(route: selectedRoute)

        #expect(tracker.state == .unavailable(token: token, route: selectedRoute, reason: .awaitingEvidence))
    }

    @Test("confident progress preserves provider current and next step strings")
    func confidentProgressPublishesProviderSteps() throws {
        var tracker = NavigationGuidanceProgressTracker()
        let selectedRoute = try route()
        let token = try tracker.select(route: selectedRoute)
        let accepted = try tracker.observe(observation(token: token))

        #expect(accepted)
        guard case let .active(activeToken, routeSnapshot, progress) = tracker.state else {
            Issue.record("Expected active guidance")
            return
        }
        #expect(activeToken == token)
        #expect(routeSnapshot == selectedRoute)
        #expect(progress.currentStepIndex == 0)
        #expect(progress.currentStep.instructions == "Continue on Main Street")
        #expect(progress.nextStep?.instructions == "Turn right onto River Road")
        #expect(progress.nextStep?.notice == "Use caution")
        #expect(progress.distanceRemainingOnStepMeters == 80)
        #expect(progress.distanceRemainingOnRouteMeters == 160)
    }

    @Test("final route step has no invented next maneuver")
    func finalStepHasNoNextStep() throws {
        var tracker = NavigationGuidanceProgressTracker()
        let token = try tracker.select(route: route())
        _ = try tracker.observe(observation(token: token, stepIndex: 1, stepRemaining: 25, routeRemaining: 25))

        guard case let .active(_, _, progress) = tracker.state else {
            Issue.record("Expected active guidance")
            return
        }
        #expect(progress.currentStepIndex == 1)
        #expect(progress.nextStep == nil)
    }

    @Test("ambiguous geometry assignment removes active progress instead of guessing")
    func ambiguousProgressFailsClosed() throws {
        var tracker = NavigationGuidanceProgressTracker()
        let selectedRoute = try route()
        let token = try tracker.select(route: selectedRoute)
        _ = try tracker.observe(observation(token: token, uptime: 10))
        _ = try tracker.observe(observation(token: token, uptime: 20, confident: false))

        #expect(tracker.state == .unavailable(token: token, route: selectedRoute, reason: .ambiguousProgress))
    }

    @Test("known continuity gap invalidates displayed progress immediately")
    func continuityGapInvalidatesProgress() throws {
        var tracker = NavigationGuidanceProgressTracker()
        let selectedRoute = try route()
        let token = try tracker.select(route: selectedRoute)
        _ = try tracker.observe(observation(token: token))

        tracker.markKnownContinuityGap()

        #expect(tracker.state == .unavailable(token: token, route: selectedRoute, reason: .continuityGap))
    }

    @Test("older callback after continuity gap cannot become current")
    func staleAfterGapRejected() throws {
        var tracker = NavigationGuidanceProgressTracker()
        let token = try tracker.select(route: route())
        _ = try tracker.observe(observation(token: token, uptime: 20))
        tracker.markKnownContinuityGap()
        let before = tracker.state

        #expect(throws: NavigationGuidanceProgressError.nonMonotonicObservation) {
            try tracker.observe(observation(token: token, uptime: 19))
        }
        #expect(tracker.state == before)
    }

    @Test("prior route generation cannot publish onto a new selection")
    func supersededRouteObservationIgnored() throws {
        var tracker = NavigationGuidanceProgressTracker()
        let firstRoute = try route()
        let firstToken = try tracker.select(route: firstRoute)
        let secondRoute = try route()
        let secondToken = try tracker.select(route: secondRoute)
        let before = tracker.state

        let accepted = try tracker.observe(observation(token: firstToken, uptime: 999))

        #expect(!accepted)
        #expect(secondToken != firstToken)
        #expect(tracker.state == before)
    }

    @Test("invalid step index fails atomically")
    func invalidStepIndexFailsAtomically() throws {
        var tracker = NavigationGuidanceProgressTracker()
        let token = try tracker.select(route: route())
        let before = tracker.state

        #expect(throws: NavigationGuidanceProgressError.invalidStepIndex) {
            try tracker.observe(observation(token: token, stepIndex: 2))
        }
        #expect(tracker.state == before)
    }

    @Test("remaining step distance cannot exceed provider step distance")
    func stepRemainingBoundedByProviderStep() throws {
        var tracker = NavigationGuidanceProgressTracker()
        let token = try tracker.select(route: route())
        let before = tracker.state

        #expect(throws: NavigationGuidanceProgressError.invalidObservation) {
            try tracker.observe(observation(token: token, stepRemaining: 121))
        }
        #expect(tracker.state == before)
    }

    @Test("remaining route distance cannot exceed provider route distance")
    func routeRemainingBoundedByProviderRoute() throws {
        var tracker = NavigationGuidanceProgressTracker()
        let token = try tracker.select(route: route())
        let before = tracker.state

        #expect(throws: NavigationGuidanceProgressError.invalidObservation) {
            try tracker.observe(observation(token: token, routeRemaining: 201))
        }
        #expect(tracker.state == before)
    }

    @Test("route remaining cannot be less than the current step remaining")
    func routeRemainingCannotContradictCurrentStep() throws {
        var tracker = NavigationGuidanceProgressTracker()
        let token = try tracker.select(route: route())
        let before = tracker.state

        #expect(throws: NavigationGuidanceProgressError.invalidObservation) {
            try tracker.observe(observation(token: token, stepRemaining: 80, routeRemaining: 79))
        }
        #expect(tracker.state == before)
    }

    @Test("zero remaining distance is legitimate at route completion")
    func zeroRemainingDistanceAccepted() throws {
        var tracker = NavigationGuidanceProgressTracker()
        let token = try tracker.select(route: route())
        let accepted = try tracker.observe(observation(token: token, stepIndex: 1, stepRemaining: 0, routeRemaining: 0))

        #expect(accepted)
        guard case let .active(_, _, progress) = tracker.state else {
            Issue.record("Expected active guidance")
            return
        }
        #expect(progress.distanceRemainingOnStepMeters == 0)
        #expect(progress.distanceRemainingOnRouteMeters == 0)
    }

    @Test("invalid numeric observation is rejected before tracker mutation")
    func invalidObservationRejectedAtConstruction() throws {
        var tracker = NavigationGuidanceProgressTracker()
        let token = try tracker.select(route: route())
        let before = tracker.state

        #expect(throws: NavigationGuidanceProgressError.invalidObservation) {
            try NavigationGuidanceProgressObservation(
                selectionToken: token,
                receivedAtUptimeNanoseconds: 10,
                stepIndex: 0,
                distanceRemainingOnStepMeters: .nan,
                distanceRemainingOnRouteMeters: 10,
                isProgressAssignmentConfident: true
            )
        }
        #expect(tracker.state == before)
    }

    @Test("selection sequence exhaustion fails atomically")
    func selectionSequenceExhaustionIsAtomic() throws {
        var tracker = NavigationGuidanceProgressTracker(initialSelectionSequence: .max)
        let before = tracker.state

        #expect(throws: NavigationGuidanceProgressError.selectionSequenceExhausted) {
            try tracker.select(route: route())
        }
        #expect(tracker.state == before)
    }
}
