import Foundation
import Testing
@testable import NembraCore

@Suite("Horizon truthful presentation domain")
struct HorizonPresentationDomainTests {
    private let contextID = UUID(uuidString: "2A173EE4-31A7-4583-B2DD-4DA9DD714759")!

    private func localDay() throws -> RideLocalDay {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return try RideLocalDay(
            containing: Date(timeIntervalSince1970: 1_787_040_000),
            calendar: calendar
        )
    }

    private func navigationSnapshot(routeID: String) -> HorizonNavigationOverlaySnapshot {
        HorizonNavigationOverlaySnapshot(
            route: HorizonNavigationRouteReference(
                providerRouteID: routeID,
                geometryRevision: 7,
                updatedAtDate: Date(timeIntervalSince1970: 1_787_040_100)
            ),
            currentPositionSampleID: UUID(uuidString: "EAD165FD-AFE0-40F4-84CE-041B0A4B5ADF"),
            maneuver: HorizonNavigationManeuverFacts(
                instruction: .authoritative(value: "Turn right", authority: .navigationProvider),
                roadName: .authoritative(value: "Oak Street", authority: .navigationProvider),
                distanceMeters: .authoritative(value: 643.7376, authority: .navigationProvider),
                followingManeuverDistanceMeters: .unavailable(reason: .notYetAvailable)
            ),
            arrival: HorizonNavigationArrivalFacts(
                expectedArrivalDate: .authoritative(
                    value: Date(timeIntervalSince1970: 1_787_041_000),
                    authority: .navigationProvider
                ),
                remainingDurationSeconds: .authoritative(value: 480, authority: .navigationProvider),
                remainingDistanceMeters: .authoritative(value: 3_379.6, authority: .navigationProvider)
            )
        )
    }

    @Test("Drive, Navigation, and Explore derive one coherent semantic reflow")
    func modeTransitionsDeriveReflow() throws {
        var coordinator = HorizonPresentationCoordinator(presentationContextID: contextID)

        #expect(coordinator.mode == .drive)
        #expect(coordinator.reflow.speedRole == .dominantCentered)
        #expect(coordinator.reflow.roadWorldRole == .perspectiveDrive)
        #expect(coordinator.reflow.transientControlRole == .none)

        let navigation = try coordinator.selectMode(.navigation)
        #expect(
            navigation == .changed(
                from: .drive,
                to: .navigation,
                reflow: HorizonCockpitReflow(mode: .navigation)
            )
        )
        #expect(coordinator.reflow.speedRole == .compactLeadingPersistent)
        #expect(coordinator.reflow.roadWorldRole == .expandedNavigation)
        #expect(coordinator.reflow.transientControlRole == .maneuver)

        let unchanged = try coordinator.selectMode(.navigation)
        #expect(unchanged == .unchanged(HorizonCockpitReflow(mode: .navigation)))
        #expect(coordinator.modeRevision == 1)

