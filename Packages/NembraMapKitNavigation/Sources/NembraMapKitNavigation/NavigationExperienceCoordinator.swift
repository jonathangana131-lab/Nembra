import NembraCore

public enum NavigationExperienceError: Error, Equatable, Sendable {
    case workflowSequenceExhausted
    case noRouteOptions
    case staleRouteOptions
}

/// Identifies one route option inside the exact provider result generation that
/// produced it. UI must carry this identity back when selecting an alternative;
/// a bare array index is not sufficient because replanning can replace the
/// result array before a delayed tap/callback arrives.
public struct NavigationRouteSelectionID: Equatable, Sendable {
    public let requestToken: NavigationRouteRequestToken
    public let index: Int

    public init(
        requestToken: NavigationRouteRequestToken,
        index: Int
    ) {
        self.requestToken = requestToken
        self.index = index
    }
}

public struct NavigationExperienceSnapshot: Equatable, Sendable {
    public let planningState: NavigationRoutePlanningState
    public let routeSelection: NavigationRouteSelectionState?
    public let selectedRoute: NavigationRouteSnapshot?
    public let guidanceState: NavigationGuidanceProgressState

    public init(
        planningState: NavigationRoutePlanningState,
        routeSelection: NavigationRouteSelectionState?,
        selectedRoute: NavigationRouteSnapshot?,
        guidanceState: NavigationGuidanceProgressState
    ) {
        self.planningState = planningState
        self.routeSelection = routeSelection
        self.selectedRoute = selectedRoute
        self.guidanceState = guidanceState
    }
}

/// App-facing, provider-independent navigation workflow composition.
///
/// Planning, explicit route choice, and active guidance remain separate truth
/// domains. A new route request may run while an already selected route remains
/// active. New provider alternatives never replace the active route until the
/// caller explicitly selects one.
@MainActor
public final class NavigationExperienceCoordinator {
    private let planningService: NavigationRoutePlanningService
    private var session: NavigationSessionCoordinator
    private var routeSelection: NavigationRouteSelectionState?
    private var selectedRoute: NavigationRouteSnapshot?
    private var workflowSequence: UInt64 = 0

    public var snapshot: NavigationExperienceSnapshot {
        NavigationExperienceSnapshot(
            planningState: planningService.state,
            routeSelection: routeSelection,
            selectedRoute: selectedRoute,
            guidanceState: session.guidanceState
        )
    }

    public init(
        factory: any NavigationDirectionsOperationFactory,
        geometryPolicy: NavigationRouteGeometryMatchingPolicy,
        reroutePolicy: NavigationReroutePolicy
    ) {
        planningService = NavigationRoutePlanningService(factory: factory)
        session = NavigationSessionCoordinator(
            geometryPolicy: geometryPolicy,
            reroutePolicy: reroutePolicy
        )
    }

    /// Starts or supersedes route planning without silently replacing a route
    /// that is already selected. Any prior provider alternatives are invalidated
    /// immediately because their indices belong to a different result set.
    @discardableResult
    public func plan(
        _ request: NavigationRoutePlanRequest
    ) async throws -> NavigationExperienceSnapshot {
        let generation = try nextWorkflowGeneration()
        routeSelection = nil

        let planningState = try await planningService.request(request)
        guard generation == workflowSequence else {
            return snapshot
        }

        if case let .available(_, _, routes) = planningState {
            routeSelection = try NavigationRouteSelectionState(routes: routes)
        }

        return snapshot
    }

    /// Explicitly selects one route from the exact provider result generation
    /// represented by `selectionID`. Stale UI actions fail closed rather than
    /// retargeting the same array index into newer alternatives.
    @discardableResult
    public func selectRoute(
        _ selectionID: NavigationRouteSelectionID
    ) throws -> NavigationExperienceSnapshot {
        guard case let .available(currentToken, _, _) = planningService.state,
              currentToken == selectionID.requestToken else {
            throw NavigationExperienceError.staleRouteOptions
        }
        return try selectCurrentRoute(index: selectionID.index)
    }

    /// Package-internal convenience for deterministic tests/composition that
    /// intentionally means "the current result set". Production callers outside
    /// this module only get the generation-bound `NavigationRouteSelectionID` API.
    @discardableResult
    func selectRoute(index: Int) throws -> NavigationExperienceSnapshot {
        guard case let .available(currentToken, _, _) = planningService.state else {
            throw NavigationExperienceError.noRouteOptions
        }
        return try selectRoute(
            NavigationRouteSelectionID(
                requestToken: currentToken,
                index: index
            )
        )
    }

    /// Feeds only quality-screened location evidence into the selected route's
    /// existing navigation session. No selected route means no navigation update.
    @discardableResult
    public func process(
        location: QualityScreenedRideLocation
    ) throws -> NavigationSessionUpdate? {
        try session.process(location: location)
    }

    /// Cancels only the current planning request. Existing selected navigation
    /// remains active and any racing plan return is ignored by workflow identity.
    /// If no request is in flight, existing completed alternatives are preserved.
    @discardableResult
    public func cancelPlanning() throws -> Bool {
        _ = try nextWorkflowGeneration()
        let cancelled = planningService.cancelCurrent()
        if cancelled {
            routeSelection = nil
        }
        return cancelled
    }

    /// Clears active guidance explicitly while preserving the current provider
    /// alternatives as unselected choices when they still exist.
    public func clearSelectedRoute() {
        selectedRoute = nil
        if var selection = routeSelection {
            selection.clearSelection()
            routeSelection = selection
        }
        session.clearRoute()
    }

    /// Resets planning, alternatives, and active guidance without allowing a
    /// pre-reset async plan return to publish workflow state afterward.
    public func reset() throws {
        _ = try nextWorkflowGeneration()
        planningService.reset()
        routeSelection = nil
        selectedRoute = nil
        session.clearRoute()
    }

    private func selectCurrentRoute(
        index: Int
    ) throws -> NavigationExperienceSnapshot {
        guard var selection = routeSelection else {
            throw NavigationExperienceError.noRouteOptions
        }

        try selection.select(index: index)
        guard let route = selection.selectedRoute else {
            throw NavigationExperienceError.noRouteOptions
        }

        routeSelection = selection
        selectedRoute = route
        _ = try session.select(route: route)
        return snapshot
    }

    private func nextWorkflowGeneration() throws -> UInt64 {
        guard workflowSequence < UInt64.max else {
            throw NavigationExperienceError.workflowSequenceExhausted
        }
        workflowSequence += 1
        return workflowSequence
    }
}
