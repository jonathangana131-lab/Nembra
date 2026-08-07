import Testing
@testable import NembraCore

@Suite("Navigation route domain")
struct NavigationRouteDomainTests {
    private func coordinate(_ latitude: Double, _ longitude: Double) throws -> NavigationRouteCoordinate {
        try NavigationRouteCoordinate(latitude: latitude, longitude: longitude)
    }

    private func step(
        distanceMeters: Double = 125,
        instructions: String = "Continue straight",
        notice: String? = nil,
        transportMode: NavigationRouteTransportMode = .cycling
    ) throws -> NavigationRouteStepSnapshot {
        try NavigationRouteStepSnapshot(
            geometry: [
                coordinate(45.6380, -122.6615),
                coordinate(45.6385, -122.6600),
            ],
            instructions: instructions,
            notice: notice,
            distanceMeters: distanceMeters,
            transportMode: transportMode
        )
    }

    @Test("MapKit cycling provenance is explicit and is not scooter legality")
    func cyclingProvenanceIsExplicit() {
        let provenance = NavigationRouteProvenance.appleMapKitCycling()

        #expect(provenance.provider == .appleMapKit)
        #expect(provenance.requestedTransportMode == .cycling)
        #expect(provenance.returnedTransportMode == .cycling)
    }

    @Test("valid route projection preserves provider facts exactly")
    func validRoutePreservesFacts() throws {
        let first = try coordinate(45.6380, -122.6615)
        let second = try coordinate(45.6400, -122.6580)
        let routeStep = try step(notice: "Seasonal closure possible")
        let route = try NavigationRouteSnapshot(
            provenance: .appleMapKitCycling(),
            name: "Waterfront route",
            geometry: [first, second],
            steps: [routeStep],
            distanceMeters: 712.4,
            expectedTravelTimeSeconds: 233,
            hasHighways: false,
            hasTolls: false,
            advisoryNotices: ["Seasonal closure possible", "Use caution"]
        )

        #expect(route.name == "Waterfront route")
        #expect(route.geometry == [first, second])
        #expect(route.steps == [routeStep])
        #expect(route.distanceMeters == 712.4)
        #expect(route.expectedTravelTimeSeconds == 233)
        #expect(route.hasHighways == false)
        #expect(route.hasTolls == false)
        #expect(route.advisoryNotices == ["Seasonal closure possible", "Use caution"])
    }