        _ = try coordinator.selectMode(.explore)
        #expect(coordinator.reflow.roadWorldRole == .expandedExploration)
        #expect(coordinator.reflow.transientControlRole == .roadDiscovery)
    }

    @Test("Dashboard battery interaction reuses the shared primary-readout state")
    func batteryModeUsesExistingState() {
        var coordinator = HorizonPresentationCoordinator(presentationContextID: contextID)

        #expect(coordinator.batteryPrimaryReadoutState.mode == .percentage)
        #expect(coordinator.toggleBatteryPrimaryReadout() == .estimatedRange)
        #expect(coordinator.batteryPrimaryReadoutState.mode == .estimatedRange)
        #expect(coordinator.toggleBatteryPrimaryReadout() == .percentage)
    }

    @Test("Unavailable metrics retain a reason and never become numeric zero")
    func unavailableMetricNeverMintsValue() throws {
        let metric = HorizonMetricPresentation<Double>.unavailable(reason: .noEvidence)

        #expect(metric.authoritativeValue == nil)
        #expect(metric.authority == nil)
        #expect(metric.unavailableReason == .noEvidence)

        let encoded = try JSONEncoder().encode(metric)
        let decoded = try JSONDecoder().decode(
            HorizonMetricPresentation<Double>.self,
            from: encoded
        )
        #expect(decoded == metric)
        #expect(decoded.authoritativeValue == nil)
    }

    @Test("A newer navigation request fences an older provider result")
    func staleNavigationUpdateIsRejected() throws {
        var coordinator = HorizonPresentationCoordinator(
            presentationContextID: contextID,
            initialMode: .navigation
        )
        let older = try coordinator.beginOverlayRequest(for: .navigation)
        let current = try coordinator.beginOverlayRequest(for: .navigation)

        let staleResult = coordinator.applyNavigationUpdate(
            HorizonNavigationOverlayUpdate(
                request: older,
                presentation: .authoritative(navigationSnapshot(routeID: "route-older"))
            )
        )
        #expect(staleResult == .rejectedStale)
        #expect(coordinator.navigationOverlay == nil)

        let acceptedResult = coordinator.applyNavigationUpdate(
            HorizonNavigationOverlayUpdate(
                request: current,
                presentation: .authoritative(navigationSnapshot(routeID: "route-current"))
            )
        )
        #expect(acceptedResult == .applied)
        #expect(
            coordinator.navigationOverlay
                == .authoritative(navigationSnapshot(routeID: "route-current"))
        )

        // A replay cannot overwrite the accepted snapshot.
        #expect(
            coordinator.applyNavigationUpdate(
                HorizonNavigationOverlayUpdate(
                    request: current,
                    presentation: .unavailable(.offline)
                )
            ) == .rejectedStale
        )
        #expect(
            coordinator.navigationOverlay
                == .authoritative(navigationSnapshot(routeID: "route-current"))
        )
    }

    @Test("Changing modes invalidates in-flight overlay work")
    func modeChangeFencesInFlightUpdate() throws {
        var coordinator = HorizonPresentationCoordinator(
            presentationContextID: contextID,
            initialMode: .navigation
        )
        let request = try coordinator.beginOverlayRequest(for: .navigation)
        _ = try coordinator.selectMode(.drive)
        _ = try coordinator.selectMode(.navigation)

        let result = coordinator.applyNavigationUpdate(
            HorizonNavigationOverlayUpdate(
                request: request,
                presentation: .authoritative(navigationSnapshot(routeID: "stale-route"))
            )
        )

        #expect(result == .rejectedStale)
        #expect(coordinator.navigationOverlay == nil)
    }

    @Test("Today, current ride, odometer, and city coverage remain exact distinct facts")
    func lowerRailFactsDoNotCollapseMeanings() throws {
        let rideID = UUID(uuidString: "4C67BA26-C5CB-47A3-B5F4-2B638E765C28")!
        let facts = HorizonLowerRailFacts(
            automaticRecording: .recording(rideSessionID: rideID),
            today: HorizonTodayFacts(
                localDay: try localDay(),
                distanceMeters: .authoritative(value: 5_149.9, authority: .acceptedRideLedger),
                durationSeconds: .authoritative(value: 2_400, authority: .acceptedRideLedger),
                containsRecoveredRideEvidence: true
            ),
            currentRide: .current(
                rideSessionID: rideID,
                distanceMeters: .authoritative(value: 1_207.0, authority: .acceptedRideLedger),
                durationSeconds: .authoritative(value: 1_122, authority: .acceptedRideLedger)
            ),
            odometerMeters: .authoritative(value: 206_639.8, authority: .persistedVehicleRecord),
            cityCoverage: HorizonCityCoverageFacts(
                evidenceState: .verified,
                progressFraction: .authoritative(value: 0.142, authority: .verifiedRoadCoverage),
                verifiedCoveredLengthMeters: .authoritative(
                    value: 12_536.8,
                    authority: .verifiedRoadCoverage
                ),
                eligibleLengthMeters: .authoritative(
                    value: 87_855.2,
                    authority: .verifiedRoadCoverage
                ),
                remainingEligibleLengthMeters: .authoritative(
                    value: 75_318.4,
                    authority: .verifiedRoadCoverage
                )
            )
        )

        #expect(facts.today.distanceMeters.authoritativeValue == 5_149.9)
        guard case let .current(_, currentDistance, currentDuration) = facts.currentRide else {
            Issue.record("Expected a distinct current-ride fact")
            return
        }
        #expect(currentDistance.authoritativeValue == 1_207.0)
        #expect(currentDuration.authoritativeValue == 1_122)
        #expect(facts.odometerMeters.authoritativeValue == 206_639.8)
        #expect(facts.cityCoverage.progressFraction.authoritativeValue == 0.142)
        #expect(facts.cityCoverage.remainingEligibleLengthMeters.authoritativeValue == 75_318.4)
        #expect(facts.today.distanceMeters != currentDistance)

        let encoded = try JSONEncoder().encode(facts)
        let decoded = try JSONDecoder().decode(HorizonLowerRailFacts.self, from: encoded)
        #expect(decoded == facts)
    }

    @Test("Visible exploration roles and discovery credit preserve ledger identities")
    func explorationOverlayPreservesAcceptedEvidence() throws {
        let dataset = try RoadDatasetKey(
            providerID: "provider",
            regionID: "city",
            graphVersion: "2026-08"
        )
        let unexploredID = try RoadSegmentID(datasetKey: dataset, canonicalID: "road-unexplored")
        let historicalID = try RoadSegmentID(datasetKey: dataset, canonicalID: "road-history")
        let discoveryID = try RoadSegmentID(datasetKey: dataset, canonicalID: "road-new")
        let historicalInterval = try RoadCoverageInterval(lowerBound: 0, upperBound: 0.65)
        let discoveredInterval = try RoadCoverageInterval(lowerBound: 0.2, upperBound: 0.8)
        let event = RoadDiscoveryEvent(
            matchRunUUID: UUID(uuidString: "FA1308E8-A46A-4C49-BB4A-8CB1E071FE79")!,
            rideID: UUID(uuidString: "F13BAF6D-40AC-410A-9054-313475DDBE40")!,
            segmentID: discoveryID,
            newlyVerifiedIntervals: [discoveredInterval],
            newlyVerifiedLengthMeters: 482.8
        )

        let snapshot = HorizonExplorationOverlaySnapshot(
            datasetKey: dataset,
            visibleSegments: [
                HorizonVisibleRoadSegmentOverlay(
                    segmentID: unexploredID,
                    role: .eligibleUnexplored,
                    intervals: []
                ),
                HorizonVisibleRoadSegmentOverlay(
                    segmentID: historicalID,
                    role: .acceptedHistoricalCoverage,
                    intervals: [historicalInterval]
                ),
                HorizonVisibleRoadSegmentOverlay(
                    segmentID: discoveryID,
                    role: .currentDiscovery,
                    intervals: event.newlyVerifiedIntervals
                ),
            ],
            cityCoverage: HorizonCityCoverageFacts(
                evidenceState: .partial,
                progressFraction: .authoritative(value: 0.142, authority: .verifiedRoadCoverage),
                verifiedCoveredLengthMeters: .authoritative(value: 12_536.8, authority: .verifiedRoadCoverage),
                eligibleLengthMeters: .authoritative(value: 87_855.2, authority: .verifiedRoadCoverage),
                remainingEligibleLengthMeters: .authoritative(value: 75_318.4, authority: .verifiedRoadCoverage)
            ),
            discoveryNotice: HorizonTransientRoadDiscoveryNotice(
                event: event,
                roadName: .authoritative(value: "Oak Street", authority: .verifiedRoadCoverage),
                issuedAtDate: Date(timeIntervalSince1970: 1_787_040_200)
            )
        )

        #expect(snapshot.visibleSegments.map(\.role) == [
            .eligibleUnexplored,
            .acceptedHistoricalCoverage,
            .currentDiscovery,
        ])
        #expect(snapshot.discoveryNotice?.event.segmentID == discoveryID)
        #expect(snapshot.discoveryNotice?.event.newlyVerifiedLengthMeters == 482.8)
        #expect(snapshot.discoveryNotice?.event.newlyVerifiedIntervals == [discoveredInterval])
    }
}
