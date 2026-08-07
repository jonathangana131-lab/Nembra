import Testing
@testable import NembraCore

@Suite("Propulsion gauge policy separation")
struct PropulsionGaugePolicySeparationTests {
    private let identity = try! PropulsionGaugeIdentity(vehicleID: "es80-policy-separation")

    private func animation(
        rise: UInt64 = 1_000_000_000,
        fall: UInt64 = 250_000_000,
        peakHold: UInt64 = 500_000_000
    ) throws -> PropulsionGaugeAnimationPolicy {
        try PropulsionGaugeAnimationPolicy(
            riseSettlingDurationNanoseconds: rise,
            fallSettlingDurationNanoseconds: fall,
            acceptedPeakHoldNanoseconds: peakHold
        )
    }

    private func freshness(
        stale: UInt64 = 1_000_000_000
    ) throws -> PropulsionGaugeFreshnessPolicy {
        try PropulsionGaugeFreshnessPolicy(staleAfterNanoseconds: stale)
    }

    private func sample(
        watts: Double,
        uptime: UInt64,
        sequence: UInt64? = nil
    ) throws -> PropulsionPowerSample {
        try .simulator(
            identity: identity,
            watts: watts,
            receiptSequenceNumber: sequence,
            receivedAtUptimeNanoseconds: uptime,
            continuityGeneration: 1
        )
    }