    @Test("invalid route coordinates fail closed")
    func invalidCoordinatesFailClosed() {
        #expect(throws: NavigationRouteDomainError.invalidCoordinate) {
            _ = try NavigationRouteCoordinate(latitude: 90.01, longitude: 0)
        }
        #expect(throws: NavigationRouteDomainError.invalidCoordinate) {
            _ = try NavigationRouteCoordinate(latitude: 0, longitude: -180.01)
        }
        #expect(throws: NavigationRouteDomainError.invalidCoordinate) {
            _ = try NavigationRouteCoordinate(latitude: .nan, longitude: 0)
        }
        #expect(throws: NavigationRouteDomainError.invalidCoordinate) {
            _ = try NavigationRouteCoordinate(latitude: 0, longitude: .infinity)
        }
    }

    @Test("coordinate boundary values remain valid")
    func coordinateBoundariesRemainValid() throws {
        #expect(try coordinate(90, 180) == NavigationRouteCoordinate(latitude: 90, longitude: 180))
        #expect(try coordinate(-90, -180) == NavigationRouteCoordinate(latitude: -90, longitude: -180))
    }

    @Test("route requires provider geometry")
    func emptyRouteGeometryFailsClosed() throws {
        let routeStep = try step()

        #expect(throws: NavigationRouteDomainError.emptyRouteGeometry) {
            _ = try NavigationRouteSnapshot(
                provenance: .appleMapKitCycling(),
                name: "",
                geometry: [],
                steps: [routeStep],
                distanceMeters: 0,
                expectedTravelTimeSeconds: 0,
                hasHighways: false,
                hasTolls: false,
                advisoryNotices: []
            )
        }
    }

    @Test("route requires at least one provider step")
    func emptyRouteStepsFailClosed() throws {
        let point = try coordinate(45.6380, -122.6615)

        #expect(throws: NavigationRouteDomainError.emptyRouteSteps) {
            _ = try NavigationRouteSnapshot(
                provenance: .appleMapKitCycling(),
                name: "",
                geometry: [point],
                steps: [],
                distanceMeters: 0,
                expectedTravelTimeSeconds: 0,
                hasHighways: false,
                hasTolls: false,
                advisoryNotices: []
            )
        }
    }

    @Test("route step requires provider geometry")
    func emptyStepGeometryFailsClosed() {
        #expect(throws: NavigationRouteDomainError.emptyStepGeometry) {
            _ = try NavigationRouteStepSnapshot(
                geometry: [],
                instructions: "",
                notice: nil,
                distanceMeters: 0,
                transportMode: .cycling
            )
        }
    }

    @Test("negative and nonfinite distances are rejected")
    func invalidDistancesAreRejected() throws {
        let point = try coordinate(45.6380, -122.6615)
        let routeStep = try step()

        for invalid in [-1.0, .infinity, -.infinity, .nan] {
            #expect(throws: NavigationRouteDomainError.invalidDistance) {
                _ = try NavigationRouteStepSnapshot(
                    geometry: [point],
                    instructions: "",
                    notice: nil,
                    distanceMeters: invalid,
                    transportMode: .cycling
                )
            }

            #expect(throws: NavigationRouteDomainError.invalidDistance) {
                _ = try NavigationRouteSnapshot(
                    provenance: .appleMapKitCycling(),
                    name: "",
                    geometry: [point],
                    steps: [routeStep],
                    distanceMeters: invalid,
                    expectedTravelTimeSeconds: 0,
                    hasHighways: false,
                    hasTolls: false,
                    advisoryNotices: []
                )
            }
        }
    }

    @Test("negative and nonfinite expected travel time is rejected")
    func invalidExpectedTravelTimeIsRejected() throws {
        let point = try coordinate(45.6380, -122.6615)
        let routeStep = try step()

        for invalid in [-1.0, .infinity, -.infinity, .nan] {
            #expect(throws: NavigationRouteDomainError.invalidExpectedTravelTime) {
                _ = try NavigationRouteSnapshot(
                    provenance: .appleMapKitCycling(),
                    name: "",
                    geometry: [point],
                    steps: [routeStep],
                    distanceMeters: 0,
                    expectedTravelTimeSeconds: invalid,
                    hasHighways: false,
                    hasTolls: false,
                    advisoryNotices: []
                )
            }
        }
    }

    @Test("zero distance and zero travel time are preserved instead of invented")
    func zeroBoundariesArePreserved() throws {
        let point = try coordinate(45.6380, -122.6615)
        let routeStep = try step(distanceMeters: 0, instructions: "")
        let route = try NavigationRouteSnapshot(
            provenance: .appleMapKitCycling(),
            name: "",
            geometry: [point],
            steps: [routeStep],
            distanceMeters: 0,
            expectedTravelTimeSeconds: 0,
            hasHighways: false,
            hasTolls: false,
            advisoryNotices: []
        )

        #expect(route.distanceMeters == 0)
        #expect(route.expectedTravelTimeSeconds == 0)
        #expect(route.steps[0].distanceMeters == 0)
    }

    @Test("step totals are not forced to equal provider route distance")
    func providerDistanceDomainsRemainIndependent() throws {
        let point = try coordinate(45.6380, -122.6615)
        let route = try NavigationRouteSnapshot(
            provenance: .appleMapKitCycling(),
            name: "",
            geometry: [point],
            steps: [try step(distanceMeters: 125)],
            distanceMeters: 130,
            expectedTravelTimeSeconds: 30,
            hasHighways: false,
            hasTolls: false,
            advisoryNotices: []
        )

        #expect(route.distanceMeters == 130)
        #expect(route.steps[0].distanceMeters == 125)
    }

    @Test("provider strings are preserved without maneuver parsing")
    func providerStringsArePreserved() throws {
        let routeStep = try step(
            instructions: "  Continue onto Main St.  ",
            notice: ""
        )

        #expect(routeStep.instructions == "  Continue onto Main St.  ")
        #expect(routeStep.notice == "")
    }

    @Test("future or combined transport semantics can fail to unknown")
    func unknownTransportIsRepresentable() throws {
        let routeStep = try step(transportMode: .unknown)
        let provenance = NavigationRouteProvenance.appleMapKitCycling(returnedTransportMode: .unknown)

        #expect(routeStep.transportMode == .unknown)
        #expect(provenance.requestedTransportMode == .cycling)
        #expect(provenance.returnedTransportMode == .unknown)
    }
}
