import Testing
@testable import NembraCore

@Suite("Navigation guidance step regression")
struct NavigationGuidanceStepRegressionTests {
    private func coordinate(_ latitude: Double, _ longitude: Double) throws -> NavigationRouteCoordinate {
        try NavigationRouteCoordinate(latitude: latitude, longitude: longitude)
    }

    private func route() throws -> NavigationRouteSnapshot {
        let a = try coordinate(45.6380, -122.6615)
        let b = try coordinate(45.6385, -122.6600)
        let c = try coordinate(45.6390, -122.6585)
        let first = try NavigationRouteStepSnapshot(
            geometry: [a, b],
            instructions: "Continue",
            notice: nil,
            distanceMeters: 120,
            transportMode: .cycling
        )
        let second = try NavigationRouteStepSnapshot(
            geometry: [b, c],
            instructions: "Turn right",
            notice: nil,
            distanceMeters: 80,
            transportMode: .cycling
        )
        return try NavigationRouteSnapshot(
            provenance: .appleMapKitCycling(),
            name: "Route",
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
        uptime: UInt64,
        stepIndex: Int,
        stepRemaining: Double,
        routeRemaining: Double,
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

    @Test("newer confident evidence cannot resurrect an earlier provider step")
    func backwardStepFailsClosed() throws {
        var tracker = NavigationGuidanceProgressTracker()
        let selectedRoute = try route()
        let token = try tracker.select(route: selectedRoute)
        _ = try tracker.observe(
            observation(token: token, uptime: 10, stepIndex: 1, stepRemaining: 40, routeRemaining: 40)
        )

        let consumed = try tracker.observe(
            observation(token: token, uptime: 20, stepIndex: 0, stepRemaining: 60, routeRemaining: 120)
        )

        #expect(consumed)
        #expect(tracker.state == .unavailable(token: token, route: selectedRoute, reason: .ambiguousProgress))
    }

    @Test("fresh non-regressive evidence recovers guidance after a backward match")
    func forwardEvidenceRecoversAfterRegression() throws {
        var tracker = NavigationGuidanceProgressTracker()
        let token = try tracker.select(route: route())
        _ = try tracker.observe(
            observation(token: token, uptime: 10, stepIndex: 1, stepRemaining: 40, routeRemaining: 40)
        )
        _ = try tracker.observe(
            observation(token: token, uptime: 20, stepIndex: 0, stepRemaining: 60, routeRemaining: 120)
        )

        let recovered = try tracker.observe(
            observation(token: token, uptime: 30, stepIndex: 1, stepRemaining: 30, routeRemaining: 30)
        )

        #expect(recovered)
        guard case let .active(_, _, progress) = tracker.state else {
            Issue.record("Expected non-regressive evidence to restore active guidance")
            return
        }
        #expect(progress.currentStepIndex == 1)
        #expect(progress.distanceRemainingOnRouteMeters == 30)
    }

    @Test("ambiguous earlier evidence does not lower the confident step floor")
    func ambiguityCannotLowerStepFloor() throws {
        var tracker = NavigationGuidanceProgressTracker()
        let selectedRoute = try route()
        let token = try tracker.select(route: selectedRoute)
        _ = try tracker.observe(
            observation(token: token, uptime: 10, stepIndex: 1, stepRemaining: 40, routeRemaining: 40)
        )
        _ = try tracker.observe(
            observation(
                token: token,
                uptime: 20,
                stepIndex: 0,
                stepRemaining: 60,
                routeRemaining: 120,
                confident: false
            )
        )

        _ = try tracker.observe(
            observation(token: token, uptime: 30, stepIndex: 0, stepRemaining: 55, routeRemaining: 115)
        )

        #expect(tracker.state == .unavailable(token: token, route: selectedRoute, reason: .ambiguousProgress))
    }

    @Test("same-step remaining distance may increase because no meter tolerance is guessed")
    func sameStepDistanceJitterRemainsAccepted() throws {
        var tracker = NavigationGuidanceProgressTracker()
        let token = try tracker.select(route: route())
        _ = try tracker.observe(
            observation(token: token, uptime: 10, stepIndex: 0, stepRemaining: 60, routeRemaining: 120)
        )

        let accepted = try tracker.observe(
            observation(token: token, uptime: 20, stepIndex: 0, stepRemaining: 65, routeRemaining: 125)
        )

        #expect(accepted)
        guard case let .active(_, _, progress) = tracker.state else {
            Issue.record("Expected same-step geometry jitter to remain representable")
            return
        }
        #expect(progress.currentStepIndex == 0)
        #expect(progress.distanceRemainingOnStepMeters == 65)
        #expect(progress.distanceRemainingOnRouteMeters == 125)
    }

    @Test("new route selection resets the prior route step floor")
    func newSelectionResetsStepFloor() throws {
        var tracker = NavigationGuidanceProgressTracker()
        let firstRoute = try route()
        let firstToken = try tracker.select(route: firstRoute)
        _ = try tracker.observe(
            observation(token: firstToken, uptime: 10, stepIndex: 1, stepRemaining: 40, routeRemaining: 40)
        )

        let secondRoute = try route()
        let secondToken = try tracker.select(route: secondRoute)
        let accepted = try tracker.observe(
            observation(token: secondToken, uptime: 20, stepIndex: 0, stepRemaining: 60, routeRemaining: 120)
        )

        #expect(accepted)
        guard case let .active(activeToken, activeRoute, progress) = tracker.state else {
            Issue.record("Expected fresh route generation to accept its first confident step")
            return
        }
        #expect(activeToken == secondToken)
        #expect(activeRoute == secondRoute)
        #expect(progress.currentStepIndex == 0)
    }
}
