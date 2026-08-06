import Testing
@testable import NembraCore

@Suite("Navigation route contract")
struct NavigationRouteContractTests {
    private func coordinate(_ latitude: Double, _ longitude: Double) throws -> NavigationCoordinate {
        try NavigationCoordinate(latitude: latitude, longitude: longitude)
    }

    @Test("ES80 route intent defaults to cycling without relabeling it scooter routing")
    func requestDefaultsToCycling() throws {
        let origin = try coordinate(45.6387, -122.6615)
        let destination = try coordinate(45.5231, -122.6765)

        let request = NavigationRouteRequestIntent(origin: origin, destination: destination)

        #expect(request.origin == origin)
        #expect(request.destination == destination)
        #expect(request.transportBasis == .cycling)
        #expect(request.requestsAlternateRoutes == false)
    }

    @Test("alternate route preference is explicit")
    func alternateRoutePreferenceIsExplicit() throws {
        let request = NavigationRouteRequestIntent(
            origin: try coordinate(45.6, -122.6),
            destination: try coordinate(45.7, -122.7),
            requestsAlternateRoutes: true
        )

        #expect(request.requestsAlternateRoutes)
    }

    @Test("coordinate validation fails closed")
    func coordinatesFailClosed() {
        #expect(throws: NavigationRouteContractError.invalidLatitude) {
            _ = try NavigationCoordinate(latitude: 90.1, longitude: 0)
        }
        #expect(throws: NavigationRouteContractError.invalidLatitude) {
            _ = try NavigationCoordinate(latitude: .nan, longitude: 0)
        }
        #expect(throws: NavigationRouteContractError.invalidLongitude) {
            _ = try NavigationCoordinate(latitude: 0, longitude: 180.1)
        }
        #expect(throws: NavigationRouteContractError.invalidLongitude) {
            _ = try NavigationCoordinate(latitude: 0, longitude: .infinity)
        }
    }

    @Test("route projection preserves provider facts without maneuver inference")
    func routeProjectionPreservesProviderFacts() throws {
        let a = try coordinate(45.6387, -122.6615)
        let b = try coordinate(45.6300, -122.6700)
        let c = try coordinate(45.6200, -122.6750)
        let first = try NavigationRouteStepSnapshot(
            instruction: "Turn right onto Main Street",
            notice: "Use caution",
            distanceMeters: 650,
            geometry: [a, b]
        )
        let second = try NavigationRouteStepSnapshot(
            instruction: "Continue straight",
            notice: nil,
            distanceMeters: 900,
            geometry: [b, c]
        )

        let route = try NavigationRouteSnapshot(
            provenance: .appleMapKitCycling,
            distanceMeters: 1_550,
            expectedTravelTimeSeconds: 420,
            geometry: [a, b, c],
            steps: [first, second],
            advisoryNotices: ["Walking may be required"],
            hasHighways: false,
            hasTolls: false
        )

        #expect(route.provenance == .appleMapKitCycling)
        #expect(route.distanceMeters == 1_550)
        #expect(route.expectedTravelTimeSeconds == 420)
        #expect(route.geometry == [a, b, c])
        #expect(route.steps == [first, second])
        #expect(route.steps[0].instruction == "Turn right onto Main Street")
        #expect(route.steps[0].notice == "Use caution")
        #expect(route.advisoryNotices == ["Walking may be required"])
        #expect(route.hasHighways == false)
        #expect(route.hasTolls == false)
    }

    @Test("localized strings and empty terminal instruction are preserved verbatim")
    func providerStringsAreNotReclassified() throws {
        let point = try coordinate(45.6, -122.6)
        let step = try NavigationRouteStepSnapshot(
            instruction: "",
            notice: "Desmonte y camine",
            distanceMeters: 0,
            geometry: [point]
        )

        #expect(step.instruction == "")
        #expect(step.notice == "Desmonte y camine")
        #expect(step.distanceMeters == 0)
    }

    @Test("invalid step distances are rejected")
    func invalidStepDistancesAreRejected() throws {
        let point = try coordinate(0, 0)

        #expect(throws: NavigationRouteContractError.invalidStepDistance) {
            _ = try NavigationRouteStepSnapshot(
                instruction: "Continue",
                notice: nil,
                distanceMeters: -0.1,
                geometry: [point]
            )
        }
        #expect(throws: NavigationRouteContractError.invalidStepDistance) {
            _ = try NavigationRouteStepSnapshot(
                instruction: "Continue",
                notice: nil,
                distanceMeters: .infinity,
                geometry: [point]
            )
        }
    }

    @Test("invalid route numerics are rejected")
    func invalidRouteNumericsAreRejected() throws {
        let point = try coordinate(0, 0)
        let step = try NavigationRouteStepSnapshot(
            instruction: "Continue",
            notice: nil,
            distanceMeters: 1,
            geometry: [point]
        )

        #expect(throws: NavigationRouteContractError.invalidRouteDistance) {
            _ = try NavigationRouteSnapshot(
                provenance: .appleMapKitCycling,
                distanceMeters: -.infinity,
                expectedTravelTimeSeconds: 1,
                geometry: [point],
                steps: [step],
                advisoryNotices: [],
                hasHighways: false,
                hasTolls: false
            )
        }
        #expect(throws: NavigationRouteContractError.invalidExpectedTravelTime) {
            _ = try NavigationRouteSnapshot(
                provenance: .appleMapKitCycling,
                distanceMeters: 1,
                expectedTravelTimeSeconds: .nan,
                geometry: [point],
                steps: [step],
                advisoryNotices: [],
                hasHighways: false,
                hasTolls: false
            )
        }
    }

    @Test("missing route geometry fails closed")
    func emptyRouteGeometryIsRejected() throws {
        let point = try coordinate(0, 0)
        let step = try NavigationRouteStepSnapshot(
            instruction: "Continue",
            notice: nil,
            distanceMeters: 1,
            geometry: [point]
        )

        #expect(throws: NavigationRouteContractError.emptyRouteGeometry) {
            _ = try NavigationRouteSnapshot(
                provenance: .appleMapKitCycling,
                distanceMeters: 1,
                expectedTravelTimeSeconds: 1,
                geometry: [],
                steps: [step],
                advisoryNotices: [],
                hasHighways: false,
                hasTolls: false
            )
        }
    }

    @Test("missing route steps fail closed")
    func emptyRouteStepsAreRejected() throws {
        let point = try coordinate(0, 0)

        #expect(throws: NavigationRouteContractError.emptyRouteSteps) {
            _ = try NavigationRouteSnapshot(
                provenance: .appleMapKitCycling,
                distanceMeters: 1,
                expectedTravelTimeSeconds: 1,
                geometry: [point],
                steps: [],
                advisoryNotices: [],
                hasHighways: false,
                hasTolls: false
            )
        }
    }

    @Test("zero distance and duration remain legitimate provider facts")
    func zeroBoundariesAreValid() throws {
        let point = try coordinate(0, 0)
        let step = try NavigationRouteStepSnapshot(
            instruction: "Arrive",
            notice: nil,
            distanceMeters: 0,
            geometry: [point]
        )

        let route = try NavigationRouteSnapshot(
            provenance: .appleMapKitCycling,
            distanceMeters: 0,
            expectedTravelTimeSeconds: 0,
            geometry: [point],
            steps: [step],
            advisoryNotices: [],
            hasHighways: false,
            hasTolls: false
        )

        #expect(route.distanceMeters == 0)
        #expect(route.expectedTravelTimeSeconds == 0)
    }
}
