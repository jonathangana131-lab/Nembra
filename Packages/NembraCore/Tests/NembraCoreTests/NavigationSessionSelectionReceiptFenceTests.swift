import Foundation
import Testing
@testable import NembraCore

@Suite("Navigation session route-selection receipt fence")
struct NavigationSessionSelectionReceiptFenceTests {
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

    @Test("callback received before selection cannot become new-route evidence when delivered later")
    func queuedPreselectionCallbackFailsClosed() throws {
        var session = try coordinator()
        #expect(try session.process(location: location(uptime: 20)) == nil)

        _ = try session.select(
            route: route(),
            receiptFence: NavigationRouteSelectionReceiptFence(selectedAtUptimeNanoseconds: 100)
        )
        let awaitingState = session.guidanceState

        #expect(throws: NavigationSessionCoordinatorError.locationReceivedAtOrBeforeSelectionFence) {
            try session.process(location: location(uptime: 90))
        }
        #expect(session.guidanceState == awaitingState)

        // Rejected pre-selection delivery is still a seen callback. It must keep
        // replay protection even though it never became navigation evidence.
        #expect(throws: NavigationSessionCoordinatorError.nonMonotonicLocation) {
            try session.process(location: location(uptime: 89))
        }
        #expect(session.guidanceState == awaitingState)

        let freshResult = try session.process(location: location(uptime: 101))
        let freshUpdate = try #require(freshResult)
        guard case .active = freshUpdate.guidanceState else {
            Issue.record("Expected post-selection receipt to recover active guidance")
            return
        }
    }

    @Test("receipt exactly at the selection boundary fails closed")
    func equalFenceReceiptFailsClosed() throws {
        var session = try coordinator()
        _ = try session.select(
            route: route(),
            receiptFence: NavigationRouteSelectionReceiptFence(selectedAtUptimeNanoseconds: 100)
        )
        let awaitingState = session.guidanceState

        #expect(throws: NavigationSessionCoordinatorError.locationReceivedAtOrBeforeSelectionFence) {
            try session.process(location: location(uptime: 100))
        }
        #expect(session.guidanceState == awaitingState)

        let freshResult = try session.process(location: location(uptime: 101))
        _ = try #require(freshResult)
    }

    @Test("existing seen-location chronology remains stronger than an older selection fence")
    func priorSeenHighWaterStillDominates() throws {
        var session = try coordinator()
        #expect(try session.process(location: location(uptime: 120)) == nil)

        _ = try session.select(
            route: route(),
            receiptFence: NavigationRouteSelectionReceiptFence(selectedAtUptimeNanoseconds: 100)
        )
        let awaitingState = session.guidanceState

        #expect(throws: NavigationSessionCoordinatorError.nonMonotonicLocation) {
            try session.process(location: location(uptime: 110))
        }
        #expect(session.guidanceState == awaitingState)

        let freshResult = try session.process(location: location(uptime: 121))
        _ = try #require(freshResult)
    }

    @Test("clearing navigation removes the old route-selection fence without resetting seen chronology")
    func clearRouteRemovesSelectionFence() throws {
        var session = try coordinator()
        _ = try session.select(
            route: route(),
            receiptFence: NavigationRouteSelectionReceiptFence(selectedAtUptimeNanoseconds: 100)
        )
        session.clearRoute()

        // No route is selected, so an older-than-former-fence receipt remains
        // harmless idle chronology rather than inheriting a stale route boundary.
        #expect(try session.process(location: location(uptime: 90)) == nil)
        #expect(session.guidanceState == .idle)

        _ = try session.select(route: route())
        let freshResult = try session.process(location: location(uptime: 91))
        _ = try #require(freshResult)
    }
}
