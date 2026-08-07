import NembraCore
import Testing
@testable import NembraMapKitNavigation

@Suite("Navigation route planning service")
@MainActor
struct NavigationRoutePlanningServiceTests {
    private enum TestError: Error { case provider }

    private func coordinate(_ latitude: Double, _ longitude: Double) throws -> NavigationRouteCoordinate {
        try NavigationRouteCoordinate(latitude: latitude, longitude: longitude)
    }

    private func request(destinationOffset: Double = 0.01) throws -> NavigationRoutePlanRequest {
        .appleMapKitCycling(
            source: try coordinate(45, -122),
            destination: try coordinate(45 + destinationOffset, -122.01)
        )
    }

    private func route(name: String = "Route") throws -> NavigationRouteSnapshot {
        let a = try coordinate(45, -122)
        let b = try coordinate(45.01, -122.01)
        let step = try NavigationRouteStepSnapshot(
            geometry: [a, b], instructions: "Continue", notice: nil,
            distanceMeters: 100, transportMode: .cycling
        )
        return try NavigationRouteSnapshot(
            provenance: .appleMapKitCycling(), name: name, geometry: [a, b], steps: [step],
            distanceMeters: 100, expectedTravelTimeSeconds: 30,
            hasHighways: false, hasTolls: false, advisoryNotices: []
        )
    }

    @Test("successful provider result publishes available planning state")
    func successPublishes() async throws {
        let expected = try route()
        let service = NavigationRoutePlanningService(
            factory: ServiceFakeFactory(operations: [ServiceFakeOperation(.routes([expected]))])
        )
        let request = try request()

        let returned = try await service.request(request)

        guard case let .available(_, publishedRequest, routes) = returned else {
            Issue.record("Expected available state")
            return
        }
        #expect(publishedRequest == request)
        #expect(routes == [expected])
        #expect(service.state == returned)
    }

    @Test("provider failure publishes stable failed planning state")
    func failurePublishes() async throws {
        let service = NavigationRoutePlanningService(
            factory: ServiceFakeFactory(operations: [ServiceFakeOperation(.error(TestError.provider))])
        )
        let request = try request()
        let returned = try await service.request(request)

        guard case let .failed(_, publishedRequest, reason) = returned else {
            Issue.record("Expected failed state")
            return
        }
        #expect(publishedRequest == request)
        #expect(reason == .serverFailure)
    }

    @Test("empty provider result becomes invalid provider response")
    func emptyFailsClosed() async throws {
        let service = NavigationRoutePlanningService(
            factory: ServiceFakeFactory(operations: [ServiceFakeOperation(.routes([]))])
        )
        let returned = try await service.request(request())
        guard case let .failed(_, _, reason) = returned else {
            Issue.record("Expected failed state")
            return
        }
        #expect(reason == .invalidProviderResponse)
    }

    @Test("superseding request cancels prior provider operation and old completion cannot overwrite new state")
    func supersessionIsAtomic() async throws {
        let firstOperation = ServiceFakeOperation(.suspended)
        let secondRoute = try route(name: "Second")
        let secondOperation = ServiceFakeOperation(.routes([secondRoute]))
        let service = NavigationRoutePlanningService(
            factory: ServiceFakeFactory(operations: [firstOperation, secondOperation])
        )
        let firstRequest = try request(destinationOffset: 0.01)
        let secondRequest = try request(destinationOffset: 0.02)

        let firstTask = Task { @MainActor in try await service.request(firstRequest) }
        await firstOperation.waitUntilSuspended()
        guard case .requesting = service.state else {
            Issue.record("Expected first request to be active")
            return
        }

        let secondState = try await service.request(secondRequest)
        #expect(firstOperation.cancelCalled)
        guard case let .available(_, publishedRequest, routes) = secondState else {
            Issue.record("Expected second request available")
            return
        }
        #expect(publishedRequest == secondRequest)
        #expect(routes == [secondRoute])

        firstOperation.resume(returning: [try route(name: "Late first")])
        let firstReturned = try await firstTask.value
        #expect(firstReturned == service.state)
        #expect(service.state == secondState)
    }

    @Test("explicit cancel publishes cancelled before late provider success")
    func cancelWinsLateSuccess() async throws {
        let operation = ServiceFakeOperation(.suspended)
        let service = NavigationRoutePlanningService(
            factory: ServiceFakeFactory(operations: [operation])
        )
        let request = try request()
        let task = Task { @MainActor in try await service.request(request) }
        await operation.waitUntilSuspended()

        #expect(service.cancelCurrent())
        #expect(operation.cancelCalled)
        guard case let .failed(_, publishedRequest, reason) = service.state else {
            Issue.record("Expected cancelled failed state")
            return
        }
        #expect(publishedRequest == request)
        #expect(reason == .cancelled)

        operation.resume(returning: [try route()])
        let returned = try await task.value
        #expect(returned == service.state)
    }

    @Test("cancel current is false once request already completed")
    func cancelAfterCompletionIsNoop() async throws {
        let service = NavigationRoutePlanningService(
            factory: ServiceFakeFactory(operations: [ServiceFakeOperation(.routes([try route()]))])
        )
        _ = try await service.request(request())
        #expect(!service.cancelCurrent())
    }

    @Test("reset cancels active provider and returns product planning state to idle")
    func resetCancelsActive() async throws {
        let operation = ServiceFakeOperation(.suspended)
        let service = NavigationRoutePlanningService(
            factory: ServiceFakeFactory(operations: [operation])
        )
        let task = Task { @MainActor in try await service.request(request()) }
        await operation.waitUntilSuspended()

        service.reset()
        #expect(operation.cancelCalled)
        #expect(service.state == .idle)

        operation.resume(returning: [try route()])
        let returned = try await task.value
        #expect(returned == .idle)
        #expect(service.state == .idle)
    }
}

@MainActor
private final class ServiceFakeFactory: NavigationDirectionsOperationFactory {
    private var operations: [ServiceFakeOperation]
    init(operations: [ServiceFakeOperation]) { self.operations = operations }
    func makeOperation(for request: NavigationRoutePlanRequest) throws -> any NavigationDirectionsOperation {
        operations.removeFirst()
    }
    func failure(from error: Error) -> NavigationRoutePlanFailure { .serverFailure }
}

@MainActor
private final class ServiceFakeOperation: NavigationDirectionsOperation {
    enum Behavior { case routes([NavigationRouteSnapshot]); case error(Error); case suspended }
    private let behavior: Behavior
    private var continuation: CheckedContinuation<[NavigationRouteSnapshot], Error>?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var cancelCalled = false

    init(_ behavior: Behavior) { self.behavior = behavior }

    func calculate() async throws -> [NavigationRouteSnapshot] {
        switch behavior {
        case let .routes(routes): return routes
        case let .error(error): throw error
        case .suspended:
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let ready = waiters
                waiters.removeAll()
                ready.forEach { $0.resume() }
            }
        }
    }

    func cancel() { cancelCalled = true }

    func waitUntilSuspended() async {
        if continuation != nil { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func resume(returning routes: [NavigationRouteSnapshot]) {
        continuation?.resume(returning: routes)
        continuation = nil
    }
}
