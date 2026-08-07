import Testing
@testable import NembraCore

@Suite("Navigation route request token identity")
struct NavigationRouteRequestIdentityTests {
    private func coordinate(_ latitude: Double, _ longitude: Double) throws -> NavigationRouteCoordinate {
        try NavigationRouteCoordinate(latitude: latitude, longitude: longitude)
    }

    private func request() throws -> NavigationRoutePlanRequest {
        NavigationRoutePlanRequest.appleMapKitCycling(
            source: try coordinate(45.6380, -122.6615),
            destination: try coordinate(45.6500, -122.6750)
        )
    }

    private func route() throws -> NavigationRouteSnapshot {
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
            provenance: NavigationRouteProvenance(
                provider: .appleMapKit,
                requestedTransportMode: .cycling,
                returnedTransportMode: .cycling
            ),
            name: "Route",
            geometry: [start, end],
            steps: [step],
            distanceMeters: 1_500,
            expectedTravelTimeSeconds: 480,
            hasHighways: false,
            hasTolls: false,
            advisoryNotices: []
        )
    }

    @Test("fresh coordinators cannot mint equal first request tokens")
    func freshCoordinatorTokensDoNotCollide() throws {
        var firstCoordinator = NavigationRoutePlanningCoordinator()
        var secondCoordinator = NavigationRoutePlanningCoordinator()

        let first = try firstCoordinator.begin(request())
        let second = try secondCoordinator.begin(request())

        #expect(first.token.sequence == 1)
        #expect(second.token.sequence == 1)
        #expect(first.token != second.token)
    }

    @Test("stale callback from a recreated coordinator cannot publish")
    func recreatedCoordinatorRejectsOldToken() throws {
        var oldCoordinator = NavigationRoutePlanningCoordinator()
        let old = try oldCoordinator.begin(request())

        var recreatedCoordinator = NavigationRoutePlanningCoordinator()
        let currentRequest = try request()
        let current = try recreatedCoordinator.begin(currentRequest)
        let staleRoute = try route()
        let staleAccepted = recreatedCoordinator.complete(
            token: old.token,
            routes: [staleRoute]
        )

        #expect(old.token.sequence == current.token.sequence)
        #expect(old.token != current.token)
        #expect(staleAccepted == false)
        #expect(recreatedCoordinator.state == .requesting(token: current.token, request: currentRequest))
    }

    @Test("copied coordinators that diverge cannot mint equal request tokens")
    func copiedCoordinatorTokensDoNotCollide() throws {
        var firstCopy = NavigationRoutePlanningCoordinator()
        var secondCopy = firstCopy
        let firstRequest = try request()
        let secondRequest = try request()

        let first = try firstCopy.begin(firstRequest)
        let second = try secondCopy.begin(secondRequest)
        let staleAccepted = firstCopy.fail(token: second.token, reason: .serverFailure)

        #expect(first.token.sequence == second.token.sequence)
        #expect(first.token != second.token)
        #expect(staleAccepted == false)
        #expect(firstCopy.state == .requesting(token: first.token, request: firstRequest))
    }

    @Test("one coordinator keeps monotonic sequence while token identity stays unique")
    func sequenceRemainsMonotonicAndIdentityUnique() throws {
        var coordinator = NavigationRoutePlanningCoordinator()
        let first = try coordinator.begin(request())
        let second = try coordinator.begin(request())

        #expect(first.token.sequence == 1)
        #expect(second.token.sequence == 2)
        #expect(first.token != second.token)
        #expect(second.supersededToken == first.token)
    }
}
