import Testing
@testable import NembraCore

@Suite("Navigation reroute policy")
struct NavigationReroutePolicyTests {
    private func policy(cooldown: Double = 30) throws -> NavigationReroutePolicy {
        try NavigationReroutePolicy(
            offRouteEnterDistanceMeters: 20,
            onRouteExitDistanceMeters: 10,
            minimumOffRouteSamples: 3,
            minimumOffRouteDurationSeconds: 4,
            rerouteCooldownSeconds: cooldown
        )
    }

    private func uptime(_ seconds: UInt64) -> UInt64 {
        seconds * 1_000_000_000
    }

    @Test("one noisy deviation cannot request a reroute")
    func oneNoisyPointCannotReroute() throws {
        var tracker = NavigationRerouteTracker(policy: try policy())

        let update = try tracker.ingest(
            distanceFromRouteMeters: 25,
            receiptUptimeNanoseconds: uptime(1)
        )

        #expect(update.adherence == .suspectedOffRoute(sampleCount: 1))
        #expect(update.recommendation == .none)
    }

    @Test("sample count alone is insufficient without sustained duration")
    func durationThresholdIsRequired() throws {
        var tracker = NavigationRerouteTracker(policy: try policy())

        _ = try tracker.ingest(distanceFromRouteMeters: 25, receiptUptimeNanoseconds: uptime(1))
        _ = try tracker.ingest(distanceFromRouteMeters: 24, receiptUptimeNanoseconds: uptime(2))
        let update = try tracker.ingest(distanceFromRouteMeters: 23, receiptUptimeNanoseconds: uptime(3))

        #expect(update.adherence == .suspectedOffRoute(sampleCount: 3))
        #expect(update.recommendation == .none)
    }

    @Test("sustained accepted deviation requests exactly one reroute")
    func sustainedDeviationRequestsOneReroute() throws {
        var tracker = NavigationRerouteTracker(policy: try policy())

        _ = try tracker.ingest(distanceFromRouteMeters: 25, receiptUptimeNanoseconds: uptime(1))
        _ = try tracker.ingest(distanceFromRouteMeters: 24, receiptUptimeNanoseconds: uptime(3))
        let confirmed = try tracker.ingest(distanceFromRouteMeters: 23, receiptUptimeNanoseconds: uptime(5))
        let repeated = try tracker.ingest(distanceFromRouteMeters: 30, receiptUptimeNanoseconds: uptime(6))

        #expect(confirmed.adherence == .offRoute)
        #expect(confirmed.recommendation == .requestNewRoute)
        #expect(repeated.adherence == .offRoute)
        #expect(repeated.recommendation == .none)
    }

    @Test("hysteresis band does not manufacture another deviation sample")
    func hysteresisBandDoesNotAdvanceEvidence() throws {
        var tracker = NavigationRerouteTracker(policy: try policy())

        _ = try tracker.ingest(distanceFromRouteMeters: 25, receiptUptimeNanoseconds: uptime(1))
        let band = try tracker.ingest(distanceFromRouteMeters: 15, receiptUptimeNanoseconds: uptime(3))
        let secondFar = try tracker.ingest(distanceFromRouteMeters: 25, receiptUptimeNanoseconds: uptime(5))

        #expect(band.adherence == .suspectedOffRoute(sampleCount: 1))
        #expect(secondFar.adherence == .suspectedOffRoute(sampleCount: 2))
        #expect(secondFar.recommendation == .none)
    }

    @Test("hysteresis band cannot turn unknown continuity into on-route truth")
    func unknownBandStaysUnknown() throws {
        var tracker = NavigationRerouteTracker(policy: try policy())

        let update = try tracker.ingest(
            distanceFromRouteMeters: 15,
            receiptUptimeNanoseconds: uptime(1)
        )

        #expect(update.adherence == .unknown)
        #expect(update.recommendation == .none)
    }

    @Test("returning inside the exit threshold clears the episode")
    func returnOnRouteClearsEpisode() throws {
        var tracker = NavigationRerouteTracker(policy: try policy())

        _ = try tracker.ingest(distanceFromRouteMeters: 25, receiptUptimeNanoseconds: uptime(1))
        let onRoute = try tracker.ingest(distanceFromRouteMeters: 10, receiptUptimeNanoseconds: uptime(2))
        let next = try tracker.ingest(distanceFromRouteMeters: 25, receiptUptimeNanoseconds: uptime(3))

        #expect(onRoute.adherence == .onRoute)
        #expect(next.adherence == .suspectedOffRoute(sampleCount: 1))
    }

