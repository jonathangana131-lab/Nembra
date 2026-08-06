import Testing
@testable import NembraCore

@Suite("Navigation route planning coordinator")
struct NavigationRoutePlanningTests {
    private func coordinate(_ latitude: Double, _ longitude: Double) throws -> NavigationRouteCoordinate {
        try NavigationRouteCoordinate(latitude: latitude, longitude: longitude)
    }

    private func request(
        alternateRoutes: Bool = true,
        highwayPreference: NavigationRoutePreference = .any,
        tollPreference: NavigationRoutePreference = .any
    ) throws -> NavigationRoutePlanRequest {
        NavigationRoutePlanRequest(
            source: try coordinate(45.6380, -122.6615),
            destination: try coordinate(45.6500, -122.6750),
            transportMode: .cycling,
            requestsAlternateRoutes: alternateRoutes,
            highwayPreference: highwayPreference,
            tollPreference: tollPreference
        )
    }

    private func route(name: String = "Route A") throws -> NavigationRouteSnapshot {
        let start = try coordinate(45.6380, -122.6615)
        let end = try coordinate(45.6500, -122.6750)
        let step = try NavigationRouteStepSnapshot(
            geometry: [start, end],
            instructions: "Continue",
            notice: nil,
            distanceMeters: 1_500,
            transportMode: .cycling
        )
        return try NavigationRouteSnapshot(
            provenance: .appleMapKitCycling(),
            name: name,
            geometry: [start, end],
            steps: [step],
            distanceMeters: 1_500,
            expectedTravelTimeSeconds: 480,
            hasHighways: false,
            hasTolls: false,
            advisoryNotices: []
        )
    }

    @Test("MapKit cycling request defaults preserve routing intent")
    func cyclingRequestDefaults() throws {
        let source = try coordinate(45.6380, -122.6615)
        let destination = try coordinate(45.6500, -122.6750)
        let request = NavigationRoutePlanRequest.appleMapKitCycling(
            source: source,
            destination: destination
        )

        #expect(request.source == source)
        #expect(request.destination == destination)
        #expect(request.transportMode == .cycling)
        #expect(request.requestsAlternateRoutes)
        #expect(request.highwayPreference == .any)
        #expect(request.tollPreference == .any)
    }

    @Test("request preferences remain explicit provider intent")
    func requestPreferencesArePreserved() throws {
        let request = try request(
            alternateRoutes: false,
            highwayPreference: .avoid,
            tollPreference: .avoid
        )

        #expect(request.requestsAlternateRoutes == false)
        #expect(request.highwayPreference == .avoid)
        #expect(request.tollPreference == .avoid)
    }

    @Test("begin creates a current request token")
    func beginCreatesCurrentToken() throws {
        var coordinator = NavigationRoutePlanningCoordinator()
        let request = try request()
        let start = try coordinator.begin(request)

        #expect(start.token.sequence == 1)
        #expect(start.supersededToken == nil)
        #expect(coordinator.state == .requesting(token: start.token, request: request))
    }

    @Test("starting a new request explicitly supersedes the old token")
    func beginSupersedesCurrentRequest() throws {
        var coordinator = NavigationRoutePlanningCoordinator()
        let firstRequest = try request()
        let first = try coordinator.begin(firstRequest)
        let secondRequest = NavigationRoutePlanRequest.appleMapKitCycling(
            source: firstRequest.destination,
            destination: firstRequest.source,
            requestsAlternateRoutes: false
        )
        let second = try coordinator.begin(secondRequest)

        #expect(second.token.sequence == 2)
        #expect(second.supersededToken == first.token)
        #expect(coordinator.state == .requesting(token: second.token, request: secondRequest))
    }

    @Test("late success from a superseded request cannot publish")
    func staleSuccessIsRejected() throws {
        var coordinator = NavigationRoutePlanningCoordinator()
        let first = try coordinator.begin(request())
        let secondRequest = try request(alternateRoutes: false)
        let second = try coordinator.begin(secondRequest)

        let staleAccepted = coordinator.complete(
            token: first.token,
            routes: [try route(name: "Stale")]
        )

        #expect(staleAccepted == false)
        #expect(coordinator.state == .requesting(token: second.token, request: secondRequest))
    }

