import Testing
@testable import NembraCore

@Suite("Navigation guidance selection identity")
struct NavigationGuidanceSelectionIdentityTests {
    private func route() throws -> NavigationRouteSnapshot {
        let start = try NavigationRouteCoordinate(latitude: 45.6380, longitude: -122.6615)
        let end = try NavigationRouteCoordinate(latitude: 45.6385, longitude: -122.6600)
        let step = try NavigationRouteStepSnapshot(
            geometry: [start, end],
            instructions: "Continue",
            notice: nil,
            distanceMeters: 100,
            transportMode: .cycling
        )
        return try NavigationRouteSnapshot(
            provenance: .appleMapKitCycling(),
            name: "Identity route",
            geometry: [start, end],
            steps: [step],
            distanceMeters: 100,
            expectedTravelTimeSeconds: 60,
            hasHighways: false,
            hasTolls: false,
            advisoryNotices: []
        )
    }

    private func observation(
        token: NavigationGuidanceSelectionToken,
        uptime: UInt64 = 10
    ) throws -> NavigationGuidanceProgressObservation {
        try NavigationGuidanceProgressObservation(
            selectionToken: token,
            receivedAtUptimeNanoseconds: uptime,
            stepIndex: 0,
            distanceRemainingOnStepMeters: 50,
            distanceRemainingOnRouteMeters: 50,
            isProgressAssignmentConfident: true
        )
    }

    @Test("fresh trackers do not reuse the same first-selection token")
    func freshTrackersHaveDistinctNamespaces() throws {
        var first = NavigationGuidanceProgressTracker()
        var second = NavigationGuidanceProgressTracker()
        let selectedRoute = try route()

        let firstToken = try first.select(route: selectedRoute)
        let secondToken = try second.select(route: selectedRoute)

        #expect(firstToken.sequence == 1)
        #expect(secondToken.sequence == 1)
        #expect(!firstToken.sharesTrackerGeneration(with: secondToken))
        #expect(firstToken != secondToken)
    }

    @Test("copied trackers that diverge cannot mint equal same-sequence selections")
    func copiedTrackersMintDistinctSelectionIdentities() throws {
        var first = NavigationGuidanceProgressTracker()
        var second = first
        let selectedRoute = try route()

        let firstToken = try first.select(route: selectedRoute)
        let secondToken = try second.select(route: selectedRoute)

        #expect(firstToken.sequence == 1)
        #expect(secondToken.sequence == 1)
        #expect(firstToken.sharesTrackerGeneration(with: secondToken))
        #expect(firstToken != secondToken)
    }

    @Test("a divergent copied-tracker token cannot publish onto the current selection")
    func divergentCopyObservationIsIgnored() throws {
        var current = NavigationGuidanceProgressTracker()
        var divergentCopy = current
        let selectedRoute = try route()

        _ = try current.select(route: selectedRoute)
        let divergentToken = try divergentCopy.select(route: selectedRoute)
        let before = current.state

        let accepted = try current.observe(observation(token: divergentToken))

        #expect(!accepted)
        #expect(current.state == before)
    }

    @Test("one tracker preserves monotonic sequence while every selection identity stays unique")
    func sameTrackerSequenceStillOrdersSelections() throws {
        var tracker = NavigationGuidanceProgressTracker()
        let selectedRoute = try route()

        let firstToken = try tracker.select(route: selectedRoute)
        let secondToken = try tracker.select(route: selectedRoute)

        #expect(firstToken.sharesTrackerGeneration(with: secondToken))
        #expect(firstToken.sequence == 1)
        #expect(secondToken.sequence == 2)
        #expect(firstToken != secondToken)
    }
}
