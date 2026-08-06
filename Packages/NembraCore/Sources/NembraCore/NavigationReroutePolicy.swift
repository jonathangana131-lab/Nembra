public enum NavigationReroutePolicyError: Error, Equatable, Sendable {
    case invalidPolicy
    case invalidObservation
    case nonMonotonicObservation
}

/// Injected policy for deciding when accepted location-derived route-deviation
/// evidence is strong enough to request a new provider route.
///
/// There is intentionally no production default. Real iPhone/ES80 outdoor traces
/// must justify the corridor distance and cooldown. The domain does enforce that
/// more than one accepted sample is required so one noisy coordinate cannot
/// request a reroute.
public struct NavigationReroutePolicy: Equatable, Sendable {
    public let minimumDeviationDistanceMeters: Double
    public let requiredConsecutiveAcceptedSamples: Int
    public let rerouteCooldownNanoseconds: UInt64

    public init(
        minimumDeviationDistanceMeters: Double,
        requiredConsecutiveAcceptedSamples: Int,
        rerouteCooldownNanoseconds: UInt64
    ) throws {
        guard minimumDeviationDistanceMeters.isFinite,
              minimumDeviationDistanceMeters > 0,
              requiredConsecutiveAcceptedSamples >= 2,
              rerouteCooldownNanoseconds > 0 else {
            throw NavigationReroutePolicyError.invalidPolicy
        }

        self.minimumDeviationDistanceMeters = minimumDeviationDistanceMeters
        self.requiredConsecutiveAcceptedSamples = requiredConsecutiveAcceptedSamples
        self.rerouteCooldownNanoseconds = rerouteCooldownNanoseconds
    }
}

/// One route-deviation observation produced *after* phone-location evidence has
/// passed Nembra's location-quality screen and a future guidance geometry layer
/// has compared it with the active route.
///
/// `isProgressAssignmentConfident` must be false when the guidance layer cannot
/// distinguish plausible route progress from an ambiguous nearby/parallel path.
/// Ambiguous observations never accumulate toward rerouting.
public struct NavigationRouteDeviationObservation: Equatable, Sendable {
    public let receivedAtUptimeNanoseconds: UInt64
    public let distanceFromActiveRouteMeters: Double
    public let isProgressAssignmentConfident: Bool

    public init(
        receivedAtUptimeNanoseconds: UInt64,
        distanceFromActiveRouteMeters: Double,
        isProgressAssignmentConfident: Bool
    ) throws {
        guard distanceFromActiveRouteMeters.isFinite,
              distanceFromActiveRouteMeters >= 0 else {
            throw NavigationReroutePolicyError.invalidObservation
        }

        self.receivedAtUptimeNanoseconds = receivedAtUptimeNanoseconds
        self.distanceFromActiveRouteMeters = distanceFromActiveRouteMeters
        self.isProgressAssignmentConfident = isProgressAssignmentConfident
    }
}

public enum NavigationRerouteDecision: Equatable, Sendable {
    case keepCurrentRoute
    case requestReroute
}

/// Deterministic evidence accumulator for reroute eligibility.
///
/// This type never computes route geometry, never accepts raw Core Location
/// callbacks, never mutates ride distance, and never makes a route legal/safe.
/// The caller must explicitly reset evidence at known location continuity gaps.
public struct NavigationRerouteEvaluator: Sendable {
    private let policy: NavigationReroutePolicy
    public private(set) var consecutiveDeviationSamples: Int = 0
    public private(set) var lastAcceptedObservationUptimeNanoseconds: UInt64?
    public private(set) var lastRerouteRequestUptimeNanoseconds: UInt64?

    public init(policy: NavigationReroutePolicy) {
        self.policy = policy
    }

    @discardableResult
    public mutating func observe(
        _ observation: NavigationRouteDeviationObservation
    ) throws -> NavigationRerouteDecision {
        if let lastAcceptedObservationUptimeNanoseconds,
           observation.receivedAtUptimeNanoseconds <= lastAcceptedObservationUptimeNanoseconds {
            throw NavigationReroutePolicyError.nonMonotonicObservation
        }

        // From this point the observation is accepted transactionally as the next
        // monotonic guidance-evidence sample. Ambiguity/on-route evidence clears a
        // prior deviation run instead of allowing disconnected evidence to stack.
        lastAcceptedObservationUptimeNanoseconds = observation.receivedAtUptimeNanoseconds

        guard observation.isProgressAssignmentConfident,
              observation.distanceFromActiveRouteMeters >= policy.minimumDeviationDistanceMeters else {
            consecutiveDeviationSamples = 0
            return .keepCurrentRoute
        }

        if consecutiveDeviationSamples < Int.max {
            consecutiveDeviationSamples += 1
        }

        guard consecutiveDeviationSamples >= policy.requiredConsecutiveAcceptedSamples else {
            return .keepCurrentRoute
        }

        if let lastRerouteRequestUptimeNanoseconds {
            let elapsed = observation.receivedAtUptimeNanoseconds - lastRerouteRequestUptimeNanoseconds
            guard elapsed >= policy.rerouteCooldownNanoseconds else {
                return .keepCurrentRoute
            }
        }

        lastRerouteRequestUptimeNanoseconds = observation.receivedAtUptimeNanoseconds
        consecutiveDeviationSamples = 0
        return .requestReroute
    }

    /// A known location/guidance continuity gap invalidates accumulated route-
    /// deviation evidence. The monotonic observation clock remains process-local
    /// and is retained so an older callback arriving after the gap cannot become
    /// current evidence.
    public mutating func markKnownContinuityGap() {
        consecutiveDeviationSamples = 0
    }

    /// A newly selected route invalidates both accumulated deviation and reroute
    /// cooldown from the previous route identity. The observation clock remains
    /// monotonic within the process to reject stale callbacks.
    public mutating func didSelectNewRoute() {
        consecutiveDeviationSamples = 0
        lastRerouteRequestUptimeNanoseconds = nil
    }
}
