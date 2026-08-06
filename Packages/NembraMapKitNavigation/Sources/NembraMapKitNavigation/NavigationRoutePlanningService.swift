import NembraCore

/// Composes NembraCore's deterministic planning state with provider operation
/// lifetime. Superseding a request invalidates the old planning token first,
/// then cancels the matching provider operation. Late provider completions are
/// harmless because both layers independently reject stale identity.
@MainActor
public final class NavigationRoutePlanningService {
    private var planner = NavigationRoutePlanningCoordinator()
    private let operations: NavigationDirectionsOperationCoordinator

    public var state: NavigationRoutePlanningState {
        planner.state
    }

    public init(factory: any NavigationDirectionsOperationFactory) {
        operations = NavigationDirectionsOperationCoordinator(factory: factory)
    }

    @discardableResult
    public func request(
        _ request: NavigationRoutePlanRequest
    ) async throws -> NavigationRoutePlanningState {
        let start = try planner.begin(request)

        if let supersededToken = start.supersededToken {
            _ = operations.cancel(token: supersededToken)
        }

        let result = await operations.calculate(
            request: request,
            token: start.token
        )

        switch result {
        case let .routes(routes):
            _ = planner.complete(token: start.token, routes: routes)
        case let .failure(reason):
            _ = planner.fail(token: start.token, reason: reason)
        }

        return planner.state
    }

    /// Invalidates planner state before asking the provider layer to cancel.
    /// If provider completion races, neither the operation coordinator nor the
    /// planning coordinator can publish it as current afterward.
    @discardableResult
    public func cancelCurrent() -> Bool {
        guard let token = planner.cancelCurrent() else {
            return false
        }
        _ = operations.cancel(token: token)
        return true
    }

    /// Cancels any current request, then clears product-facing planning state.
    /// Request-sequence identity remains monotonic inside NembraCore.
    public func reset() {
        if let token = planner.cancelCurrent() {
            _ = operations.cancel(token: token)
        }
        planner.reset()
    }
}
