public enum NavigationReroutePolicyError: Error, Equatable, Sendable {
    case invalidOffRouteEnterDistance
    case invalidOnRouteExitDistance
    case invalidMinimumOffRouteSamples
    case invalidMinimumOffRouteDuration
    case invalidRerouteCooldown
    case invalidDistanceFromRoute
    case nonMonotonicReceiptUptime
    case sampleCountExhausted
}

/// Injected, evidence-gated thresholds for converting accepted navigation deviation
/// evidence into a reroute recommendation.
///
/// These values are product policy, not route-provider or scooter telemetry. Production
/// thresholds must remain configurable until real iPhone/ride traces justify them.
public struct NavigationReroutePolicy: Equatable, Sendable {
    public let offRouteEnterDistanceMeters: Double
    public let onRouteExitDistanceMeters: Double
    public let minimumOffRouteSamples: Int
    public let minimumOffRouteDurationSeconds: Double
    public let rerouteCooldownSeconds: Double

    public init(
        offRouteEnterDistanceMeters: Double,
        onRouteExitDistanceMeters: Double,
        minimumOffRouteSamples: Int,
        minimumOffRouteDurationSeconds: Double,
        rerouteCooldownSeconds: Double
    ) throws {
        guard offRouteEnterDistanceMeters.isFinite,
              offRouteEnterDistanceMeters > 0 else {
            throw NavigationReroutePolicyError.invalidOffRouteEnterDistance
        }
        guard onRouteExitDistanceMeters.isFinite,
              onRouteExitDistanceMeters >= 0,
              onRouteExitDistanceMeters < offRouteEnterDistanceMeters else {
            throw NavigationReroutePolicyError.invalidOnRouteExitDistance
        }
        guard minimumOffRouteSamples >= 2 else {
            throw NavigationReroutePolicyError.invalidMinimumOffRouteSamples
        }
        guard minimumOffRouteDurationSeconds.isFinite,
              minimumOffRouteDurationSeconds > 0 else {
            throw NavigationReroutePolicyError.invalidMinimumOffRouteDuration
        }
        guard rerouteCooldownSeconds.isFinite,
              rerouteCooldownSeconds >= 0 else {
            throw NavigationReroutePolicyError.invalidRerouteCooldown
        }

        self.offRouteEnterDistanceMeters = offRouteEnterDistanceMeters
        self.onRouteExitDistanceMeters = onRouteExitDistanceMeters
        self.minimumOffRouteSamples = minimumOffRouteSamples
        self.minimumOffRouteDurationSeconds = minimumOffRouteDurationSeconds
        self.rerouteCooldownSeconds = rerouteCooldownSeconds
    }
}

public enum NavigationRouteAdherence: Equatable, Sendable {
    case unknown
    case onRoute
    case suspectedOffRoute(sampleCount: Int)
    case offRoute
}

public enum NavigationRerouteRecommendation: Equatable, Sendable {
    case none
    case requestNewRoute
}

public struct NavigationRerouteUpdate: Equatable, Sendable {
    public let adherence: NavigationRouteAdherence
    public let recommendation: NavigationRerouteRecommendation

    public init(
        adherence: NavigationRouteAdherence,
        recommendation: NavigationRerouteRecommendation
    ) {
        self.adherence = adherence
        self.recommendation = recommendation
    }
}

/// Stateful evidence gate for reroute requests.
///
/// `distanceFromRouteMeters` must already have been derived by a navigation geometry layer
/// from accepted location evidence. This type never accepts raw Core Location callbacks and
/// its derived route-distance values must never be fed back into ride/GPS distance truth.
/// `receiptUptimeNanoseconds` intentionally shares the existing ride-location process-local
/// ordering clock; it is not persisted or compared across a relaunch/reboot.
public struct NavigationRerouteTracker: Equatable, Sendable {
    public let policy: NavigationReroutePolicy
    public private(set) var adherence: NavigationRouteAdherence = .unknown

    private var lastReceiptUptimeNanoseconds: UInt64?
    private var suspectedOffRouteStartUptimeNanoseconds: UInt64?
    private var suspectedOffRouteSamples = 0
    private var rerouteIssuedForCurrentEpisode = false
    private var lastRerouteRequestUptimeNanoseconds: UInt64?

    public init(policy: NavigationReroutePolicy) {
        self.policy = policy
    }

