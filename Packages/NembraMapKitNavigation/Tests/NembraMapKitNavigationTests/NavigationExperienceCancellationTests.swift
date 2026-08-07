import NembraCore
import Testing
@testable import NembraMapKitNavigation

@Suite("Navigation experience cancellation")
@MainActor
struct NavigationExperienceCancellationTests {
    @Test("cancel after completed planning preserves available alternatives")
    func completedPlanningCancelIsNoop() async throws {
        let route = try makeRoute()
        let experience = try NavigationExperienceCoordinator(
            factory: CompletedPlanningFactory(routes: [route]),
            geometryPolicy: NavigationRouteGeometryMatchingPolicy(
                maximumRouteDistanceMeters: 40,
                minimumStepAmbiguitySeparationMeters: 4
            ),
            reroutePolicy: NavigationReroutePolicy(
                minimumDeviationDistanceMeters: 20,
                requiredConsecutiveAcceptedSamples: 2,
                rerouteCooldownNanoseconds: 100
            )
        )

        let completed = try await experience.plan(
            .appleMapKitCycling(
                source: NavigationRouteCoordinate(latitude: 45, longitude: -122),
                destination: NavigationRouteCoordinate(latitude: 45.01, longitude: -122.01)
            )
        )
        let alternativesBeforeCancel = try #require(completed.routeSelection)

        #expect(try !experience.cancelPlanning())
        #expect(experience.snapshot.routeSelection == alternativesBeforeCancel)
        #expect(experience.snapshot.planningState == completed.planningState)
        #expect(experience.snapshot.selectedRoute == nil)
        #expect(experience.snapshot.guidanceState == .idle)
    }

    private func makeRoute() throws -> NavigationRouteSnapshot {
        let start = try NavigationRouteCoordinate(latitude: 45, longitude: -122)
        let end = try NavigationRouteCoordinate(latitude: 45.01, longitude: -122.01)
        let step = try NavigationRouteStepSnapshot(
            geometry: [start, end],
            instructions: "Continue",
            notice: nil,
            distanceMeters: 100,
            transportMode: .cycling
        )
        return try NavigationRouteSnapshot(
            provenance: .appleMapKitCycling(),
            name: "Completed route",
            geometry: [start, end],
            steps: [step],
            distanceMeters: 100,
            expectedTravelTimeSeconds: 30,
            hasHighways: false,
            hasTolls: false,
            advisoryNotices: []
        )
    }
}

@MainActor
private final class CompletedPlanningFactory: NavigationDirectionsOperationFactory {
    private let routes: [NavigationRouteSnapshot]

    init(routes: [NavigationRouteSnapshot]) {
        self.routes = routes
    }

    func makeOperation(
        for request: NavigationRoutePlanRequest
    ) throws -> any NavigationDirectionsOperation {
        CompletedPlanningOperation(routes: routes)
    }

    func failure(from error: Error) -> NavigationRoutePlanFailure {
        .unknown
    }
}

@MainActor
private final class CompletedPlanningOperation: NavigationDirectionsOperation {
    private let routes: [NavigationRouteSnapshot]

    init(routes: [NavigationRouteSnapshot]) {
        self.routes = routes
    }

    func calculate() async throws -> [NavigationRouteSnapshot] {
        routes
    }

    func cancel() {}
}