    @Test("freshness policy rejects a zero live interval")
    func freshnessRejectsZeroInterval() {
        #expect(throws: PropulsionGaugeFreshnessPolicyError.invalidStaleInterval) {
            try PropulsionGaugeFreshnessPolicy(staleAfterNanoseconds: 0)
        }
    }

    @Test("animation policy keeps release at least as responsive as application")
    func animationPolicyRejectsSlowRelease() {
        #expect(throws: PropulsionGaugeAnimationPolicyError.fallResponseSlowerThanRise) {
            try PropulsionGaugeAnimationPolicy(
                riseSettlingDurationNanoseconds: 100,
                fallSettlingDurationNanoseconds: 101,
                acceptedPeakHoldNanoseconds: 10
            )
        }
    }

    @Test("Reduce Motion changes rendering without changing measurement freshness")
    func reduceMotionCannotChangeFreshness() throws {
        let currentness = try freshness(stale: 1_000_000_000)
        var animated = PropulsionGaugeDisplayModel(
            identity: identity,
            animationPolicy: try animation(rise: 900_000_000, fall: 200_000_000),
            freshnessPolicy: currentness
        )
        var reducedMotion = PropulsionGaugeDisplayModel(
            identity: identity,
            animationPolicy: try animation(rise: 0, fall: 0),
            freshnessPolicy: currentness
        )

        let first = try sample(watts: 100, uptime: 1_000_000_000)
        let second = try sample(watts: 700, uptime: 1_100_000_000)
        try animated.accept(first)
        try reducedMotion.accept(first)
        try animated.accept(second)
        try reducedMotion.accept(second)

        let animatedLive = animated.frame(atUptimeNanoseconds: 1_500_000_000, scale: nil)
        let reducedLive = reducedMotion.frame(atUptimeNanoseconds: 1_500_000_000, scale: nil)
        #expect(animatedLive.availability == .live)
        #expect(reducedLive.availability == .live)
        #expect(animatedLive.origin == .visuallyInterpolated)
        #expect(reducedLive.origin == .acceptedMeasurement)
        #expect(animatedLive.latestAcceptedWatts == 700)
        #expect(reducedLive.latestAcceptedWatts == 700)

        let animatedRetained = animated.frame(atUptimeNanoseconds: 2_100_000_001, scale: nil)
        let reducedRetained = reducedMotion.frame(atUptimeNanoseconds: 2_100_000_001, scale: nil)
        #expect(animatedRetained.availability == .retained)
        #expect(reducedRetained.availability == .retained)
        #expect(animatedRetained.latestAcceptedWatts == 700)
        #expect(reducedRetained.latestAcceptedWatts == 700)
    }

    @Test("freshness policy decides whether a missing-evidence gap may be visually bridged")
    func freshnessOwnsGapContinuity() throws {
        let slowAnimation = try animation(rise: 2_000_000_000, fall: 200_000_000)

        var shortFreshness = PropulsionGaugeDisplayModel(
            identity: identity,
            animationPolicy: slowAnimation,
            freshnessPolicy: try freshness(stale: 500_000_000)
        )
        try shortFreshness.accept(sample(watts: 100, uptime: 1_000_000_000))
        try shortFreshness.accept(sample(watts: 800, uptime: 1_600_000_000))
        let afterGap = shortFreshness.frame(atUptimeNanoseconds: 1_600_000_000, scale: nil)

        #expect(afterGap.availability == .live)
        #expect(afterGap.origin == .acceptedMeasurement)
        #expect(afterGap.displayWatts == 800)
        #expect(afterGap.latestAcceptedWatts == 800)

        var longFreshness = PropulsionGaugeDisplayModel(
            identity: identity,
            animationPolicy: slowAnimation,
            freshnessPolicy: try freshness(stale: 700_000_000)
        )
        try longFreshness.accept(sample(watts: 100, uptime: 1_000_000_000))
        try longFreshness.accept(sample(watts: 800, uptime: 1_600_000_000))
        let continuous = longFreshness.frame(atUptimeNanoseconds: 1_600_000_000, scale: nil)

        #expect(continuous.availability == .live)
        #expect(continuous.origin == .visuallyInterpolated)
        #expect(continuous.displayWatts == 100)
        #expect(continuous.latestAcceptedWatts == 800)
    }

    @Test("animation tuning cannot extend the accepted measurement live window")
    func longAnimationCannotKeepStaleEvidenceLive() throws {
        var model = PropulsionGaugeDisplayModel(
            identity: identity,
            animationPolicy: try animation(rise: 10_000_000_000, fall: 1_000_000_000),
            freshnessPolicy: try freshness(stale: 250_000_000)
        )
        try model.accept(sample(watts: 500, uptime: 1_000_000_000))

        let frame = model.frame(atUptimeNanoseconds: 1_250_000_001, scale: nil)
        #expect(frame.availability == .retained)
        #expect(frame.origin == .retainedAcceptedMeasurement)
        #expect(frame.displayWatts == 500)
        #expect(frame.latestAcceptedWatts == 500)
    }

    @Test("legacy combined policy preserves its original semantics through the adapter")
    func legacyCombinedPolicyRemainsSourceCompatible() throws {
        let legacy = try PropulsionGaugeMotionPolicy(
            riseSettlingDurationNanoseconds: 1_000_000_000,
            fallSettlingDurationNanoseconds: 250_000_000,
            staleAfterNanoseconds: 400_000_000,
            acceptedPeakHoldNanoseconds: 300_000_000
        )
        var model = PropulsionGaugeDisplayModel(identity: identity, policy: legacy)
        try model.accept(sample(watts: 320, uptime: 1_000_000_000))

        #expect(model.animationPolicy.riseSettlingDurationNanoseconds == legacy.riseSettlingDurationNanoseconds)
        #expect(model.animationPolicy.fallSettlingDurationNanoseconds == legacy.fallSettlingDurationNanoseconds)
        #expect(model.animationPolicy.acceptedPeakHoldNanoseconds == legacy.acceptedPeakHoldNanoseconds)
        #expect(model.freshnessPolicy.staleAfterNanoseconds == legacy.staleAfterNanoseconds)
        #expect(model.policy == legacy)
        #expect(model.frame(atUptimeNanoseconds: 1_400_000_000, scale: nil).availability == .live)
        #expect(model.frame(atUptimeNanoseconds: 1_400_000_001, scale: nil).availability == .retained)
    }
}