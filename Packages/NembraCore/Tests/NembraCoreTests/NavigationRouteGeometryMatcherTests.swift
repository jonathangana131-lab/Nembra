import Foundation
import Testing
@testable import NembraCore

@Suite("Navigation route geometry matcher")
struct NavigationRouteGeometryMatcherTests {
    private func coordinate(_ latitude: Double, _ longitude: Double) throws -> NavigationRouteCoordinate {
        try NavigationRouteCoordinate(latitude: latitude, longitude: longitude)
    }

    private func screened(
        latitude: Double,
        longitude: Double,
        uptime: UInt64 = 100,
        startsNewSegment: Bool = false
    ) throws -> QualityScreenedRideLocation {
        let date = Date(timeIntervalSinceReferenceDate: 1_000)
        let sample = try RideLocationSample(
            latitude: latitude,
            longitude: longitude,
            sourceMeasurementDate: date,
            receivedAtDate: date,
            receivedAtUptimeNanoseconds: uptime,
            horizontalAccuracyMeters: 3,
            isSimulatedBySoftware: true
        )
        return QualityScreenedRideLocation(
            sample: sample,
            distanceDeltaMeters: startsNewSegment ? nil : 1,
            startsNewRouteSegment: startsNewSegment
        )
    }

    private func straightRoute() throws -> NavigationRouteSnapshot {
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
        return try NavigationRouteSnapshot(
            provenance: .appleMapKitCycling(),
            name: "Straight",
            geometry: [a, b, c],
            steps: [first, second],
            distanceMeters: 300,
            expectedTravelTimeSeconds: 120,
            hasHighways: false,
            hasTolls: false,
            advisoryNotices: []
        )
    }

    private func matcher(maximumDistance: Double = 30, ambiguitySeparation: Double = 4) throws -> NavigationRouteGeometryMatcher {
        NavigationRouteGeometryMatcher(
            policy: try NavigationRouteGeometryMatchingPolicy(
                maximumRouteDistanceMeters: maximumDistance,
                minimumStepAmbiguitySeparationMeters: ambiguitySeparation
            )
        )
    }

    @Test("accepted point on first step yields provider-scaled progress")
    func firstStepProgress() throws {
        let match = try matcher().match(
            location: screened(latitude: 45.0005, longitude: -122.0000),
            route: straightRoute()
        )

        #expect(match.stepIndex == 0)
        #expect(match.isProgressAssignmentConfident)
        #expect(match.distanceFromRouteMeters < 0.01)
        #expect(abs(match.distanceRemainingOnStepMeters - 50) < 1)
        #expect(abs(match.distanceRemainingOnRouteMeters - 225) < 2)
    }

    @Test("accepted point on second step chooses second provider step")
    func secondStepProgress() throws {
        let match = try matcher().match(
            location: screened(latitude: 45.0015, longitude: -122.0000),
            route: straightRoute()
        )

        #expect(match.stepIndex == 1)
        #expect(match.isProgressAssignmentConfident)
        #expect(abs(match.distanceRemainingOnStepMeters - 75) < 1)
        #expect(abs(match.distanceRemainingOnRouteMeters - 75) < 2)
    }

    @Test("provider route distance is scaled independently of provider step totals")
    func providerTotalsRemainIndependent() throws {
        let match = try matcher().match(
            location: screened(latitude: 45.0005, longitude: -122.0000),
            route: straightRoute()
        )

        #expect(abs(match.distanceRemainingOnStepMeters - 50) < 1)
        #expect(abs(match.distanceRemainingOnRouteMeters - 225) < 2)
        #expect(match.distanceRemainingOnRouteMeters != 200)
    }

    @Test("far accepted point keeps distance evidence but fails progress confidence")
    func farPointFailsConfidence() throws {
        let match = try matcher(maximumDistance: 10).match(
            location: screened(latitude: 45.0005, longitude: -122.0010),
            route: straightRoute()
        )

        #expect(match.distanceFromRouteMeters > 10)
        #expect(!match.isProgressAssignmentConfident)
    }

    @Test("nearby parallel step ambiguity fails closed")
    func parallelStepAmbiguityFailsClosed() throws {
        let west1 = try coordinate(45.0000, -122.0010)
        let east1 = try coordinate(45.0000, -121.9990)
        let west2 = try coordinate(45.00005, -122.0010)
        let east2 = try coordinate(45.00005, -121.9990)
        let step1 = try NavigationRouteStepSnapshot(geometry: [west1, east1], instructions: "A", notice: nil, distanceMeters: 100, transportMode: .cycling)
        let step2 = try NavigationRouteStepSnapshot(geometry: [west2, east2], instructions: "B", notice: nil, distanceMeters: 100, transportMode: .cycling)
        let route = try NavigationRouteSnapshot(
            provenance: .appleMapKitCycling(),
            name: "Parallel",
            geometry: [west1, east1, east2, west2],
            steps: [step1, step2],
            distanceMeters: 250,
            expectedTravelTimeSeconds: 100,
            hasHighways: false,
            hasTolls: false,
            advisoryNotices: []
        )

        let match = try matcher(maximumDistance: 30, ambiguitySeparation: 4).match(
            location: screened(latitude: 45.000025, longitude: -122.0000),
            route: route
        )

        #expect(!match.isProgressAssignmentConfident)
        #expect(match.distanceFromRouteMeters < 5)
    }

