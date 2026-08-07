import Foundation
import Testing
@testable import NembraCore

@Suite("Navigation route geometry consistency")
struct NavigationRouteGeometryConsistencyTests {
    private func coordinate(_ latitude: Double, _ longitude: Double) throws -> NavigationRouteCoordinate {
        try NavigationRouteCoordinate(latitude: latitude, longitude: longitude)
    }

    private func screened(_ latitude: Double, _ longitude: Double) throws -> QualityScreenedRideLocation {
        let date = Date(timeIntervalSinceReferenceDate: 1_000)
        let sample = try RideLocationSample(
            latitude: latitude,
            longitude: longitude,
            sourceMeasurementDate: date,
            receivedAtDate: date,
            receivedAtUptimeNanoseconds: 100,
            horizontalAccuracyMeters: 3,
            isSimulatedBySoftware: true
        )
        return QualityScreenedRideLocation(
            sample: sample,
            distanceDeltaMeters: 1,
            startsNewRouteSegment: false
        )
    }

    @Test("route-near but chosen-step-far geometry fails progress confidence")
    func routeNearStepFarFailsClosed() throws {
        let routeA = try coordinate(45.0000, -122.0000)
        let routeB = try coordinate(45.0020, -122.0000)
        let stepA = try coordinate(45.0000, -122.0100)
        let stepB = try coordinate(45.0020, -122.0100)
        let contradictoryStep = try NavigationRouteStepSnapshot(
            geometry: [stepA, stepB],
            instructions: "Provider-inconsistent step",
            notice: nil,
            distanceMeters: 200,
            transportMode: .cycling
        )
        let route = try NavigationRouteSnapshot(
            provenance: .appleMapKitCycling(),
            name: "Contradictory geometry",
            geometry: [routeA, routeB],
            steps: [contradictoryStep],
            distanceMeters: 200,
            expectedTravelTimeSeconds: 60,
            hasHighways: false,
            hasTolls: false,
            advisoryNotices: []
        )
        let matcher = NavigationRouteGeometryMatcher(
            policy: try NavigationRouteGeometryMatchingPolicy(
                maximumRouteDistanceMeters: 100,
                minimumStepAmbiguitySeparationMeters: 4,
                minimumWithinGeometryProgressSeparationMeters: 25
            )
        )

        let match = matcher.match(
            location: try screened(45.0010, -122.0000),
            route: route
        )

        #expect(match.distanceFromRouteMeters < 0.01)
        #expect(!match.isProgressAssignmentConfident)
        #expect(match.isDeviationAssessmentConfident)
    }
}