    @Test("cooldown suppresses a second off-route episode until it expires")
    func cooldownSuppressesSecondEpisode() throws {
        var tracker = NavigationRerouteTracker(policy: try policy(cooldown: 30))

        _ = try tracker.ingest(distanceFromRouteMeters: 25, receiptUptimeNanoseconds: uptime(1))
        _ = try tracker.ingest(distanceFromRouteMeters: 25, receiptUptimeNanoseconds: uptime(3))
        let firstRequest = try tracker.ingest(distanceFromRouteMeters: 25, receiptUptimeNanoseconds: uptime(5))
        #expect(firstRequest.recommendation == .requestNewRoute)
        _ = try tracker.ingest(distanceFromRouteMeters: 5, receiptUptimeNanoseconds: uptime(6))
        _ = try tracker.ingest(distanceFromRouteMeters: 25, receiptUptimeNanoseconds: uptime(10))
        _ = try tracker.ingest(distanceFromRouteMeters: 25, receiptUptimeNanoseconds: uptime(12))
        let suppressed = try tracker.ingest(distanceFromRouteMeters: 25, receiptUptimeNanoseconds: uptime(14))
        let eligibleLater = try tracker.ingest(distanceFromRouteMeters: 25, receiptUptimeNanoseconds: uptime(35))

        #expect(suppressed.adherence == .offRoute)
        #expect(suppressed.recommendation == .none)
        #expect(eligibleLater.recommendation == .requestNewRoute)
    }

    @Test("cooldown exact boundary is eligible")
    func cooldownBoundaryIsInclusive() throws {
        var tracker = NavigationRerouteTracker(policy: try policy(cooldown: 30))

        _ = try tracker.ingest(distanceFromRouteMeters: 25, receiptUptimeNanoseconds: uptime(1))
        _ = try tracker.ingest(distanceFromRouteMeters: 25, receiptUptimeNanoseconds: uptime(3))
        _ = try tracker.ingest(distanceFromRouteMeters: 25, receiptUptimeNanoseconds: uptime(5))
        _ = try tracker.ingest(distanceFromRouteMeters: 5, receiptUptimeNanoseconds: uptime(6))
        _ = try tracker.ingest(distanceFromRouteMeters: 25, receiptUptimeNanoseconds: uptime(29))
        _ = try tracker.ingest(distanceFromRouteMeters: 25, receiptUptimeNanoseconds: uptime(32))
        let confirmed = try tracker.ingest(distanceFromRouteMeters: 25, receiptUptimeNanoseconds: uptime(35))

        #expect(confirmed.recommendation == .requestNewRoute)
    }

    @Test("known continuity interruption discards in-flight deviation evidence without inventing a sample")
    func continuityGapResetsConfidence() throws {
        var tracker = NavigationRerouteTracker(policy: try policy())

        _ = try tracker.ingest(distanceFromRouteMeters: 25, receiptUptimeNanoseconds: uptime(1))
        _ = try tracker.ingest(distanceFromRouteMeters: 25, receiptUptimeNanoseconds: uptime(3))
        let gap = tracker.markContinuityInterrupted()
        let postGap = try tracker.ingest(distanceFromRouteMeters: 25, receiptUptimeNanoseconds: uptime(5))

        #expect(gap.adherence == .unknown)
        #expect(gap.recommendation == .none)
        #expect(postGap.adherence == .suspectedOffRoute(sampleCount: 1))
        #expect(postGap.recommendation == .none)
    }

    @Test("continuity interruption preserves reroute cooldown")
    func continuityGapPreservesCooldown() throws {
        var tracker = NavigationRerouteTracker(policy: try policy(cooldown: 30))

        _ = try tracker.ingest(distanceFromRouteMeters: 25, receiptUptimeNanoseconds: uptime(1))
        _ = try tracker.ingest(distanceFromRouteMeters: 25, receiptUptimeNanoseconds: uptime(3))
        _ = try tracker.ingest(distanceFromRouteMeters: 25, receiptUptimeNanoseconds: uptime(5))
        tracker.markContinuityInterrupted()
        _ = try tracker.ingest(distanceFromRouteMeters: 25, receiptUptimeNanoseconds: uptime(10))
        _ = try tracker.ingest(distanceFromRouteMeters: 25, receiptUptimeNanoseconds: uptime(12))
        let confirmed = try tracker.ingest(distanceFromRouteMeters: 25, receiptUptimeNanoseconds: uptime(14))

        #expect(confirmed.adherence == .offRoute)
        #expect(confirmed.recommendation == .none)
    }