    @Test("late failure from a superseded request cannot replace current state")
    func staleFailureIsRejected() throws {
        var coordinator = NavigationRoutePlanningCoordinator()
        let first = try coordinator.begin(request())
        let secondRequest = try request(alternateRoutes: false)
        let second = try coordinator.begin(secondRequest)

        let staleAccepted = coordinator.fail(token: first.token, reason: .serverFailure)

        #expect(staleAccepted == false)
        #expect(coordinator.state == .requesting(token: second.token, request: secondRequest))
    }

    @Test("current nonempty routes become available")
    func currentRoutesPublish() throws {
        var coordinator = NavigationRoutePlanningCoordinator()
        let request = try request()
        let start = try coordinator.begin(request)
        let routes = [try route(name: "Primary"), try route(name: "Alternate")]

        let accepted = coordinator.complete(token: start.token, routes: routes)

        #expect(accepted)
        #expect(coordinator.state == .available(token: start.token, request: request, routes: routes))
    }

    @Test("empty provider response fails closed")
    func emptyResponseFailsClosed() throws {
        var coordinator = NavigationRoutePlanningCoordinator()
        let request = try request()
        let start = try coordinator.begin(request)

        let accepted = coordinator.complete(token: start.token, routes: [])

        #expect(accepted)
        #expect(
            coordinator.state == .failed(
                token: start.token,
                request: request,
                reason: .invalidProviderResponse
            )
        )
    }

    @Test("documented provider failure semantics remain explicit")
    func currentFailurePublishes() throws {
        var coordinator = NavigationRoutePlanningCoordinator()
        let request = try request()
        let start = try coordinator.begin(request)

        let accepted = coordinator.fail(token: start.token, reason: .loadingThrottled)

        #expect(accepted)
        #expect(
            coordinator.state == .failed(
                token: start.token,
                request: request,
                reason: .loadingThrottled
            )
        )
    }

    @Test("cancellation invalidates generation before transport cancellation races")
    func cancellationInvalidatesCurrentRequest() throws {
        var coordinator = NavigationRoutePlanningCoordinator()
        let request = try request()
        let start = try coordinator.begin(request)

        let cancelledToken = coordinator.cancelCurrent()

        #expect(cancelledToken == start.token)
        #expect(
            coordinator.state == .failed(
                token: start.token,
                request: request,
                reason: .cancelled
            )
        )
        let staleAccepted = coordinator.complete(token: start.token, routes: [try route()])
        #expect(staleAccepted == false)
    }

    @Test("cancelling without a current request is a no-op")
    func cancellationWithoutRequestIsNoOp() throws {
        var coordinator = NavigationRoutePlanningCoordinator()

        let beforeRequest = coordinator.cancelCurrent()
        #expect(beforeRequest == nil)

        _ = try coordinator.begin(request())
        _ = coordinator.cancelCurrent()
        let afterCancellation = coordinator.cancelCurrent()
        #expect(afterCancellation == nil)
    }

    @Test("reset clears presentation state without making old callbacks current")
    func resetRejectsOldCallbacks() throws {
        var coordinator = NavigationRoutePlanningCoordinator()
        let start = try coordinator.begin(request())

        coordinator.reset()

        #expect(coordinator.state == .idle)
        let staleAccepted = coordinator.complete(token: start.token, routes: [try route()])
        #expect(staleAccepted == false)
        #expect(coordinator.fail(token: start.token, reason: .unknown) == false)
    }

    @Test("request sequence exhaustion fails atomically")
    func sequenceExhaustionFailsAtomically() throws {
        var coordinator = NavigationRoutePlanningCoordinator(initialSequence: UInt64.max)
        let original = coordinator.state

        #expect(throws: NavigationRoutePlanningError.requestSequenceExhausted) {
            _ = try coordinator.begin(request())
        }
        #expect(coordinator.state == original)
    }
}
