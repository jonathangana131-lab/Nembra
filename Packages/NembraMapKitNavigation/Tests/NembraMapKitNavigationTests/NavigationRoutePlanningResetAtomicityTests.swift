import NembraCore
import Testing
@testable import NembraMapKitNavigation

@Suite("Navigation route planning reset atomicity")
@MainActor
struct NavigationRoutePlanningResetAtomicityTests {
    @Test("reset publishes idle before provider cancellation is observed")
    func resetPublishesIdleBeforeProviderCancellation() async throws {
        let operation = ResetObservationOperation()
        let factory = ResetObservationFactory(operation: operation)
        let service = NavigationRoutePlanningService(factory: factory)
        operation.stateAtCancel = { service.state }

        let request = NavigationRoutePlanRequest.appleMapKitCycling(
            source: try NavigationRouteCoordinate(latitude: 45, longitude: -122),
            destination: try NavigationRouteCoordinate(latitude: 45.01, longitude: -122.01)
        )

        let task = Task { @MainActor in
            try await service.request(request)
        }
        await operation.waitUntilSuspended()

        service.reset()

        #expect(operation.cancelCalled)
        #expect(operation.observedStateAtCancel == NavigationRoutePlanningState.idle)
        #expect(service.state == NavigationRoutePlanningState.idle)

        operation.resume(returning: [])
        let returned = try await task.value
        #expect(returned == NavigationRoutePlanningState.idle)
        #expect(service.state == NavigationRoutePlanningState.idle)
    }
}

@MainActor
private final class ResetObservationFactory: NavigationDirectionsOperationFactory {
    private let operation: ResetObservationOperation

    init(operation: ResetObservationOperation) {
        self.operation = operation
    }

    func makeOperation(
        for request: NavigationRoutePlanRequest
    ) throws -> any NavigationDirectionsOperation {
        operation
    }

    func failure(from error: Error) -> NavigationRoutePlanFailure {
        .unknown
    }
}

@MainActor
private final class ResetObservationOperation: NavigationDirectionsOperation {
    var stateAtCancel: (() -> NavigationRoutePlanningState)?
    private(set) var observedStateAtCancel: NavigationRoutePlanningState?
    private(set) var cancelCalled = false

    private var continuation: CheckedContinuation<[NavigationRouteSnapshot], Error>?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func calculate() async throws -> [NavigationRouteSnapshot] {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let ready = waiters
            waiters.removeAll()
            ready.forEach { $0.resume() }
        }
    }

    func cancel() {
        cancelCalled = true
        observedStateAtCancel = stateAtCancel?()
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