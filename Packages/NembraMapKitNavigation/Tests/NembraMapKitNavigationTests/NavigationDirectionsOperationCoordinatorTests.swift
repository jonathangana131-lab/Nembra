import NembraCore
import Testing
@testable import NembraMapKitNavigation

@Suite("Navigation directions operation coordinator")
@MainActor
struct NavigationDirectionsOperationCoordinatorTests {
    private enum TestError: Error { case provider; case factory }

    private func coordinate(_ latitude: Double, _ longitude: Double) throws -> NavigationRouteCoordinate {
        try NavigationRouteCoordinate(latitude: latitude, longitude: longitude)
    }

    private func request() throws -> NavigationRoutePlanRequest {
        .appleMapKitCycling(
            source: try coordinate(45, -122),
            destination: try coordinate(45.01, -122.01)
        )
    }

    private func route() throws -> NavigationRouteSnapshot {
        let a = try coordinate(45, -122)
        let b = try coordinate(45.01, -122.01)
        let step = try NavigationRouteStepSnapshot(
            geometry: [a, b], instructions: "Continue", notice: nil,
            distanceMeters: 100, transportMode: .cycling
        )
        return try NavigationRouteSnapshot(
            provenance: .appleMapKitCycling(), name: "Route", geometry: [a, b], steps: [step],
            distanceMeters: 100, expectedTravelTimeSeconds: 30,
            hasHighways: false, hasTolls: false, advisoryNotices: []
        )
    }

    private func token() throws -> NavigationRouteRequestToken {
        var planner = NavigationRoutePlanningCoordinator()
        return try planner.begin(request()).token
    }

    @Test("successful provider routes are returned")
    func successfulRoutes() async throws {
        let expected = try route()
        let operation = FakeOperation(.routes([expected]))
        let factory = FakeFactory(operations: [operation])
        let coordinator = NavigationDirectionsOperationCoordinator(factory: factory)
        let result = await coordinator.calculate(request: try request(), token: try token())
        #expect(result == .routes([expected]))
    }

    @Test("empty provider result fails closed")
    func emptyRoutesFailClosed() async throws {
        let operation = FakeOperation(.routes([]))
        let coordinator = NavigationDirectionsOperationCoordinator(factory: FakeFactory(operations: [operation]))
        let result = await coordinator.calculate(request: try request(), token: try token())
        #expect(result == .failure(.invalidProviderResponse))
    }

    @Test("provider error uses injected stable failure mapping")
    func providerErrorMapped() async throws {
        let operation = FakeOperation(.error(TestError.provider))
        let coordinator = NavigationDirectionsOperationCoordinator(factory: FakeFactory(operations: [operation]))
        let result = await coordinator.calculate(request: try request(), token: try token())
        #expect(result == .failure(.serverFailure))
    }

    @Test("factory error is mapped before an operation becomes active")
    func factoryErrorMapped() async throws {
        let factory = FakeFactory(operations: [], factoryError: TestError.factory)
        let coordinator = NavigationDirectionsOperationCoordinator(factory: factory)
        let request = try request()
        let token = try token()
        let result = await coordinator.calculate(request: request, token: token)
        #expect(result == .failure(.serverFailure))
        #expect(!coordinator.isActive(token: token))
    }

    @Test("cancel removes operation before transport cancel callback can race")
    func cancellationWinsRace() async throws {
        let operation = FakeOperation(.suspended)
        let coordinator = NavigationDirectionsOperationCoordinator(factory: FakeFactory(operations: [operation]))
        let request = try request()
        let token = try token()

        let task = Task { @MainActor in
            await coordinator.calculate(request: request, token: token)
        }
        await operation.waitUntilSuspended()
        #expect(coordinator.isActive(token: token))
        #expect(coordinator.cancel(token: token))
        #expect(operation.cancelCalled)
        #expect(!coordinator.isActive(token: token))

        operation.resume(returning: [try route()])
        let result = await task.value
        #expect(result == .failure(.cancelled))
    }

    @Test("late provider error after cancellation remains cancelled")
    func lateErrorAfterCancellation() async throws {
        let operation = FakeOperation(.suspended)
        let coordinator = NavigationDirectionsOperationCoordinator(factory: FakeFactory(operations: [operation]))
        let request = try request()
        let token = try token()
        let task = Task { @MainActor in await coordinator.calculate(request: request, token: token) }
        await operation.waitUntilSuspended()
        _ = coordinator.cancel(token: token)
        operation.resume(throwing: TestError.provider)
        #expect(await task.value == .failure(.cancelled))
    }

