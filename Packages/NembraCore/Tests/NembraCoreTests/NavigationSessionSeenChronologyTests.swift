import Foundation
import Testing
@testable import NembraCore

@Suite("Navigation session seen callback chronology")
struct NavigationSessionSeenChronologyTests {
    private func coordinate(_ latitude: Double, _ longitude: Double) throws -> NavigationRouteCoordinate {
        try NavigationRouteCoordinate(latitude: latitude, longitude: longitude)
    }

    private func route() throws -> NavigationRouteSnapshot {
        let start = try coordinate(45.0, -122.0)
        let end = try coordinate(45.002, -122.0)
        let step = try NavigationRouteStepSnapshot(
            geometry: [start, end],
            instructions: "Continue",
            notice: nil,
            distanceMeters: 200,
            transportMode: .cycling
        )
        return try NavigationRouteSnapshot(
            provenance: .appleMapKitCycling(),
            name: "Route",
            geometry: [start, end],
            steps: [step],
            distanceMeters: 200,
            expectedTravelTimeSeconds: 100,
            hasHighways: false,
            hasTolls: false,
            advisoryNotices: []
        )
    }

    private func location(uptime: UInt64) throws -> QualityScreenedRideLocation {
        let date = Date(timeIntervalSinceReferenceDate: 1_000)
        let sample = try RideLocationSample(
            latitude: 45.001,
            longitude: -122.0,
            sourceMeasurementDate: date,
            receivedAtDate: date,
            receivedAtUptimeNanoseconds: uptime,
            horizontalAccuracyMeters: 3,
            isSimulatedBySoftware: true
        )
        return QualityScreenedRideLocation(
            sample: sample,
            distanceDeltaMeters: 1,
            startsNewRouteSegment: false
        )
    }

    private func coordinator() throws -> NavigationSessionCoordinator {
        NavigationSessionCoordinator(
            geometryPolicy: try NavigationRouteGeometryMatchingPolicy(
                maximumRouteDistanceMeters: 100,
                minimumStepAmbiguitySeparationMeters: 4,
                minimumWithinGeometryProgressSeparationMeters: 25
            ),
            reroutePolicy: try NavigationReroutePolicy(
                minimumDeviationDistanceMeters: 20,
                requiredConsecutiveAcceptedSamples: 2,
                minimumConsecutiveDeviationDurationNanoseconds: 10,
                maximumAcceptedObservationGapNanoseconds: 100,
                rerouteCooldownNanoseconds: 100
            )
        )
    }

    @Test("idle screened callbacks advance chronology before later route selection")
    func idleObservationBlocksOlderCallbackAfterSelection() throws {
        var session = try coordinator()

        #expect(try session.process(location: location(uptime: 50)) == nil)
        #expect(session.guidanceState == .idle)

        _ = try session.select(route: route())
        let awaitingState = session.guidanceState

        #expect(throws: NavigationSessionCoordinatorError.nonMonotonicLocation) {
            try session.process(location: location(uptime: 49))
        }
        #expect(session.guidanceState == awaitingState)

        let freshResult = try session.process(location: location(uptime: 51))
        let freshUpdate = try #require(freshResult)
        #expect(freshUpdate.rerouteDecision == .keepCurrentRoute)
        guard case .active = freshUpdate.guidanceState else {
            Issue.record("Expected genuinely newer location to recover active guidance")
            return
        }
    }

    @Test("cleared navigation keeps observing callback chronology")
    func clearedIntervalBlocksDelayedCallbackAfterReselection() throws {
        var session = try coordinator()
        _ = try session.select(route: route())
        let initialResult = try session.process(location: location(uptime: 30))
        _ = try #require(initialResult)
        session.clearRoute()

        #expect(try session.process(location: location(uptime: 100)) == nil)
        #expect(try session.process(location: location(uptime: 90)) == nil)
        #expect(session.guidanceState == .idle)

        _ = try session.select(route: route())
        let awaitingState = session.guidanceState

        #expect(throws: NavigationSessionCoordinatorError.nonMonotonicLocation) {
            try session.process(location: location(uptime: 90))
        }
        #expect(session.guidanceState == awaitingState)

        let freshResult = try session.process(location: location(uptime: 101))
        let freshUpdate = try #require(freshResult)
        guard case .active = freshUpdate.guidanceState else {
            Issue.record("Expected newer post-reselection location to recover active guidance")
            return
        }
    }

    @Test("older and replayed idle callbacks stay nil without regressing the high-water mark")
    func idleStaleCallbacksStayHarmlessWithoutRegressingChronology() throws {
        var session = try coordinator()

        #expect(try session.process(location: location(uptime: 70)) == nil)
        #expect(try session.process(location: location(uptime: 60)) == nil)
        #expect(try session.process(location: location(uptime: 70)) == nil)
        #expect(session.guidanceState == .idle)

        _ = try session.select(route: route())
        let awaitingState = session.guidanceState
        #expect(throws: NavigationSessionCoordinatorError.nonMonotonicLocation) {
            try session.process(location: location(uptime: 69))
        }
        #expect(session.guidanceState == awaitingState)

        let freshResult = try session.process(location: location(uptime: 71))
        let freshUpdate = try #require(freshResult)
        guard case .active = freshUpdate.guidanceState else {
            Issue.record("Expected callback above idle high-water mark to recover active guidance")
            return
        }
    }
}
