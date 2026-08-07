import Foundation
import NembraCore
import Testing
@testable import NembraMapKitNavigation

@Suite("Navigation experience coordinator")
@MainActor
struct NavigationExperienceCoordinatorTests {
    private enum TestError: Error { case provider }

    private func coordinate(_ latitude: Double, _ longitude: Double) throws -> NavigationRouteCoordinate {
        try NavigationRouteCoordinate(latitude: latitude, longitude: longitude)
    }

    private func request(offset: Double = 0.01) throws -> NavigationRoutePlanRequest {
        .appleMapKitCycling(
            source: try coordinate(45, -122),
            destination: try coordinate(45 + offset, -122.01)
        )
    }

    private func route(name: String, distance: Double = 100) throws -> NavigationRouteSnapshot {
        let a = try coordinate(45, -122)
        let b = try coordinate(45.001, -122)
        let step = try NavigationRouteStepSnapshot(
            geometry: [a, b],
            instructions: name,
            notice: nil,
            distanceMeters: distance,
            transportMode: .cycling
        )
        return try NavigationRouteSnapshot(
            provenance: .appleMapKitCycling(),
            name: name,
            geometry: [a, b],
            steps: [step],
            distanceMeters: distance,
            expectedTravelTimeSeconds: 30,
            hasHighways: false,
            hasTolls: false,
            advisoryNotices: []
        )
    }

