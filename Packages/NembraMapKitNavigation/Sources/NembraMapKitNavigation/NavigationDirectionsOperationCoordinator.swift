import NembraCore

public enum NavigationDirectionsOperationResult: Equatable, Sendable {
    case routes([NavigationRouteSnapshot])
    case failure(NavigationRoutePlanFailure)
}

@MainActor
public protocol NavigationDirectionsOperation: AnyObject {
    func calculate() async throws -> [NavigationRouteSnapshot]
    func cancel()
}

@MainActor
public protocol NavigationDirectionsOperationFactory: AnyObject {
    func makeOperation(
        for request: NavigationRoutePlanRequest
    ) throws -> any NavigationDirectionsOperation

    func failure(from error: Error) -> NavigationRoutePlanFailure
}

/// Runs provider operations under Nembra's already-generated request token.
/// Transport cancellation is not trusted as the correctness mechanism: once a
/// token is cancelled/removed here, its late completion can only become
/// `.cancelled`, never a route result.
@MainActor
public final class NavigationDirectionsOperationCoordinator {
    private let factory: any NavigationDirectionsOperationFactory
    private var activeOperations: [UInt64: any NavigationDirectionsOperation] = [:]

    public init(factory: any NavigationDirectionsOperationFactory) {
        self.factory = factory
    }

    public func calculate(
        request: NavigationRoutePlanRequest,
        token: NavigationRouteRequestToken
    ) async -> NavigationDirectionsOperationResult {
        guard activeOperations[token.sequence] == nil else {
            return .failure(.unknown)
        }

        let operation: any NavigationDirectionsOperation
        do {
            operation = try factory.makeOperation(for: request)
        } catch {
            return .failure(factory.failure(from: error))
        }

        activeOperations[token.sequence] = operation

        do {
            let routes = try await operation.calculate()
            guard removeIfCurrent(operation, for: token.sequence) else {
                return .failure(.cancelled)
            }
            guard !routes.isEmpty else {
                return .failure(.invalidProviderResponse)
            }
            return .routes(routes)
        } catch {
            guard removeIfCurrent(operation, for: token.sequence) else {
                return .failure(.cancelled)
            }
            return .failure(factory.failure(from: error))
        }
    }

    @discardableResult
    public func cancel(token: NavigationRouteRequestToken) -> Bool {
        guard let operation = activeOperations.removeValue(forKey: token.sequence) else {
            return false
        }
        operation.cancel()
        return true
    }

    public func cancelAll() {
        let operations = Array(activeOperations.values)
        activeOperations.removeAll(keepingCapacity: true)
        for operation in operations {
            operation.cancel()
        }
    }

    public func isActive(token: NavigationRouteRequestToken) -> Bool {
        activeOperations[token.sequence] != nil
    }

    private func removeIfCurrent(
        _ operation: any NavigationDirectionsOperation,
        for sequence: UInt64
    ) -> Bool {
        guard let current = activeOperations[sequence],
              (current as AnyObject) === (operation as AnyObject) else {
            return false
        }
        activeOperations.removeValue(forKey: sequence)
        return true
    }
}
