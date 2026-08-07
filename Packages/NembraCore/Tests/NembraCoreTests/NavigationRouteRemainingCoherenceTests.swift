import Foundation
import Testing
@testable import NembraCore

@Suite("Navigation route remaining-distance coherence")
struct NavigationRouteRemainingCoherenceTests {
    private func coordinate(_ latitude: Double, _ longitude: Double) throws -> NavigationRouteCoordinate {
        try NavigationRouteCoordinate(latitude: latitude, longitude: longitude)
    }

    private func route() throws -> NavigationRouteSnapshot {
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
            name: "Independent provider totals",
            geometry: [a, b, c],
            steps: [first, second],
            distanceMeters: 200,
            expectedTravelTimeSeconds: 90,
            hasHighways: false,
            hasTolls: false,
            advisoryNotices: []
        )
    }

    private func screened() throws -> QualityScreenedRideLocation {
        let date = Date(timeIntervalSinceReferenceDate: 1_000)
        let sample = try RideLocationSample(
            latitude: 45.0015,
            longitude: -122.0000,
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

    private func geometryPolicy() throws -> NavigationRouteGeometryMatchingPolicy {
        try NavigationRouteGeometryMatchingPolicy(
            maximumRouteDistanceMeters: 30,
            minimumStepAmbiguitySeparationMeters: 4,
            minimumWithinGeometryProgressSeparationMeters: 25
        )
    }

    @Test("contradictory independent projections preserve raw evidence and fail closed")
    func contradictoryProjectionPreservesEvidence() throws {
        let selectedRoute = try route()
        let matcher = NavigationRouteGeometryMatcher(policy: try geometryPolicy())
        let match = matcher.match(location: try screened(), route: selectedRoute)

        #expect(match.stepIndex == 1)
        #expect(abs(match.distanceRemainingOnStepMeters - 75) < 1)
        #expect(abs(match.distanceRemainingOnRouteMeters - 50) < 1)
        #expect(match.distanceRemainingOnStepMeters > match.distanceRemainingOnRouteMeters)
        #expect(!match.isProgressAssignmentConfident)

        var tracker = NavigationGuidanceProgressTracker()
        let token = try tracker.select(route: selectedRoute)
        let observation = try match.guidanceObservation(selectionToken: token)
        #expect(abs(observation.distanceRemainingOnStepMeters - 75) < 1)
        #expect(abs(observation.distanceRemainingOnRouteMeters - 75) < 1)
        #expect(!observation.isProgressAssignmentConfident)
        #expect(try tracker.observe(observation))
        #expect(
            tracker.state == .unavailable(
                token: token,
                route: selectedRoute,
                reason: .ambiguousProgress
            )
        )
    }

    @Test("session coordinator consumes incoherent projections transactionally")
    func sessionCoordinatorFailsProgressClosed() throws {
        let selectedRoute = try route()
        var coordinator = NavigationSessionCoordinator(
            geometryPolicy: try geometryPolicy(),
            reroutePolicy: try NavigationReroutePolicy(
                minimumDeviationDistanceMeters: 20,
                requiredConsecutiveAcceptedSamples: 2,
                minimumConsecutiveDeviationDurationNanoseconds: 1,
                rerouteCooldownNanoseconds: 1
            )
        )
        let token = try coordinator.select(route: selectedRoute)

        guard let update = try coordinator.process(location: screened()) else {
            Issue.record("Selected navigation route must produce a session update")
            return
        }

        #expect(update.geometryMatch.distanceRemainingOnStepMeters > update.geometryMatch.distanceRemainingOnRouteMeters)
        #expect(!update.geometryMatch.isProgressAssignmentConfident)
        #expect(update.rerouteDecision == .keepCurrentRoute)
        #expect(
            update.guidanceState == .unavailable(
                token: token,
                route: selectedRoute,
                reason: .ambiguousProgress
            )
        )
    }
}
