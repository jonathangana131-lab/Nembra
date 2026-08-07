import Testing
@testable import NembraCore

@Suite("Navigation route distance consistency")
struct NavigationRouteDistanceConsistencyTests {
    private func coordinate(_ latitude: Double, _ longitude: Double) throws -> NavigationRouteCoordinate {
        try NavigationRouteCoordinate(latitude: latitude, longitude: longitude)
    }

    private func step(
        from start: NavigationRouteCoordinate,
        to end: NavigationRouteCoordinate,
        distanceMeters: Double
    ) throws -> NavigationRouteStepSnapshot {
        try NavigationRouteStepSnapshot(
            geometry: [start, end],
            instructions: "Continue",
            notice: nil,
            distanceMeters: distanceMeters,
            transportMode: .cycling
        )
    }

    @Test("one provider step cannot be longer than the entire provider route")
    func rejectsStepLongerThanRoute() throws {
        let a = try coordinate(45.6380, -122.6615)
        let b = try coordinate(45.6390, -122.6600)
        let routeStep = try step(from: a, to: b, distanceMeters: 131)

        #expect(throws: NavigationRouteDomainError.invalidDistance) {
            _ = try NavigationRouteSnapshot(
                provenance: .appleMapKitCycling(),
                name: "Contradictory route",
                geometry: [a, b],
                steps: [routeStep],
                distanceMeters: 130,
                expectedTravelTimeSeconds: 60,
                hasHighways: false,
                hasTolls: false,
                advisoryNotices: []
            )
        }
    }

    @Test("provider step totals remain independent from route total")
    func allowsStepSumToDifferFromRouteTotal() throws {
        let a = try coordinate(45.6380, -122.6615)
        let b = try coordinate(45.6390, -122.6600)
        let c = try coordinate(45.6400, -122.6585)
        let first = try step(from: a, to: b, distanceMeters: 80)
        let second = try step(from: b, to: c, distanceMeters: 80)

        let route = try NavigationRouteSnapshot(
            provenance: .appleMapKitCycling(),
            name: "Provider totals remain independent",
            geometry: [a, b, c],
            steps: [first, second],
            distanceMeters: 130,
            expectedTravelTimeSeconds: 60,
            hasHighways: false,
            hasTolls: false,
            advisoryNotices: []
        )

        #expect(route.distanceMeters == 130)
        #expect(route.steps.map(\.distanceMeters).reduce(0, +) == 160)
    }
}
