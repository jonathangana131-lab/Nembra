import NembraCore
import Testing
@testable import NembraMapKitNavigation

@Suite("Navigation route selection identity")
@MainActor
struct NavigationRouteSelectionIdentityTests {
    @Test("stale option identity cannot retarget the same index into newer alternatives")
    func staleSelectionFailsClosed() async throws {
        let firstRoute = try route(name: "First generation")
        let secondRoute = try route(name: "Second generation")
        let experience = try coordinator(routeResults: [[firstRoute], [secondRoute]])

        _ = try await experience.plan(request(destinationOffset: 0.01))
        let firstPresentation = NavigationPresentationProjector.snapshot(from: experience.snapshot)
        let staleSelectionID = try #require(firstPresentation.routeOptions.first?.selectionID)

        _ = try await experience.plan(request(destinationOffset: 0.02))
        let secondPresentation = NavigationPresentationProjector.snapshot(from: experience.snapshot)
        let freshSelectionID = try #require(secondPresentation.routeOptions.first?.selectionID)

        #expect(staleSelectionID.index == freshSelectionID.index)
        #expect(staleSelectionID.requestToken != freshSelectionID.requestToken)
        #expect(throws: NavigationExperienceError.staleRouteOptions) {
            try experience.selectRoute(staleSelectionID)
        }
        #expect(experience.snapshot.selectedRoute == nil)
        #expect(experience.snapshot.routeSelection?.selectedIndex == nil)

        let selected = try experience.selectRoute(freshSelectionID)
        #expect(selected.selectedRoute == secondRoute)
        #expect(selected.routeSelection?.selectedIndex == 0)
    }

    private func coordinate(_ latitude: Double, _ longitude: Double) throws -> NavigationRouteCoordinate {
        try NavigationRouteCoordinate(latitude: latitude, longitude: longitude)
    }

    private func request(destinationOffset: Double) throws -> NavigationRoutePlanRequest {
        .appleMapKitCycling(
            source: try coordinate(45, -122),
            destination: try coordinate(45 + destinationOffset, -122.01)
        )
    }

    private func route(name: String) throws -> NavigationRouteSnapshot {
        let start = try coordinate(45, -122)
        let end = try coordinate(45.01, -122.01)
        let step = try NavigationRouteStepSnapshot(
            geometry: [start, end],
            instructions: "Continue",
            notice: nil,
            distanceMeters: 100,
            transportMode: .cycling
        )
        return try NavigationRouteSnapshot(
            provenance: .appleMapKitCycling(),
            name: name,
            geometry: [start, end],
            steps: [step],
            distanceMeters: 100,
            expectedTravelTimeSeconds: 30,
            hasHighways: false,
            hasTolls: false,
            advisoryNotices: []
        )
    }

    private func coordinator(
        routeResults: [[NavigationRouteSnapshot]]
    ) throws -> NavigationExperienceCoordinator {
        NavigationExperienceCoordinator(
            factory: SelectionIdentityFactory(routeResults: routeResults),
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
    }
}

@MainActor
private final class SelectionIdentityFactory: NavigationDirectionsOperationFactory {
    private var routeResults: [[NavigationRouteSnapshot]]

    init(routeResults: [[NavigationRouteSnapshot]]) {
        self.routeResults = routeResults
    }

    func makeOperation(
        for request: NavigationRoutePlanRequest
    ) throws -> any NavigationDirectionsOperation {
        SelectionIdentityOperation(routes: routeResults.removeFirst())
    }

    func failure(from error: Error) -> NavigationRoutePlanFailure {
        .unknown
    }
}

@MainActor
private final class SelectionIdentityOperation: NavigationDirectionsOperation {
    private let routes: [NavigationRouteSnapshot]

    init(routes: [NavigationRouteSnapshot]) {
        self.routes = routes
    }

    func calculate() async throws -> [NavigationRouteSnapshot] {
        routes
    }

    func cancel() {}
}