    /// Consumes one already-screened navigation deviation observation.
    ///
    /// Receipt uptime must be strictly increasing. Equal uptime is rejected so one accepted
    /// location fix cannot be counted repeatedly toward the multi-sample off-route threshold.
    @discardableResult
    public mutating func ingest(
        distanceFromRouteMeters: Double,
        receiptUptimeNanoseconds: UInt64
    ) throws -> NavigationRerouteUpdate {
        try validateReceiptUptime(receiptUptimeNanoseconds)
        guard distanceFromRouteMeters.isFinite, distanceFromRouteMeters >= 0 else {
            throw NavigationReroutePolicyError.invalidDistanceFromRoute
        }

        if distanceFromRouteMeters >= policy.offRouteEnterDistanceMeters,
           case .suspectedOffRoute = adherence,
           suspectedOffRouteSamples == Int.max {
            throw NavigationReroutePolicyError.sampleCountExhausted
        }

        lastReceiptUptimeNanoseconds = receiptUptimeNanoseconds

        if distanceFromRouteMeters <= policy.onRouteExitDistanceMeters {
            adherence = .onRoute
            clearOffRouteEpisode()
            return currentUpdate(recommendation: .none)
        }

        if distanceFromRouteMeters < policy.offRouteEnterDistanceMeters {
            return currentUpdate(recommendation: .none)
        }

        switch adherence {
        case .unknown, .onRoute:
            suspectedOffRouteStartUptimeNanoseconds = receiptUptimeNanoseconds
            suspectedOffRouteSamples = 1
            rerouteIssuedForCurrentEpisode = false
            adherence = .suspectedOffRoute(sampleCount: 1)
            return currentUpdate(recommendation: .none)

        case .suspectedOffRoute:
            suspectedOffRouteSamples += 1
            adherence = .suspectedOffRoute(sampleCount: suspectedOffRouteSamples)

            let startUptime = suspectedOffRouteStartUptimeNanoseconds ?? receiptUptimeNanoseconds
            let durationSeconds = secondsBetween(startUptime, receiptUptimeNanoseconds)
            guard suspectedOffRouteSamples >= policy.minimumOffRouteSamples,
                  durationSeconds >= policy.minimumOffRouteDurationSeconds else {
                return currentUpdate(recommendation: .none)
            }

            adherence = .offRoute
            return issueRerouteIfEligible(at: receiptUptimeNanoseconds)

        case .offRoute:
            return issueRerouteIfEligible(at: receiptUptimeNanoseconds)
        }
    }

    /// Marks a known interval where accepted navigation location evidence was not observed.
    /// This mirrors the ride-location layer's explicit gap marker: the gap itself does not
    /// invent a timestamp or location sample. In-flight adherence confidence is discarded;
    /// the last accepted sample ordering baseline and reroute cooldown history are preserved.
    @discardableResult
    public mutating func markContinuityInterrupted() -> NavigationRerouteUpdate {
        adherence = .unknown
        clearOffRouteEpisode()
        return currentUpdate(recommendation: .none)
    }

    /// A replacement route invalidates adherence to the prior geometry. Existing cooldown
    /// history remains in force so repeated route replacements cannot create request storms.
    public mutating func markReplacementRouteAccepted() {
        adherence = .unknown
        clearOffRouteEpisode()
    }

    private mutating func issueRerouteIfEligible(
        at receiptUptimeNanoseconds: UInt64
    ) -> NavigationRerouteUpdate {
        guard !rerouteIssuedForCurrentEpisode else {
            return currentUpdate(recommendation: .none)
        }

        if let lastRerouteRequestUptimeNanoseconds,
           secondsBetween(lastRerouteRequestUptimeNanoseconds, receiptUptimeNanoseconds)
               < policy.rerouteCooldownSeconds {
            return currentUpdate(recommendation: .none)
        }

        rerouteIssuedForCurrentEpisode = true
        lastRerouteRequestUptimeNanoseconds = receiptUptimeNanoseconds
        return currentUpdate(recommendation: .requestNewRoute)
    }

    private mutating func clearOffRouteEpisode() {
        suspectedOffRouteStartUptimeNanoseconds = nil
        suspectedOffRouteSamples = 0
        rerouteIssuedForCurrentEpisode = false
    }

    private func currentUpdate(
        recommendation: NavigationRerouteRecommendation
    ) -> NavigationRerouteUpdate {
        NavigationRerouteUpdate(
            adherence: adherence,
            recommendation: recommendation
        )
    }

    private func validateReceiptUptime(_ receiptUptimeNanoseconds: UInt64) throws {
        if let lastReceiptUptimeNanoseconds,
           receiptUptimeNanoseconds <= lastReceiptUptimeNanoseconds {
            throw NavigationReroutePolicyError.nonMonotonicReceiptUptime
        }
    }

    private func secondsBetween(_ earlier: UInt64, _ later: UInt64) -> Double {
        Double(later - earlier) / 1_000_000_000
    }
}