    @Test("independent request tokens may run concurrently")
    func independentTokens() async throws {
        var planner = NavigationRoutePlanningCoordinator()
        let request = try request()
        let first = try planner.begin(request).token
        planner.reset()
        let second = try planner.begin(request).token
        let op1 = FakeOperation(.suspended)
        let op2 = FakeOperation(.suspended)
        let coordinator = NavigationDirectionsOperationCoordinator(factory: FakeFactory(operations: [op1, op2]))

        let task1 = Task { @MainActor in await coordinator.calculate(request: request, token: first) }
        await op1.waitUntilSuspended()
        let task2 = Task { @MainActor in await coordinator.calculate(request: request, token: second) }
        await op2.waitUntilSuspended()
        #expect(coordinator.isActive(token: first))
        #expect(coordinator.isActive(token: second))

        let expected = try route()
        op2.resume(returning: [expected])
        op1.resume(returning: [expected])
        #expect(await task1.value == .routes([expected]))
        #expect(await task2.value == .routes([expected]))
    }

    @Test("duplicate use of one active token fails without replacing original operation")
    func duplicateTokenRejected() async throws {
        let firstOperation = FakeOperation(.suspended)
        let secondOperation = FakeOperation(.routes([try route()]))
        let factory = FakeFactory(operations: [firstOperation, secondOperation])
        let coordinator = NavigationDirectionsOperationCoordinator(factory: factory)
        let request = try request()
        let token = try token()
        let firstTask = Task { @MainActor in await coordinator.calculate(request: request, token: token) }
        await firstOperation.waitUntilSuspended()

        let duplicate = await coordinator.calculate(request: request, token: token)
        #expect(duplicate == .failure(.unknown))
        #expect(factory.makeCount == 1)
        #expect(coordinator.isActive(token: token))

        firstOperation.resume(returning: [try route()])
        _ = await firstTask.value
    }

    @Test("cancel all invalidates every in-flight operation")
    func cancelAll() async throws {
        var planner = NavigationRoutePlanningCoordinator()
        let request = try request()
        let first = try planner.begin(request).token
        planner.reset()
        let second = try planner.begin(request).token
        let op1 = FakeOperation(.suspended)
        let op2 = FakeOperation(.suspended)
        let coordinator = NavigationDirectionsOperationCoordinator(factory: FakeFactory(operations: [op1, op2]))
        let task1 = Task { @MainActor in await coordinator.calculate(request: request, token: first) }
        await op1.waitUntilSuspended()
        let task2 = Task { @MainActor in await coordinator.calculate(request: request, token: second) }
        await op2.waitUntilSuspended()

        coordinator.cancelAll()
        #expect(op1.cancelCalled)
        #expect(op2.cancelCalled)
        op1.resume(returning: [try route()])
        op2.resume(returning: [try route()])
        #expect(await task1.value == .failure(.cancelled))
        #expect(await task2.value == .failure(.cancelled))
    }
}

@MainActor
private final class FakeFactory: NavigationDirectionsOperationFactory {
    private var operations: [FakeOperation]
    private let factoryError: Error?
    private(set) var makeCount = 0

    init(operations: [FakeOperation], factoryError: Error? = nil) {
        self.operations = operations
        self.factoryError = factoryError
    }

    func makeOperation(for request: NavigationRoutePlanRequest) throws -> any NavigationDirectionsOperation {
        makeCount += 1
        if let factoryError { throw factoryError }
        return operations.removeFirst()
    }

    func failure(from error: Error) -> NavigationRoutePlanFailure { .serverFailure }
}

@MainActor
private final class FakeOperation: NavigationDirectionsOperation {
    enum Behavior { case routes([NavigationRouteSnapshot]); case error(Error); case suspended }
    private let behavior: Behavior
    private var continuation: CheckedContinuation<[NavigationRouteSnapshot], Error>?
    private var suspensionWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var cancelCalled = false

    init(_ behavior: Behavior) { self.behavior = behavior }

    func calculate() async throws -> [NavigationRouteSnapshot] {
        switch behavior {
        case let .routes(routes): return routes
        case let .error(error): throw error
        case .suspended:
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let waiters = suspensionWaiters
                suspensionWaiters.removeAll()
                waiters.forEach { $0.resume() }
            }
        }
    }

    func cancel() { cancelCalled = true }

    func waitUntilSuspended() async {
        if continuation != nil { return }
        await withCheckedContinuation { suspensionWaiters.append($0) }
    }

    func resume(returning routes: [NavigationRouteSnapshot]) {
        continuation?.resume(returning: routes)
        continuation = nil
    }

    func resume(throwing error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
