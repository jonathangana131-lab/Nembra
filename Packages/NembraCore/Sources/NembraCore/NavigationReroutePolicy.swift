public enum NavigationReroutePolicyError: Error, Equatable, Sendable {
    case invalidPolicy
    case invalidObservation
    case nonMonotonicObservation
}

/// Injected policy for deciding when accepted location-derived route-deviation
/// evidence is strong enough to request a new provider route.
///
/// There is intentionally no production default. Real iPhone/ES80 outdoor traces
/// must justify the deviation corridor, sustained-duration window, maximum
/// accepted-observation gap, and cooldown. The domain requires multiple accepted
/// samples, elapsed deviation time, and bounded spacing between those samples so
/// one noisy coordinate, an unrealistically dense callback burst, or a long
/// interval with no evidence cannot request a reroute.
public struct NavigationReroutePolicy: Equatable, Sendable {
    public let minimumDeviationDistanceMeters: Double
    public let requiredConsecutiveAcceptedSamples: Int
    public let minimumConsecutiveDeviationDurationNanoseconds: UInt64
    public let maximumAcceptedObservationGapNanoseconds: UInt64
    public let rerouteCooldownNanoseconds: UInt64

    public init(
        minimumDeviationDistanceMeters: Double,
        requiredConsecutiveAcceptedSamples: Int,
        minimumConsecutiveDeviationDurationNanoseconds: UInt64,
        maximumAcceptedObservationGapNanoseconds: UInt64,
        rerouteCooldownNanoseconds: UInt64
    ) throws {
        guard minimumDeviationDistanceMeters.isFinite,
              minimumDeviationDistanceMeters > 0,
              requiredConsecutiveAcceptedSamples >= 2,
              minimumConsecutiveDeviationDurationNanoseconds > 0,
              maximumAcceptedObservationGapNanoseconds > 0,
              rerouteCooldownNanoseconds > 0 else {
            throw NavigationReroutePolicyError.invalidPolicy
        }

        self.minimumDeviationDistanceMeters = minimumDeviationDistanceMeters
        self.requiredConsecutiveAcceptedSamples = requiredConsecutiveAcceptedSamples
        self.minimumConsecutiveDeviationDurationNanoseconds = minimumConsecutiveDeviationDurationNanoseconds
        self.maximumAcceptedObservationGapNanoseconds = maximumAcceptedObservationGapNanoseconds
        self.rerouteCooldownNanoseconds = rerouteCooldownNanoseconds
    }
}

/// One route-deviation observation produced *after* phone-location evidence has
/// passed Nembra's location-quality screen and a future guidance geometry layer
/// has compared it with the active route.
///
/// `isDeviationAssessmentConfident` describes confidence in the distance-from-route
/// assessment only. It is intentionally separate from route-progress assignment:
/// a location may be too far from the route for trustworthy progress while still
/// providing strong evidence that the rider is materially off the active route.
public struct NavigationRouteDeviationObservation: Equatable, Sendable {
    public let receivedAtUptimeNanoseconds: UInt64
    public let distanceFromActiveRouteMeters: Double
    public let isDeviationAssessmentConfident: Bool

    public init(
        receivedAtUptimeNanoseconds: UInt64,
        distanceFromActiveRouteMeters: Double,
        isDeviationAssessmentConfident: Bool
    ) throws {
        guard distanceFromActiveRouteMeters.isFinite,
              distanceFromActiveRouteMeters >= 0 else {
            throw NavigationReroutePolicyError.invalidObservation
        }

        self.receivedAtUptimeNanoseconds = receivedAtUptimeNanoseconds
        self.distanceFromActiveRouteMeters = distanceFromActiveRouteMeters
        self.isDeviationAssessmentConfident = isDeviationAssessmentConfident
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
/// Explicit known continuity gaps reset evidence immediately. In addition, the
/// caller-supplied maximum accepted-observation gap prevents silent periods from
/// being counted as if off-route evidence had been continuously observed.
public struct NavigationRerouteEvaluator: Sendable {
    private let policy: NavigationReroutePolicy
    public private(set) var consecutiveDeviationSamples: Int = 0
    public private(set) var deviationRunStartUptimeNanoseconds: UInt64?
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

        // A deviation run is evidence-contiguous only while accepted callbacks
        // remain within the caller's explicit gap bound. A longer silent interval
        // is missing evidence, not proof that the rider stayed off route. Keep the
        // process chronology and reroute cooldown, but make the current sample the
        // first possible member of a fresh deviation run.
        if consecutiveDeviationSamples > 0,
           let lastAcceptedObservationUptimeNanoseconds {
            let acceptedObservationGap =
                observation.receivedAtUptimeNanoseconds - lastAcceptedObservationUptimeNanoseconds
            if acceptedObservationGap > policy.maximumAcceptedObservationGapNanoseconds {
                resetDeviationRun()
            }
        }

        // From this point the observation is accepted transactionally as the next
        // monotonic guidance-evidence sample. Ambiguity/on-route evidence clears a
        // prior deviation run instead of allowing disconnected evidence to stack.
        lastAcceptedObservationUptimeNanoseconds = observation.receivedAtUptimeNanoseconds

        guard observation.isDeviationAssessmentConfident,
              observation.distanceFromActiveRouteMeters >= policy.minimumDeviationDistanceMeters else {
            resetDeviationRun()
            return .keepCurrentRoute
        }

        if consecutiveDeviationSamples == 0 {
            deviationRunStartUptimeNanoseconds = observation.receivedAtUptimeNanoseconds
        }
        if consecutiveDeviationSamples < Int.max {
            consecutiveDeviationSamples += 1
        }

        guard consecutiveDeviationSamples >= policy.requiredConsecutiveAcceptedSamples,
              let deviationRunStartUptimeNanoseconds else {
            return .keepCurrentRoute
        }
        let deviationElapsed = observation.receivedAtUptimeNanoseconds - deviationRunStartUptimeNanoseconds
        guard deviationElapsed >= policy.minimumConsecutiveDeviationDurationNanoseconds else {
            return .keepCurrentRoute
        }

        if let lastRerouteRequestUptimeNanoseconds {
            let elapsed = observation.receivedAtUptimeNanoseconds - lastRerouteRequestUptimeNanoseconds
            guard elapsed >= policy.rerouteCooldownNanoseconds else {
                return .keepCurrentRoute
            }
        }

        lastRerouteRequestUptimeNanoseconds = observation.receivedAtUptimeNanoseconds
        resetDeviationRun()
        return .requestReroute
    }

    /// A known location/guidance continuity gap invalidates accumulated route-
    /// deviation evidence. The monotonic observation clock remains process-local
    /// and is retained so an older callback arriving after the gap cannot become
    /// current evidence.
    public mutating func markKnownContinuityGap() {
        resetDeviationRun()
    }

    /// A newly selected route invalidates both accumulated deviation and reroute
    /// cooldown from the previous route identity. The observation clock remains
    /// monotonic within the process to reject stale callbacks.
    public mutating func didSelectNewRoute() {
        resetDeviationRun()
        lastRerouteRequestUptimeNanoseconds = nil
    }

    private mutating func resetDeviationRun() {
        consecutiveDeviationSamples = 0
        deviationRunStartUptimeNanoseconds = nil
    }
}
