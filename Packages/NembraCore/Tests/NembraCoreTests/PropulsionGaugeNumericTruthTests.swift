import Foundation
import Testing
@testable import NembraCore

@Suite("Propulsion gauge numeric truth")
struct PropulsionGaugeNumericTruthTests {
    private let identity = PropulsionGaugeIdentity(vehicleID: "numeric-es80")

    private func policy() throws -> PropulsionGaugeMotionPolicy {
        try PropulsionGaugeMotionPolicy(
            riseSettlingDurationNanoseconds: 1_000_000_000,
            fallSettlingDurationNanoseconds: 1_000_000_000,
            staleAfterNanoseconds: 2_000_000_000,
            acceptedPeakHoldNanoseconds: 500_000_000
        )
    }

    private func sample(watts: Double, uptime: UInt64) throws -> PropulsionPowerSample {
        try .simulator(
            identity: identity,
            watts: watts,
            receivedAtUptimeNanoseconds: uptime,
            continuityGeneration: 1
        )
    }

    @Test("extreme finite endpoints never manufacture a non-finite display frame")
    func extremeFiniteEndpointsStayFinite() throws {
        var rising = PropulsionGaugeDisplayModel(identity: identity, policy: try policy())
        try rising.accept(sample(watts: 0, uptime: 1_000_000_000))
        try rising.accept(sample(watts: .greatestFiniteMagnitude, uptime: 1_100_000_000))

        let risingFrame = rising.frame(
            atUptimeNanoseconds: 1_600_000_000,
            scale: try .simulator(identity: identity, ceilingWatts: .greatestFiniteMagnitude)
        )
        let risingWatts = try #require(risingFrame.displayWatts)
        #expect(risingWatts.isFinite)
        #expect(risingWatts >= 0)
        #expect(risingWatts <= Double.greatestFiniteMagnitude)
        #expect(risingFrame.normalizedPropulsion?.isFinite == true)

        var falling = PropulsionGaugeDisplayModel(identity: identity, policy: try policy())
        try falling.accept(sample(watts: .greatestFiniteMagnitude, uptime: 1_000_000_000))
        try falling.accept(sample(watts: 0, uptime: 1_100_000_000))

        let fallingFrame = falling.frame(atUptimeNanoseconds: 1_600_000_000, scale: nil)
        let fallingWatts = try #require(fallingFrame.displayWatts)
        #expect(fallingWatts.isFinite)
        #expect(fallingWatts >= 0)
        #expect(fallingWatts <= Double.greatestFiniteMagnitude)
    }

    @Test("normalization clamps a finite observation even when its raw ratio overflows")
    func normalizationRatioOverflowClamps() throws {
        var model = PropulsionGaugeDisplayModel(identity: identity, policy: try policy())
        try model.accept(sample(watts: .greatestFiniteMagnitude, uptime: 1_000))
        let tinyScale = try PropulsionGaugeScale.simulator(
            identity: identity,
            ceilingWatts: .leastNonzeroMagnitude
        )

        let frame = model.frame(atUptimeNanoseconds: 1_000, scale: tinyScale)

        #expect(frame.normalizedPropulsion == 1)
        #expect(frame.acceptedPeakNormalized == 1)
    }
}
