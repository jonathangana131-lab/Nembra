import Foundation
import NembraCore
import Testing
@testable import NembraMapKitNavigation

@Suite("Navigation experience selection receipt fence")
@MainActor
struct NavigationExperienceSelectionReceiptFenceTests {
    private func coordinate(_ latitude: Double, _ longitude: Double) throws -> NavigationRouteCoordinate {
        try NavigationRouteCoordinate(latitude: latitude, longitude: longitude)
    }

    private func request(offset: Double = 0.01) throws -> NavigationRoutePlanRequest {
        .appleMapKitCycling(
            source: try coordinate(45, -122),
            destination: try coordinate(45 + offset, -122.01)
        )
    }

    private func route(name: String) throws -> NavigationRouteSnapshot {
        let a = try coordinate(45, -122)
        let b = try coordinate(45.001, -122)
        let step = try NavigationRouteStepSnapshot(
            geometry: [a, b],
            instructions: name,
            notice: nil,
            distanceMeters: 100,
            transportMode: .cycling
        )
        return try NavigationRouteSnapshot(
            provenance: .appleMapKitCycling(),
            name: name,
            geometry: [a, b],
            steps: [step],
            distanceMeters: 100,
            expectedTravelTimeSeconds: 30,
            hasHighways: false,
            hasTolls: false,
            advisoryNotices: []
        )
    }

    private func location(uptime: UInt64) throws -> QualityScreenedRideLocation {
        let date = Date(timeIntervalSinceReferenceDate: 1_000)
        let sample = try RideLocationSample(
            latitude: 45.0005,
            longitude: -122,
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

    private func coordinator(operations: [ReceiptFenceOperation]) throws -> NavigationExperienceCoordinator {
        NavigationExperienceCoordinator(
            factory: ReceiptFenceFactory(operations: operations),
            geometryPolicy: try NavigationRouteGeometryMatchingPolicy(
                maximumRouteDistanceMeters: 40,
                minimumStepAmbiguitySeparationMeters: 4
            ),
            reroutePolicy: try NavigationReroutePolicy(
                minimumDeviationDistanceMeters: 20,
                requiredConsecutiveAcceptedSamples: 2,
                rerouteCooldownNanoseconds: 100
            )
        )
    }

    private func selectionID(from snapshot: NavigationExperienceSnapshot) throws -> NavigationRouteSelectionID {
        let presentation = NavigationPresentationProjector.snapshot(from: snapshot)
        return try #require(presentation.routeOptions.first?.selectionID)
    }

    @Test("fenced selection rejects a queued pre-selection location receipt")
    func fencedSelectionRejectsQueuedReceipt() async throws {
        let selected = try route(name: "Selected")
        let experience = try coordinator(operations: [.init(routes: [selected])])
        let planned = try await experience.plan(request())
        let selectionID = try selectionID(from: planned)

        _ = try experience.selectRoute(
            selectionID,
            receiptFence: NavigationRouteSelectionReceiptFence(selectedAtUptimeNanoseconds: 100)
        )
        let awaiting = experience.snapshot.guidanceState

        #expect(throws: NavigationSessionCoordinatorError.locationReceivedAtOrBeforeSelectionFence) {
            try experience.process(location: location(uptime: 90))
        }
        #expect(experience.snapshot.guidanceState == awaiting)

        let update = try #require(experience.process(location: location(uptime: 101)))
        guard case .active = update.guidanceState else {
            Issue.record("Expected a post-selection receipt to activate guidance")
            return
        }
    }

    @Test("regressing selection fence fails transactionally without replacing active route")
    func regressingFenceDoesNotReplaceActiveRoute() async throws {
        let first = try route(name: "First")
        let replacement = try route(name: "Replacement")
        let experience = try coordinator(operations: [
            .init(routes: [first]),
            .init(routes: [replacement]),
        ])

        let firstPlan = try await experience.plan(request())
        _ = try experience.selectRoute(
            selectionID(from: firstPlan),
            receiptFence: NavigationRouteSelectionReceiptFence(selectedAtUptimeNanoseconds: 100)
        )

        let replacementPlan = try await experience.plan(request(offset: 0.02))
        let replacementID = try selectionID(from: replacementPlan)
        let beforeRejectedSelection = experience.snapshot

        #expect(throws: NavigationSessionCoordinatorError.nonMonotonicSelectionFence) {
            try experience.selectRoute(
                replacementID,
                receiptFence: NavigationRouteSelectionReceiptFence(selectedAtUptimeNanoseconds: 99)
            )
        }
        #expect(experience.snapshot == beforeRejectedSelection)
        #expect(experience.snapshot.selectedRoute == first)
        #expect(experience.snapshot.routeSelection?.selectedIndex == nil)

        let accepted = try experience.selectRoute(
            replacementID,
            receiptFence: NavigationRouteSelectionReceiptFence(selectedAtUptimeNanoseconds: 101)
        )
        #expect(accepted.selectedRoute == replacement)
        #expect(accepted.routeSelection?.selectedIndex == 0)
    }
}

@MainActor
private final class ReceiptFenceFactory: NavigationDirectionsOperationFactory {
    private var operations: [ReceiptFenceOperation]

    init(operations: [ReceiptFenceOperation]) {
        self.operations = operations
    }

    func makeOperation(for request: NavigationRoutePlanRequest) throws -> any NavigationDirectionsOperation {
        operations.removeFirst()
    }

    func failure(from error: Error) -> NavigationRoutePlanFailure {
        .serverFailure
    }
}

@MainActor
private final class ReceiptFenceOperation: NavigationDirectionsOperation {
    private let routes: [NavigationRouteSnapshot]

    init(routes: [NavigationRouteSnapshot]) {
        self.routes = routes
    }

    func calculate() async throws -> [NavigationRouteSnapshot] {
        routes
    }

    func cancel() {}
}