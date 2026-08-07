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
    let route: NavigationRouteSnapshot

    init(
        requestToken: NavigationRouteRequestToken,
        index: Int,
        route: NavigationRouteSnapshot
    ) {
        self.requestToken = requestToken
        self.index = index
        self.route = route
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
    /// represented by `selectionID`. Both request identity and immutable route
    /// facts must still match, so an ID from a replaced coordinator cannot
    /// silently collide with a restarted token sequence/index.
    @discardableResult
    public func selectRoute(
        _ selectionID: NavigationRouteSelectionID
    ) throws -> NavigationExperienceSnapshot {
        try selectValidatedRoute(selectionID, receiptFence: nil)
    }

    /// Explicitly selects one route and binds it to the caller's process-local
    /// selection receipt boundary. Use this overload when quality-screened
    /// location delivery can already be queued while the user selects a route.
    ///
    /// `receiptFence` must come from the same monotonic receipt clock used by
    /// `RideLocationSample.receivedAtUptimeNanoseconds`. It is delivery-order
    /// evidence only: never GPS measurement time, route progress, ride duration,
    /// or proof that the provider route is physically safe for a scooter.
    @discardableResult
    public func selectRoute(
        _ selectionID: NavigationRouteSelectionID,
        receiptFence: NavigationRouteSelectionReceiptFence
    ) throws -> NavigationExperienceSnapshot {
        try selectValidatedRoute(selectionID, receiptFence: receiptFence)
    }

    /// Package-internal convenience for deterministic tests/composition that
    /// intentionally means "the current result set". Production callers outside
    /// this module only get the generation-bound `NavigationRouteSelectionID` API.
    @discardableResult
    func selectRoute(index: Int) throws -> NavigationExperienceSnapshot {
        guard case .available = planningService.state else {
            throw NavigationExperienceError.noRouteOptions
        }
        return try selectCurrentRoute(index: index, receiptFence: nil)
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

    private func selectValidatedRoute(
        _ selectionID: NavigationRouteSelectionID,
        receiptFence: NavigationRouteSelectionReceiptFence?
    ) throws -> NavigationExperienceSnapshot {
        guard case let .available(currentToken, _, _) = planningService.state,
              currentToken == selectionID.requestToken,
              let selection = routeSelection,
              selection.routes.indices.contains(selectionID.index),
              selection.routes[selectionID.index] == selectionID.route else {
            throw NavigationExperienceError.staleRouteOptions
        }
        return try selectCurrentRoute(
            index: selectionID.index,
            receiptFence: receiptFence
        )
    }

    private func selectCurrentRoute(
        index: Int,
        receiptFence: NavigationRouteSelectionReceiptFence?
    ) throws -> NavigationExperienceSnapshot {
        guard var selection = routeSelection else {
            throw NavigationExperienceError.noRouteOptions
        }

        try selection.select(index: index)
        guard let route = selection.selectedRoute else {
            throw NavigationExperienceError.noRouteOptions
        }

        // Commit the throwing navigation-session selection first. If its
        // generation/fence validation fails, presentation state must remain on
        // the previously accepted route rather than claiming an unaccepted one.
        if let receiptFence {
            _ = try session.select(route: route, receiptFence: receiptFence)
        } else {
            _ = try session.select(route: route)
        }
        routeSelection = selection
        selectedRoute = route
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