    @Test("known screened route-segment boundary survives matching")
    func continuityFlagPreserved() throws {
        let match = try matcher().match(
            location: screened(latitude: 45.0005, longitude: -122.0000, startsNewSegment: true),
            route: straightRoute()
        )

        #expect(match.startsNewRouteSegment)
    }

    @Test("route endpoint produces zero provider-scaled remaining distance")
    func endpointProducesZeroRemaining() throws {
        let match = try matcher().match(
            location: screened(latitude: 45.0020, longitude: -122.0000),
            route: straightRoute()
        )

        #expect(match.stepIndex == 1)
        #expect(match.isProgressAssignmentConfident)
        #expect(match.distanceRemainingOnStepMeters < 0.001)
        #expect(match.distanceRemainingOnRouteMeters < 0.001)
    }

    @Test("zero-distance one-point provider route remains representable")
    func zeroDistancePointRoute() throws {
        let point = try coordinate(45, -122)
        let step = try NavigationRouteStepSnapshot(geometry: [point], instructions: "Arrive", notice: nil, distanceMeters: 0, transportMode: .cycling)
        let route = try NavigationRouteSnapshot(
            provenance: .appleMapKitCycling(),
            name: "Point",
            geometry: [point],
            steps: [step],
            distanceMeters: 0,
            expectedTravelTimeSeconds: 0,
            hasHighways: false,
            hasTolls: false,
            advisoryNotices: []
        )

        let match = try matcher().match(location: screened(latitude: 45, longitude: -122), route: route)

        #expect(match.isProgressAssignmentConfident)
        #expect(match.distanceRemainingOnStepMeters == 0)
        #expect(match.distanceRemainingOnRouteMeters == 0)
    }

    @Test("nonzero provider distance with degenerate geometry fails confidence")
    func degenerateGeometryFailsConfidence() throws {
        let point = try coordinate(45, -122)
        let step = try NavigationRouteStepSnapshot(geometry: [point], instructions: "Unknown", notice: nil, distanceMeters: 50, transportMode: .cycling)
        let route = try NavigationRouteSnapshot(
            provenance: .appleMapKitCycling(),
            name: "Degenerate",
            geometry: [point],
            steps: [step],
            distanceMeters: 50,
            expectedTravelTimeSeconds: 10,
            hasHighways: false,
            hasTolls: false,
            advisoryNotices: []
        )

        let match = try matcher().match(location: screened(latitude: 45, longitude: -122), route: route)
        #expect(!match.isProgressAssignmentConfident)
        #expect(match.distanceRemainingOnRouteMeters == 50)
    }

    @Test("match converts directly into guidance observation without changing evidence")
    func guidanceObservationProjection() throws {
        let route = try straightRoute()
        let match = try matcher().match(
            location: screened(latitude: 45.0005, longitude: -122.0000, uptime: 777),
            route: route
        )
        var tracker = NavigationGuidanceProgressTracker()
        let token = try tracker.select(route: route)
        let observation = try match.guidanceObservation(selectionToken: token)

        #expect(observation.receivedAtUptimeNanoseconds == 777)
        #expect(observation.stepIndex == match.stepIndex)
        #expect(observation.distanceRemainingOnRouteMeters == match.distanceRemainingOnRouteMeters)
        #expect(observation.isProgressAssignmentConfident == match.isProgressAssignmentConfident)
    }

    @Test("match converts directly into reroute observation")
    func rerouteObservationProjection() throws {
        let match = try matcher().match(
            location: screened(latitude: 45.0005, longitude: -122.0010, uptime: 888),
            route: straightRoute()
        )
        let observation = try match.rerouteObservation()

        #expect(observation.receivedAtUptimeNanoseconds == 888)
        #expect(observation.distanceFromActiveRouteMeters == match.distanceFromRouteMeters)
        #expect(observation.isProgressAssignmentConfident == match.isProgressAssignmentConfident)
    }

    @Test("invalid confidence policy is rejected")
    func invalidPolicyRejected() {
        #expect(throws: NavigationRouteGeometryMatchingError.invalidPolicy) {
            try NavigationRouteGeometryMatchingPolicy(
                maximumRouteDistanceMeters: 0,
                minimumStepAmbiguitySeparationMeters: 4
            )
        }
        #expect(throws: NavigationRouteGeometryMatchingError.invalidPolicy) {
            try NavigationRouteGeometryMatchingPolicy(
                maximumRouteDistanceMeters: 30,
                minimumStepAmbiguitySeparationMeters: .nan
            )
        }
    }

    @Test("dateline-adjacent geometry uses wrapped longitude distance")
    func datelineLongitudeWrap() throws {
        let a = try coordinate(0, 179.999)
        let b = try coordinate(0, -179.999)
        let step = try NavigationRouteStepSnapshot(geometry: [a, b], instructions: "Cross", notice: nil, distanceMeters: 222, transportMode: .cycling)
        let route = try NavigationRouteSnapshot(
            provenance: .appleMapKitCycling(),
            name: "Dateline",
            geometry: [a, b],
            steps: [step],
            distanceMeters: 222,
            expectedTravelTimeSeconds: 100,
            hasHighways: false,
            hasTolls: false,
            advisoryNotices: []
        )

        let match = try matcher(maximumDistance: 30).match(
            location: screened(latitude: 0, longitude: 180),
            route: route
        )

        #expect(match.distanceFromRouteMeters < 0.1)
        #expect(match.isProgressAssignmentConfident)
        #expect(abs(match.distanceRemainingOnRouteMeters - 111) < 2)
    }
}
