import Testing
@testable import NembraCore

@Suite("Navigation reroute evidence policy")
struct NavigationReroutePolicyTests {
    private func policy(
        minimumDeviationDistanceMeters: Double = 25,
        requiredConsecutiveAcceptedSamples: Int = 3,
        rerouteCooldownNanoseconds: UInt64 = 10_000_000_000
    ) throws -> NavigationReroutePolicy {
        try NavigationReroutePolicy(
            minimumDeviationDistanceMeters: minimumDeviationDistanceMeters,
            requiredConsecutiveAcceptedSamples: requiredConsecutiveAcceptedSamples,
            rerouteCooldownNanoseconds: rerouteCooldownNanoseconds
        )
    }

    private func observation(
        uptime: UInt64,
        distance: Double,
        confident: Bool = true
    ) throws -> NavigationRouteDeviationObservation {
        try NavigationRouteDeviationObservation(
            receivedAtUptimeNanoseconds: uptime,
            distanceFromActiveRouteMeters: distance,
            isProgressAssignmentConfident: confident
        )
    }

    @Test("policy has no one-sample reroute configuration")
    func policyRejectsSingleSampleRerouting() {
        #expect(throws: NavigationReroutePolicyError.invalidPolicy) {
            _ = try NavigationReroutePolicy(
                minimumDeviationDistanceMeters: 25,
                requiredConsecutiveAcceptedSamples: 1,
                rerouteCooldownNanoseconds: 1
            )
        }
    }

    @Test("invalid numeric or zero policy values fail closed")
    func invalidPolicyFailsClosed() {
        let invalidDistances: [Double] = [0, -1, .nan, .infinity]
        for distance in invalidDistances {
            #expect(throws: NavigationReroutePolicyError.invalidPolicy) {
                _ = try NavigationReroutePolicy(
                    minimumDeviationDistanceMeters: distance,
                    requiredConsecutiveAcceptedSamples: 2,
                    rerouteCooldownNanoseconds: 1
                )
            }
        }

        #expect(throws: NavigationReroutePolicyError.invalidPolicy) {
            _ = try NavigationReroutePolicy(
                minimumDeviationDistanceMeters: 25,
                requiredConsecutiveAcceptedSamples: 2,
                rerouteCooldownNanoseconds: 0
            )
        }
    }

    @Test("invalid deviation observations fail closed")
    func invalidObservationFailsClosed() {
        for distance in [-1.0, .nan, .infinity] {
            #expect(throws: NavigationReroutePolicyError.invalidObservation) {
                _ = try NavigationRouteDeviationObservation(
                    receivedAtUptimeNanoseconds: 1,
                    distanceFromActiveRouteMeters: distance,
                    isProgressAssignmentConfident: true
                )
            }
        }
    }

    @Test("one noisy off-route sample cannot request reroute")
    func oneSampleCannotReroute() throws {
        var evaluator = NavigationRerouteEvaluator(policy: try policy(requiredConsecutiveAcceptedSamples: 2))

        let decision = try evaluator.observe(observation(uptime: 1, distance: 100))

        #expect(decision == .keepCurrentRoute)
        #expect(evaluator.consecutiveDeviationSamples == 1)
        #expect(evaluator.lastRerouteRequestUptimeNanoseconds == nil)
    }

    @Test("sustained confident deviation requests exactly after the threshold")
    func sustainedDeviationRequestsReroute() throws {
        var evaluator = NavigationRerouteEvaluator(policy: try policy())

        let first = try evaluator.observe(observation(uptime: 1, distance: 30))
        let second = try evaluator.observe(observation(uptime: 2, distance: 40))
        let third = try evaluator.observe(observation(uptime: 3, distance: 50))

        #expect(first == .keepCurrentRoute)
        #expect(second == .keepCurrentRoute)
        #expect(third == .requestReroute)
        #expect(evaluator.consecutiveDeviationSamples == 0)
        #expect(evaluator.lastRerouteRequestUptimeNanoseconds == 3)
    }

    @Test("distance exactly on injected threshold counts")
    func exactThresholdCounts() throws {
        var evaluator = NavigationRerouteEvaluator(
            policy: try policy(minimumDeviationDistanceMeters: 25, requiredConsecutiveAcceptedSamples: 2)
        )

        let first = try evaluator.observe(observation(uptime: 1, distance: 25))
        let second = try evaluator.observe(observation(uptime: 2, distance: 25))

        #expect(first == .keepCurrentRoute)
        #expect(second == .requestReroute)
    }

    @Test("an on-route observation resets accumulated deviation")
    func onRouteResetsDeviationRun() throws {
        var evaluator = NavigationRerouteEvaluator(policy: try policy())

        _ = try evaluator.observe(observation(uptime: 1, distance: 40))
        _ = try evaluator.observe(observation(uptime: 2, distance: 40))
        let onRoute = try evaluator.observe(observation(uptime: 3, distance: 5))
        let nextDeviation = try evaluator.observe(observation(uptime: 4, distance: 40))

        #expect(onRoute == .keepCurrentRoute)
        #expect(nextDeviation == .keepCurrentRoute)
        #expect(evaluator.consecutiveDeviationSamples == 1)
    }

    @Test("ambiguous parallel-route progress fails closed and resets deviation")
    func ambiguousProgressResetsDeviationRun() throws {
        var evaluator = NavigationRerouteEvaluator(policy: try policy())

        _ = try evaluator.observe(observation(uptime: 1, distance: 50))
        _ = try evaluator.observe(observation(uptime: 2, distance: 50))
        let ambiguous = try evaluator.observe(observation(uptime: 3, distance: 100, confident: false))
        let afterAmbiguity = try evaluator.observe(observation(uptime: 4, distance: 50))

        #expect(ambiguous == .keepCurrentRoute)
        #expect(afterAmbiguity == .keepCurrentRoute)
        #expect(evaluator.consecutiveDeviationSamples == 1)
    }

    @Test("known continuity gap clears accumulated deviation")
    func continuityGapClearsDeviation() throws {
        var evaluator = NavigationRerouteEvaluator(policy: try policy())

        _ = try evaluator.observe(observation(uptime: 1, distance: 40))
        _ = try evaluator.observe(observation(uptime: 2, distance: 40))
        evaluator.markKnownContinuityGap()
        let afterGap = try evaluator.observe(observation(uptime: 3, distance: 40))

        #expect(afterGap == .keepCurrentRoute)
        #expect(evaluator.consecutiveDeviationSamples == 1)
    }

    @Test("continuity gap does not allow an older callback to become current")
    func gapRetainsMonotonicClock() throws {
        var evaluator = NavigationRerouteEvaluator(policy: try policy())

        _ = try evaluator.observe(observation(uptime: 10, distance: 40))
        evaluator.markKnownContinuityGap()

        #expect(throws: NavigationReroutePolicyError.nonMonotonicObservation) {
            _ = try evaluator.observe(observation(uptime: 9, distance: 40))
        }
        #expect(evaluator.lastAcceptedObservationUptimeNanoseconds == 10)
        #expect(evaluator.consecutiveDeviationSamples == 0)
    }

    @Test("nonmonotonic observation rejection is atomic")
    func nonMonotonicObservationIsAtomic() throws {
        var evaluator = NavigationRerouteEvaluator(policy: try policy())
        _ = try evaluator.observe(observation(uptime: 10, distance: 40))
        let beforeCount = evaluator.consecutiveDeviationSamples
        let beforeUptime = evaluator.lastAcceptedObservationUptimeNanoseconds

        #expect(throws: NavigationReroutePolicyError.nonMonotonicObservation) {
            _ = try evaluator.observe(observation(uptime: 10, distance: 100))
        }

        #expect(evaluator.consecutiveDeviationSamples == beforeCount)
        #expect(evaluator.lastAcceptedObservationUptimeNanoseconds == beforeUptime)
    }

    @Test("cooldown prevents immediate repeated reroute requests")
    func cooldownPreventsRequestStorms() throws {
        var evaluator = NavigationRerouteEvaluator(
            policy: try policy(requiredConsecutiveAcceptedSamples: 2, rerouteCooldownNanoseconds: 10)
        )

        _ = try evaluator.observe(observation(uptime: 1, distance: 40))
        let firstReroute = try evaluator.observe(observation(uptime: 2, distance: 40))
        _ = try evaluator.observe(observation(uptime: 3, distance: 40))
        let blocked = try evaluator.observe(observation(uptime: 4, distance: 40))
        let stillBlocked = try evaluator.observe(observation(uptime: 11, distance: 40))
        let allowedAtBoundary = try evaluator.observe(observation(uptime: 12, distance: 40))

        #expect(firstReroute == .requestReroute)
        #expect(blocked == .keepCurrentRoute)
        #expect(stillBlocked == .keepCurrentRoute)
        #expect(allowedAtBoundary == .requestReroute)
        #expect(evaluator.lastRerouteRequestUptimeNanoseconds == 12)
    }

    @Test("new selected route clears cooldown and accumulated deviation")
    func selectingNewRouteResetsRouteSpecificState() throws {
        var evaluator = NavigationRerouteEvaluator(
            policy: try policy(requiredConsecutiveAcceptedSamples: 2, rerouteCooldownNanoseconds: 100)
        )

        _ = try evaluator.observe(observation(uptime: 1, distance: 40))
        _ = try evaluator.observe(observation(uptime: 2, distance: 40))
        #expect(evaluator.lastRerouteRequestUptimeNanoseconds == 2)

        evaluator.didSelectNewRoute()
        #expect(evaluator.lastRerouteRequestUptimeNanoseconds == nil)
        #expect(evaluator.consecutiveDeviationSamples == 0)

        _ = try evaluator.observe(observation(uptime: 3, distance: 40))
        let rerouteOnNewRoute = try evaluator.observe(observation(uptime: 4, distance: 40))
        #expect(rerouteOnNewRoute == .requestReroute)
    }
}
