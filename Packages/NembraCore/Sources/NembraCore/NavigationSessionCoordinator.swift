public enum NavigationSessionCoordinatorError: Error, Equatable, Sendable {
    case nonMonotonicLocation
    case nonMonotonicSelectionFence
    case locationReceivedAtOrBeforeSelectionFence
}

/// Process-local receipt boundary for one route-selection event.
///
/// Capture `selectedAtUptimeNanoseconds` from the same monotonic clock used by
/// `RideLocationSample.receivedAtUptimeNanoseconds`, at the moment the route
/// selection becomes current. A quality-screened location received at or before
/// this boundary cannot become guidance/reroute evidence for that selection even
/// if downstream async delivery reaches the coordinator later.
///
/// This is a delivery-order fence only. It is not GPS measurement time, route
/// progress, ride duration, or proof that the provider route is physically valid.
public struct NavigationRouteSelectionReceiptFence: Equatable, Sendable {
    public let selectedAtUptimeNanoseconds: UInt64

    public init(selectedAtUptimeNanoseconds: UInt64) {
        self.selectedAtUptimeNanoseconds = selectedAtUptimeNanoseconds
    }
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
    private var selectionReceiptFenceUptimeNanoseconds: UInt64?
    private var lastSeenSelectionReceiptFenceUptimeNanoseconds: UInt64?
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

    /// Selects a route without minting a new receipt-time fence.
    ///
    /// This preserves the original synchronous/serialized contract: the global
    /// seen-callback high-water mark still rejects callbacks older than any
    /// location already delivered to this coordinator. If an earlier strong
    /// selection established a process-local receipt fence, this compatibility
    /// path preserves that already-proven floor instead of weakening chronology.
    /// It does not pretend that floor is the exact time of this newer selection.
    /// Callers whose route selection can race with already-screened location
    /// delivery should use the `receiptFence` overload for an exact new boundary.
    @discardableResult
    public mutating func select(
        route: NavigationRouteSnapshot
    ) throws -> NavigationGuidanceSelectionToken {
        try installSelection(route: route, receiptFenceUptimeNanoseconds: nil)
    }

    /// Selects a route with an explicit process-local receipt boundary.
    ///
    /// The fence is intentionally caller-supplied because the coordinator cannot
    /// reconstruct when an upstream route-selection event happened relative to an
    /// asynchronously queued location callback. Only location receipts strictly
    /// newer than the fence may become guidance/reroute evidence for this route.
    /// A fence older than the coordinator's existing seen-location high-water mark
    /// is still safe: the existing location high-water mark is the stronger boundary.
    /// Fenced route selections themselves may not move backward in the same
    /// coordinator process; a regressing fence is rejected before selection state
    /// or reroute state mutates.
    @discardableResult
    public mutating func select(
        route: NavigationRouteSnapshot,
        receiptFence: NavigationRouteSelectionReceiptFence
    ) throws -> NavigationGuidanceSelectionToken {
        try installSelection(
            route: route,
            receiptFenceUptimeNanoseconds: receiptFence.selectedAtUptimeNanoseconds
        )
    }

    /// Returns nil whenever no route is selected. Quality-screened callbacks seen
    /// while navigation is idle/cleared still advance the process-local high-water
    /// mark when newer, so a later route selection cannot resurrect an older delayed
    /// callback as current evidence. Replayed/older callbacks remain harmless nils
    /// while idle and never regress that high-water mark. With a selected route,
    /// non-monotonic callbacks fail closed before guidance or reroute mutation.
    ///
    /// When the selected route carries an explicit or inherited proven receipt
    /// floor, a newer-to-this-coordinator callback can still fail closed if its
    /// actual receipt uptime is not newer than that floor. That rejected callback
    /// still advances the global seen-callback high-water mark, preserving replay
    /// protection without promoting it into route progress or reroute evidence.
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

        if let selectionReceiptFenceUptimeNanoseconds,
           uptime <= selectionReceiptFenceUptimeNanoseconds {
            throw NavigationSessionCoordinatorError.locationReceivedAtOrBeforeSelectionFence
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
    /// older callbacks from the idle interval as current evidence. The active route
    /// fence is removed, but the last fenced-selection high-water mark is retained.
    /// A later compatibility selection inherits that value only as a conservative
    /// known floor; a later strong selection must supply a non-regressing exact fence.
    public mutating func clearRoute() {
        selectedRoute = nil
        selectionToken = nil
        selectionReceiptFenceUptimeNanoseconds = nil
        guidanceTracker.clearSelection()
        rerouteEvaluator.didSelectNewRoute()
    }

    private mutating func installSelection(
        route: NavigationRouteSnapshot,
        receiptFenceUptimeNanoseconds: UInt64?
    ) throws -> NavigationGuidanceSelectionToken {
        if let receiptFenceUptimeNanoseconds,
           let lastSeenSelectionReceiptFenceUptimeNanoseconds,
           receiptFenceUptimeNanoseconds < lastSeenSelectionReceiptFenceUptimeNanoseconds {
            throw NavigationSessionCoordinatorError.nonMonotonicSelectionFence
        }

        let token = try guidanceTracker.select(route: route)
        selectedRoute = route
        selectionToken = token
        selectionReceiptFenceUptimeNanoseconds =
            receiptFenceUptimeNanoseconds ?? lastSeenSelectionReceiptFenceUptimeNanoseconds
        if let receiptFenceUptimeNanoseconds {
            lastSeenSelectionReceiptFenceUptimeNanoseconds = receiptFenceUptimeNanoseconds
        }
        rerouteEvaluator.didSelectNewRoute()
        return token
    }
}