    @Test("replacement route resets adherence without erasing cooldown")
    func replacementRouteResetsAdherence() throws {
        var tracker = NavigationRerouteTracker(policy: try policy(cooldown: 30))

        _ = try tracker.ingest(distanceFromRouteMeters: 25, receiptUptimeNanoseconds: uptime(1))
        _ = try tracker.ingest(distanceFromRouteMeters: 25, receiptUptimeNanoseconds: uptime(3))
        _ = try tracker.ingest(distanceFromRouteMeters: 25, receiptUptimeNanoseconds: uptime(5))
        tracker.markReplacementRouteAccepted()

        #expect(tracker.adherence == .unknown)

        _ = try tracker.ingest(distanceFromRouteMeters: 25, receiptUptimeNanoseconds: uptime(10))
        _ = try tracker.ingest(distanceFromRouteMeters: 25, receiptUptimeNanoseconds: uptime(12))
        let update = try tracker.ingest(distanceFromRouteMeters: 25, receiptUptimeNanoseconds: uptime(14))

        #expect(update.adherence == .offRoute)
        #expect(update.recommendation == .none)
    }

    @Test("equal or backwards uptime cannot double-count one fix and fails atomically")
    func uptimeMustStrictlyIncrease() throws {
        var tracker = NavigationRerouteTracker(policy: try policy())
        _ = try tracker.ingest(distanceFromRouteMeters: 25, receiptUptimeNanoseconds: uptime(10))
        let before = tracker

        #expect(throws: NavigationReroutePolicyError.nonMonotonicReceiptUptime) {
            _ = try tracker.ingest(distanceFromRouteMeters: 25, receiptUptimeNanoseconds: uptime(10))
        }
        #expect(tracker == before)

        #expect(throws: NavigationReroutePolicyError.nonMonotonicReceiptUptime) {
            _ = try tracker.ingest(distanceFromRouteMeters: 25, receiptUptimeNanoseconds: uptime(9))
        }
        #expect(tracker == before)
    }

    @Test("invalid deviation fails atomically")
    func invalidDeviationFailsAtomically() throws {
        var tracker = NavigationRerouteTracker(policy: try policy())
        _ = try tracker.ingest(distanceFromRouteMeters: 5, receiptUptimeNanoseconds: uptime(1))
        let before = tracker

        #expect(throws: NavigationReroutePolicyError.invalidDistanceFromRoute) {
            _ = try tracker.ingest(distanceFromRouteMeters: .nan, receiptUptimeNanoseconds: uptime(2))
        }
        #expect(tracker == before)

        #expect(throws: NavigationReroutePolicyError.invalidDistanceFromRoute) {
            _ = try tracker.ingest(distanceFromRouteMeters: -1, receiptUptimeNanoseconds: uptime(2))
        }
        #expect(tracker == before)
    }

    @Test("policy rejects thresholds that cannot express sustained hysteretic evidence")
    func invalidPolicyIsRejected() {
        #expect(throws: NavigationReroutePolicyError.invalidOffRouteEnterDistance) {
            _ = try NavigationReroutePolicy(
                offRouteEnterDistanceMeters: 0,
                onRouteExitDistanceMeters: 0,
                minimumOffRouteSamples: 3,
                minimumOffRouteDurationSeconds: 4,
                rerouteCooldownSeconds: 30
            )
        }
        #expect(throws: NavigationReroutePolicyError.invalidOnRouteExitDistance) {
            _ = try NavigationReroutePolicy(
                offRouteEnterDistanceMeters: 20,
                onRouteExitDistanceMeters: 20,
                minimumOffRouteSamples: 3,
                minimumOffRouteDurationSeconds: 4,
                rerouteCooldownSeconds: 30
            )
        }
        #expect(throws: NavigationReroutePolicyError.invalidMinimumOffRouteSamples) {
            _ = try NavigationReroutePolicy(
                offRouteEnterDistanceMeters: 20,
                onRouteExitDistanceMeters: 10,
                minimumOffRouteSamples: 1,
                minimumOffRouteDurationSeconds: 4,
                rerouteCooldownSeconds: 30
            )
        }
        #expect(throws: NavigationReroutePolicyError.invalidMinimumOffRouteDuration) {
            _ = try NavigationReroutePolicy(
                offRouteEnterDistanceMeters: 20,
                onRouteExitDistanceMeters: 10,
                minimumOffRouteSamples: 3,
                minimumOffRouteDurationSeconds: .nan,
                rerouteCooldownSeconds: 30
            )
        }
        #expect(throws: NavigationReroutePolicyError.invalidRerouteCooldown) {
            _ = try NavigationReroutePolicy(
                offRouteEnterDistanceMeters: 20,
                onRouteExitDistanceMeters: 10,
                minimumOffRouteSamples: 3,
                minimumOffRouteDurationSeconds: 4,
                rerouteCooldownSeconds: -1
            )
        }
    }
}
