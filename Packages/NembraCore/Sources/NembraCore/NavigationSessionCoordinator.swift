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
    private var lastSeenLocationUptimeNanoseconds: UInt64?

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

    /// Returns nil whenever no route is selected. Quality-screened callbacks seen
    /// while navigation is idle/cleared still advance the process-local high-water
    /// mark when newer, so a later route selection cannot resurrect an older delayed
    /// callback as current evidence. Replayed/older callbacks remain harmless nils
    /// while idle and never regress that high-water mark. With a selected route,
    /// non-monotonic callbacks fail closed before guidance or reroute mutation.
    @discardableResult
    public mutating func process(
        location: QualityScreenedRideLocation
    ) throws -> NavigationSessionUpdate? {
        let uptime = location.sample.receivedAtUptimeNanoseconds
        if let lastSeenLocationUptimeNanoseconds,
           uptime <= lastSeenLocationUptimeNanoseconds {
            guard selectedRoute != nil, selectionToken != nil else {
                return nil
            }
            throw NavigationSessionCoordinatorError.nonMonotonicLocation
        }
        lastSeenLocationUptimeNanoseconds = uptime

        guard let selectedRoute, let selectionToken else {
            return nil
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

        return NavigationSessionUpdate(
            geometryMatch: match,
            guidanceState: guidanceTracker.state,
            rerouteDecision: rerouteDecision
        )
    }

    /// Clears navigation selection/presentation state without pretending the
    /// process-local seen-callback clock restarted. Newer screened callbacks observed
    /// while cleared continue advancing that clock, while replayed/older callbacks
    /// cannot move it backward. Later route selection therefore cannot resurrect
    /// older callbacks from the idle interval as current evidence.
    public mutating func clearRoute() {
        selectedRoute = nil
        selectionToken = nil
        guidanceTracker.clearSelection()
        rerouteEvaluator.didSelectNewRoute()
    }
}
