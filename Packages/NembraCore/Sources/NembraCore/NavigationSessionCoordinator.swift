public enum NavigationSessionCoordinatorError: Error, Equatable, Sendable {
    case nonMonotonicLocation
}

public struct NavigationSessionUpdate: Equatable, Sendable {
    public let geometryMatch: NavigationRouteGeometryMatch
    public let guidanceState: NavigationGuidanceProgressState
    public let rerouteDecision: NavigationRerouteDecision
}

/// Deterministic composition root for the platform-neutral navigation domain.
///
/// The session accepts only `QualityScreenedRideLocation`, projects it through
/// the injected geometry policy, updates guidance progress, and then feeds the
/// same immutable match into reroute evidence. A process-local monotonic gate is
/// checked before either reducer mutates so stale callbacks cannot partially
/// update one navigation subsystem but not the other.
public struct NavigationSessionCoordinator: Sendable {
    private let geometryMatcher: NavigationRouteGeometryMatcher
    private var guidanceTracker: NavigationGuidanceProgressTracker
    private var rerouteEvaluator: NavigationRerouteEvaluator
    private var selectedRoute: NavigationRouteSnapshot?
    private var selectionToken: NavigationGuidanceSelectionToken?
    private var lastProcessedLocationUptimeNanoseconds: UInt64?

    public var guidanceState: NavigationGuidanceProgressState {
        guidanceTracker.state
    }

    public init(
        geometryPolicy: NavigationRouteGeometryMatchingPolicy,
        reroutePolicy: NavigationReroutePolicy
    ) {
        geometryMatcher = NavigationRouteGeometryMatcher(policy: geometryPolicy)
        guidanceTracker = NavigationGuidanceProgressTracker()
        rerouteEvaluator = NavigationRerouteEvaluator(policy: reroutePolicy)
    }

    @discardableResult
    public mutating func select(
        route: NavigationRouteSnapshot
    ) throws -> NavigationGuidanceSelectionToken {
        let token = try guidanceTracker.select(route: route)
        selectedRoute = route
        selectionToken = token
        rerouteEvaluator.didSelectNewRoute()
        return token
    }

    /// Returns nil when no route is selected. A valid screened observation is
    /// otherwise applied transactionally across geometry, guidance, and reroute
    /// state under one process-local monotonic ordering gate.
    @discardableResult
    public mutating func process(
        location: QualityScreenedRideLocation
    ) throws -> NavigationSessionUpdate? {
        guard let selectedRoute, let selectionToken else {
            return nil
        }

        if let lastProcessedLocationUptimeNanoseconds,
           location.sample.receivedAtUptimeNanoseconds <= lastProcessedLocationUptimeNanoseconds {
            throw NavigationSessionCoordinatorError.nonMonotonicLocation
        }

        let match = geometryMatcher.match(location: location, route: selectedRoute)
        let guidanceObservation = try match.guidanceObservation(selectionToken: selectionToken)
        let rerouteObservation = try match.rerouteObservation()

        if match.startsNewRouteSegment {
            guidanceTracker.markKnownContinuityGap()
            rerouteEvaluator.markKnownContinuityGap()
        }

        _ = try guidanceTracker.observe(guidanceObservation)
        let rerouteDecision = try rerouteEvaluator.observe(rerouteObservation)
        lastProcessedLocationUptimeNanoseconds = location.sample.receivedAtUptimeNanoseconds

        return NavigationSessionUpdate(
            geometryMatch: match,
            guidanceState: guidanceTracker.state,
            rerouteDecision: rerouteDecision
        )
    }

    /// Clears navigation selection/presentation state without pretending the
    /// process-local callback clock restarted. A later selection therefore still
    /// cannot accept an older callback from before the clear.
    public mutating func clearRoute() {
        selectedRoute = nil
        selectionToken = nil
        guidanceTracker.clearSelection()
        rerouteEvaluator.didSelectNewRoute()
    }
}
