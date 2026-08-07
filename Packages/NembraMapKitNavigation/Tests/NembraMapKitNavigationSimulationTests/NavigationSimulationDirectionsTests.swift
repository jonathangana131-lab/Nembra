import NembraCore
import NembraMapKitNavigation
import NembraMapKitNavigationSimulation
import Testing

@Suite("Navigation simulation directions")
@MainActor
struct NavigationSimulationDirectionsTests {
    private func coordinate(_ latitude: Double, _ longitude: Double) throws -> NavigationRouteCoordinate {
        try NavigationRouteCoordinate(latitude: latitude, longitude: longitude)
    }

    private func request(offset: Double = 0.01) throws -> NavigationRoutePlanRequest {
        .appleMapKitCycling(
            source: try coordinate(45, -122),
            destination: try coordinate(45 + offset, -122.01)
        )
    }

    private func route(name: String) throws -> NavigationRouteSnapshot {
        let a = try coordinate(45, -122)
        let b = try coordinate(45.001, -122)
        let step = try NavigationRouteStepSnapshot(
            geometry: [a, b],
            instructions: name,
            notice: nil,
            distanceMeters: 100,
            transportMode: .cycling
        )
        return try NavigationRouteSnapshot(
            provenance: .appleMapKitCycling(),
            name: name,
            geometry: [a, b],
            steps: [step],
            distanceMeters: 100,
            expectedTravelTimeSeconds: 30,
            hasHighways: false,
            hasTolls: false,
            advisoryNotices: []
        )
    }

    @Test("scripted routes are consumed in order and requests are recorded")
    func responsesAreOrdered() async throws {
        let first = try route(name: "First")
        let second = try route(name: "Second")
        let factory = NavigationSimulationDirectionsOperationFactory(responses: [
            .routes([first]),
            .routes([second]),
        ])
        let coordinator = NavigationDirectionsOperationCoordinator(factory: factory)
        var planner = NavigationRoutePlanningCoordinator()
        let firstRequest = try request(offset: 0.01)
        let firstToken = try planner.begin(firstRequest).token
        planner.reset()
        let secondRequest = try request(offset: 0.02)
        let secondToken = try planner.begin(secondRequest).token

        #expect(await coordinator.calculate(request: firstRequest, token: firstToken) == .routes([first]))
        #expect(await coordinator.calculate(request: secondRequest, token: secondToken) == .routes([second]))
        #expect(factory.receivedRequests == [firstRequest, secondRequest])
    }

    @Test("scripted failure preserves exact product failure")
    func scriptedFailure() async throws {
        let factory = NavigationSimulationDirectionsOperationFactory(responses: [
            .failure(.loadingThrottled)
        ])
        let service = NavigationRoutePlanningService(factory: factory)
        let state = try await service.request(request())

        guard case let .failed(_, _, reason) = state else {
            Issue.record("Expected failed state")
            return
        }
        #expect(reason == .loadingThrottled)
    }

    @Test("missing scripted response fails unavailable instead of inventing a route")
    func missingResponseFailsClosed() async throws {
        let factory = NavigationSimulationDirectionsOperationFactory()
        let service = NavigationRoutePlanningService(factory: factory)
        let state = try await service.request(request())

        guard case let .failed(_, _, reason) = state else {
            Issue.record("Expected failed state")
            return
        }
        #expect(reason == .directionsUnavailable)
    }

    @Test("responses may be enqueued after factory construction")
    func enqueueResponse() async throws {
        let expected = try route(name: "Queued")
        let factory = NavigationSimulationDirectionsOperationFactory()
        factory.enqueue(.routes([expected]))
        let service = NavigationRoutePlanningService(factory: factory)
        let state = try await service.request(request())

        guard case let .available(_, _, routes) = state else {
            Issue.record("Expected routes")
            return
        }
        #expect(routes == [expected])
    }

    @Test("simulation provider composes through explicit route selection workflow")
    func experienceComposition() async throws {
        let first = try route(name: "First")
        let second = try route(name: "Second")
        let factory = NavigationSimulationDirectionsOperationFactory(responses: [
            .routes([first, second])
        ])
        let experience = NavigationExperienceCoordinator(
            factory: factory,
            geometryPolicy: try NavigationRouteGeometryMatchingPolicy(
                maximumRouteDistanceMeters: 40,
                minimumStepAmbiguitySeparationMeters: 4
            ),
            reroutePolicy: try NavigationReroutePolicy(
                minimumDeviationDistanceMeters: 20,
                requiredConsecutiveAcceptedSamples: 2,
                rerouteCooldownNanoseconds: 100
            )
        )

        let planned = try await experience.plan(request())
        #expect(planned.routeSelection?.selectedIndex == nil)
        let selected = try experience.selectRoute(index: 1)
        #expect(selected.selectedRoute == second)
    }

    @Test("unknown non-simulation errors map to unknown")
    func unknownErrorMapping() {
        struct OtherError: Error {}
        let factory = NavigationSimulationDirectionsOperationFactory()
        #expect(factory.failure(from: OtherError()) == .unknown)
    }
}
