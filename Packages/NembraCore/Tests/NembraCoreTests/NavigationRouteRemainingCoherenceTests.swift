import Foundation
import Testing
@testable import NembraCore

@Suite("Navigation route remaining-distance coherence")
struct NavigationRouteRemainingCoherenceTests {
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
            receivedAtUptimeNanoseconds: 500,
            horizontalAccuracyMeters: 3,
            isSimulatedBySoftware: true
        )
        return QualityScreenedRideLocation(
            sample: sample,
            distanceDeltaMeters: 1,
            startsNewRouteSegment: false
        )
    }

    private func matcher() throws -> NavigationRouteGeometryMatcher {
        NavigationRouteGeometryMatcher(
            policy: try NavigationRouteGeometryMatchingPolicy(
                maximumRouteDistanceMeters: 30,
                minimumStepAmbiguitySeparationMeters: 4,
                minimumWithinGeometryProgressSeparationMeters: 25
            )
        )
    }

    @Test("one provider step cannot be longer than the whole route")
    func rejectsSingleStepLongerThanRoute() throws {
        let a = try coordinate(45.0000, -122.0000)
        let b = try coordinate(45.0010, -122.0000)
        let step = try NavigationRouteStepSnapshot(
            geometry: [a, b],
            instructions: "Continue",
            notice: nil,
            distanceMeters: 201,
            transportMode: .cycling
        )

        #expect(throws: NavigationRouteDomainError.invalidDistance) {
            _ = try NavigationRouteSnapshot(
                provenance: .appleMapKitCycling(),
                name: "Impossible provider distance",
                geometry: [a, b],
                steps: [step],
                distanceMeters: 200,
                expectedTravelTimeSeconds: 60,
                hasHighways: false,
                hasTolls: false,
                advisoryNotices: []
            )
        }
    }

    @Test("step totals may still differ from the provider route distance")
    func preservesIndependentProviderTotals() throws {
        let a = try coordinate(45.0000, -122.0000)
        let b = try coordinate(45.0010, -122.0000)
        let c = try coordinate(45.0020, -122.0000)
        let first = try NavigationRouteStepSnapshot(
            geometry: [a, b],
            instructions: "First",
            notice: nil,
            distanceMeters: 100,
            transportMode: .cycling
        )
        let second = try NavigationRouteStepSnapshot(
            geometry: [b, c],
            instructions: "Second",
            notice: nil,
            distanceMeters: 150,
            transportMode: .cycling
        )

        let route = try NavigationRouteSnapshot(
            provenance: .appleMapKitCycling(),
            name: "Independent totals",
            geometry: [a, b, c],
            steps: [first, second],
            distanceMeters: 200,
            expectedTravelTimeSeconds: 90,
            hasHighways: false,
            hasTolls: false,
            advisoryNotices: []
        )

        #expect(route.steps.reduce(0) { $0 + $1.distanceMeters } == 250)
        #expect(route.distanceMeters == 200)
    }

    @Test("contradictory independent projections fail guidance confidence without throwing")
    func contradictoryProjectionFailsClosedCoherently() throws {
        let a = try coordinate(45.0000, -122.0000)
        let b = try coordinate(45.0010, -122.0000)
        let c = try coordinate(45.0020, -122.0000)
        let first = try NavigationRouteStepSnapshot(
            geometry: [a, b],
            instructions: "First",
            notice: nil,
            distanceMeters: 100,
            transportMode: .cycling
        )
        let second = try NavigationRouteStepSnapshot(
            geometry: [b, c],
            instructions: "Second",
            notice: nil,
            distanceMeters: 150,
            transportMode: .cycling
        )
        let route = try NavigationRouteSnapshot(
            provenance: .appleMapKitCycling(),
            name: "Independent totals",
            geometry: [a, b, c],
            steps: [first, second],
            distanceMeters: 200,
            expectedTravelTimeSeconds: 90,
            hasHighways: false,
            hasTolls: false,
            advisoryNotices: []
        )

        let match = try matcher().match(
            location: screened(45.0015, -122.0000),
            route: route
        )

        #expect(match.stepIndex == 1)
        #expect(abs(match.distanceRemainingOnStepMeters - 75) < 1)
        #expect(abs(match.distanceRemainingOnRouteMeters - 75) < 1)
        #expect(!match.isProgressAssignmentConfident)

        var tracker = NavigationGuidanceProgressTracker()
        let token = try tracker.select(route: route)
        let observation = try match.guidanceObservation(selectionToken: token)
        #expect(!observation.isProgressAssignmentConfident)
        #expect(try tracker.observe(observation))

        guard case let .unavailable(_, _, reason) = tracker.state else {
            Issue.record("Contradictory projections must not publish active guidance")
            return
        }
        #expect(reason == .ambiguousProgress)
    }
}