    private func location(uptime: UInt64 = 10) throws -> QualityScreenedRideLocation {
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

    private func coordinator(
        operations: [ExperienceFakeOperation]
    ) throws -> NavigationExperienceCoordinator {
        NavigationExperienceCoordinator(
            factory: ExperienceFakeFactory(operations: operations),
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

    @Test("successful plan exposes provider routes but makes no implicit selection")
    func planRequiresExplicitSelection() async throws {
        let first = try route(name: "First")
        let second = try route(name: "Second")
        let experience = try coordinator(operations: [.init(.routes([first, second]))])

        let snapshot = try await experience.plan(request())

        #expect(snapshot.routeSelection?.routes == [first, second])
        #expect(snapshot.routeSelection?.selectedIndex == nil)
        #expect(snapshot.selectedRoute == nil)
        #expect(snapshot.guidanceState == .idle)
    }

    @Test("explicit route selection starts guidance for the exact selected route")
    func explicitSelectionStartsGuidance() async throws {
        let first = try route(name: "First")
        let second = try route(name: "Second")
        let experience = try coordinator(operations: [.init(.routes([first, second]))])
        _ = try await experience.plan(request())

        let snapshot = try experience.selectRoute(index: 1)

        #expect(snapshot.routeSelection?.selectedIndex == 1)
        #expect(snapshot.selectedRoute == second)
        guard case let .unavailable(_, selected, reason) = snapshot.guidanceState else {
            Issue.record("Expected guidance awaiting evidence")
            return
        }
        #expect(selected == second)
        #expect(reason == .awaitingEvidence)
    }

    @Test("screened location updates active selected guidance")
    func screenedLocationUpdatesGuidance() async throws {
        let selected = try route(name: "Selected")
        let experience = try coordinator(operations: [.init(.routes([selected]))])
        _ = try await experience.plan(request())
        _ = try experience.selectRoute(index: 0)

        let updateValue = try experience.process(location: location())
        let update = try #require(updateValue)

        guard case let .active(_, route, progress) = update.guidanceState else {
            Issue.record("Expected active guidance")
            return
        }
        #expect(route == selected)
        #expect(progress.currentStep.instructions == "Selected")
    }

    @Test("new route plan preserves existing selected navigation until replacement is explicit")
    func planningPreservesActiveRoute() async throws {
        let active = try route(name: "Active")
        let replacement = try route(name: "Replacement")
        let experience = try coordinator(operations: [
            .init(.routes([active])),
            .init(.routes([replacement])),
        ])
        _ = try await experience.plan(request())
        _ = try experience.selectRoute(index: 0)

        let replanned = try await experience.plan(request(offset: 0.02))

        #expect(replanned.selectedRoute == active)
        #expect(replanned.routeSelection?.routes == [replacement])
        #expect(replanned.routeSelection?.selectedIndex == nil)
    }

    @Test("failed replanning keeps current navigation but exposes no stale alternatives")
    func failedReplanPreservesRoute() async throws {
        let active = try route(name: "Active")
        let experience = try coordinator(operations: [
            .init(.routes([active])),
            .init(.error(TestError.provider)),
        ])
        _ = try await experience.plan(request())
        _ = try experience.selectRoute(index: 0)

        let failed = try await experience.plan(request(offset: 0.02))

        #expect(failed.selectedRoute == active)
        #expect(failed.routeSelection == nil)
        guard case let .failed(_, _, reason) = failed.planningState else {
            Issue.record("Expected failed planning state")
            return
        }
        #expect(reason == .serverFailure)
    }

    @Test("late superseded plan return cannot reset a newer explicitly selected route")
    func stalePlanReturnCannotResetNewSelection() async throws {
        let oldOperation = ExperienceFakeOperation(.suspended)
        let newer = try route(name: "Newer")
        let experience = try coordinator(operations: [
            oldOperation,
            .init(.routes([newer])),
        ])

        let oldTask = Task { @MainActor in
            try await experience.plan(request(offset: 0.01))
        }
        await oldOperation.waitUntilSuspended()

        _ = try await experience.plan(request(offset: 0.02))
        _ = try experience.selectRoute(index: 0)
        let selectedBeforeLateReturn = experience.snapshot

        oldOperation.resume(returning: [try route(name: "Old late")])
        _ = try await oldTask.value

        #expect(experience.snapshot == selectedBeforeLateReturn)
        #expect(experience.snapshot.selectedRoute == newer)
        #expect(experience.snapshot.routeSelection?.selectedIndex == 0)
    }

    @Test("cancel planning preserves current navigation and rejects late result")
    func cancelPlanningPreservesNavigation() async throws {
        let active = try route(name: "Active")
        let pending = ExperienceFakeOperation(.suspended)
        let experience = try coordinator(operations: [
            .init(.routes([active])),
            pending,
        ])
        _ = try await experience.plan(request())
        _ = try experience.selectRoute(index: 0)

        let task = Task { @MainActor in
            try await experience.plan(request(offset: 0.02))
        }
        await pending.waitUntilSuspended()
        #expect(try experience.cancelPlanning())
        #expect(pending.cancelCalled)
        let afterCancel = experience.snapshot
        #expect(afterCancel.selectedRoute == active)
        #expect(afterCancel.routeSelection == nil)

        pending.resume(returning: [try route(name: "Late")])
        _ = try await task.value
        #expect(experience.snapshot.selectedRoute == active)
        #expect(experience.snapshot.routeSelection == nil)
    }

    @Test("route selection without current alternatives fails closed")
    func selectionWithoutOptionsFails() throws {
        let experience = try coordinator(operations: [])
        #expect(throws: NavigationExperienceError.noRouteOptions) {
            try experience.selectRoute(index: 0)
        }
    }

    @Test("clearing selected route preserves alternatives but removes their selected index")
    func clearSelectedRoutePreservesOptions() async throws {
        let first = try route(name: "First")
        let second = try route(name: "Second")
        let experience = try coordinator(operations: [.init(.routes([first, second]))])
        _ = try await experience.plan(request())
        _ = try experience.selectRoute(index: 1)

        experience.clearSelectedRoute()

        #expect(experience.snapshot.selectedRoute == nil)
        #expect(experience.snapshot.routeSelection?.routes == [first, second])
        #expect(experience.snapshot.routeSelection?.selectedIndex == nil)
        #expect(experience.snapshot.guidanceState == .idle)
    }

    @Test("reset clears planning alternatives and active navigation")
    func resetClearsEverything() async throws {
        let selected = try route(name: "Selected")
        let experience = try coordinator(operations: [.init(.routes([selected]))])
        _ = try await experience.plan(request())
        _ = try experience.selectRoute(index: 0)

        try experience.reset()

        #expect(experience.snapshot.planningState == .idle)
        #expect(experience.snapshot.routeSelection == nil)
        #expect(experience.snapshot.selectedRoute == nil)
        #expect(experience.snapshot.guidanceState == .idle)
    }
}

@MainActor
private final class ExperienceFakeFactory: NavigationDirectionsOperationFactory {
    private var operations: [ExperienceFakeOperation]

    init(operations: [ExperienceFakeOperation]) {
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
private final class ExperienceFakeOperation: NavigationDirectionsOperation {
    enum Behavior {
        case routes([NavigationRouteSnapshot])
        case error(Error)
        case suspended
    }

    private let behavior: Behavior
    private var continuation: CheckedContinuation<[NavigationRouteSnapshot], Error>?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var cancelCalled = false

    init(_ behavior: Behavior) {
        self.behavior = behavior
    }

    func calculate() async throws -> [NavigationRouteSnapshot] {
        switch behavior {
        case let .routes(routes):
            return routes
        case let .error(error):
            throw error
        case .suspended:
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let ready = waiters
                waiters.removeAll()
                ready.forEach { $0.resume() }
            }
        }
    }

    func cancel() {
        cancelCalled = true
    }

    func waitUntilSuspended() async {
        if continuation != nil { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func resume(returning routes: [NavigationRouteSnapshot]) {
        continuation?.resume(returning: routes)
        continuation = nil
    }
}
