import Foundation
import Testing
@testable import NembraCore

@Suite("Propulsion gauge presentation")
struct PropulsionGaugePresentationTests {
    private let identity = PropulsionGaugeIdentity(vehicleID: "es80-test")

    private func motionPolicy(
        rise: UInt64 = 1_000_000_000,
        fall: UInt64 = 250_000_000,
        stale: UInt64 = 2_000_000_000,
        peakHold: UInt64 = 500_000_000
    ) throws -> PropulsionGaugeMotionPolicy {
        try PropulsionGaugeMotionPolicy(
            riseSettlingDurationNanoseconds: rise,
            fallSettlingDurationNanoseconds: fall,
            staleAfterNanoseconds: stale,
            acceptedPeakHoldNanoseconds: peakHold
        )
    }

    private func simulatorSample(
        watts: Double,
        uptime: UInt64,
        generation: UInt64 = 1,
        identity: PropulsionGaugeIdentity? = nil
    ) throws -> PropulsionPowerSample {
        try .simulator(
            identity: identity ?? self.identity,
            watts: watts,
            receivedAtUptimeNanoseconds: uptime,
            continuityGeneration: generation
        )
    }

    private func verifiedSample(
        watts: Double,
        uptime: UInt64,
        generation: UInt64 = 1,
        identity: PropulsionGaugeIdentity? = nil
    ) throws -> PropulsionPowerSample {
        try .verifiedVehicleMeasurement(
            identity: identity ?? self.identity,
            watts: watts,
            receivedAtUptimeNanoseconds: uptime,
            continuityGeneration: generation
        )
    }

    private func simulatorScale(
        ceilingWatts: Double,
        identity: PropulsionGaugeIdentity? = nil
    ) throws -> PropulsionGaugeScale {
        try .simulator(
            identity: identity ?? self.identity,
            ceilingWatts: ceilingWatts
        )
    }

    private func verifiedScale(
        ceilingWatts: Double,
        identity: PropulsionGaugeIdentity? = nil
    ) throws -> PropulsionGaugeScale {
        try .verifiedObservedEnvelope(
            identity: identity ?? self.identity,
            ceilingWatts: ceilingWatts
        )
    }

    @Test("invalid propulsion samples fail closed")
    func invalidSamplesFailClosed() {
        #expect(throws: PropulsionPowerSampleError.invalidWatts) {
            try PropulsionPowerSample.simulator(
                identity: identity,
                watts: -1,
                receivedAtUptimeNanoseconds: 1,
                continuityGeneration: 1
            )
        }
        #expect(throws: PropulsionPowerSampleError.invalidWatts) {
            try PropulsionPowerSample.simulator(
                identity: identity,
                watts: .infinity,
                receivedAtUptimeNanoseconds: 1,
                continuityGeneration: 1
            )
        }
        #expect(throws: PropulsionPowerSampleError.invalidWatts) {
            try PropulsionPowerSample.simulator(
                identity: identity,
                watts: .nan,
                receivedAtUptimeNanoseconds: 1,
                continuityGeneration: 1
            )
        }
    }

    @Test("no measurement is unavailable rather than fake zero")
    func noMeasurementIsUnavailable() throws {
        let model = PropulsionGaugeDisplayModel(identity: identity, policy: try motionPolicy())
        let frame = model.frame(atUptimeNanoseconds: 1_000, scale: nil)

        #expect(frame.availability == .unavailable)
        #expect(frame.origin == .unavailable)
        #expect(frame.displayWatts == nil)
        #expect(frame.latestAcceptedWatts == nil)
        #expect(frame.normalizedPropulsion == nil)
    }

    @Test("display clock interpolates without becoming accepted measurement evidence")
    func displayClockStaysSeparateFromMeasurementClock() throws {
        var model = PropulsionGaugeDisplayModel(identity: identity, policy: try motionPolicy())
        let scale = try simulatorScale(ceilingWatts: 1_000)

        try model.accept(simulatorSample(watts: 100, uptime: 1_000_000_000))
        try model.accept(simulatorSample(watts: 500, uptime: 1_100_000_000))

        let immediate = model.frame(atUptimeNanoseconds: 1_100_000_000, scale: scale)
        let midpoint = model.frame(atUptimeNanoseconds: 1_600_000_000, scale: scale)
        let settled = model.frame(atUptimeNanoseconds: 2_100_000_000, scale: scale)

        #expect(immediate.origin == .visuallyInterpolated)
        #expect(immediate.displayWatts == 100)
        #expect(immediate.latestAcceptedWatts == 500)
        #expect(midpoint.origin == .visuallyInterpolated)
        #expect((midpoint.displayWatts ?? 0) > 100)
        #expect((midpoint.displayWatts ?? 1_000) < 500)
        #expect(midpoint.latestAcceptedWatts == 500)
        #expect(settled.origin == .acceptedMeasurement)
        #expect(settled.displayWatts == 500)
        #expect(settled.latestAcceptedWatts == 500)
    }

    @Test("retargeting starts from the current render value without a jump")
    func retargetIsContinuous() throws {
        var model = PropulsionGaugeDisplayModel(identity: identity, policy: try motionPolicy())
        try model.accept(simulatorSample(watts: 0, uptime: 1_000_000_000))
        try model.accept(simulatorSample(watts: 800, uptime: 1_100_000_000))

        let before = model.frame(atUptimeNanoseconds: 1_350_000_000, scale: nil)
        try model.accept(simulatorSample(watts: 300, uptime: 1_350_000_000))
        let after = model.frame(atUptimeNanoseconds: 1_350_000_000, scale: nil)

        #expect(before.displayWatts != nil)
        #expect(after.displayWatts == before.displayWatts)
        #expect(after.latestAcceptedWatts == 300)
        #expect(after.origin == .visuallyInterpolated)
    }

    @Test("fall response can be more responsive than power application")
    func fallCanRespondFasterThanRise() throws {
        let policy = try motionPolicy(rise: 1_000_000_000, fall: 200_000_000)

        var rising = PropulsionGaugeDisplayModel(identity: identity, policy: policy)
        try rising.accept(simulatorSample(watts: 0, uptime: 1_000_000_000))
        try rising.accept(simulatorSample(watts: 1_000, uptime: 1_100_000_000))
        let risingAt100ms = rising.frame(atUptimeNanoseconds: 1_200_000_000, scale: nil).displayWatts ?? 0

        var falling = PropulsionGaugeDisplayModel(identity: identity, policy: policy)
        try falling.accept(simulatorSample(watts: 1_000, uptime: 1_000_000_000))
        try falling.accept(simulatorSample(watts: 0, uptime: 1_100_000_000))
        let fallingAt100ms = falling.frame(atUptimeNanoseconds: 1_200_000_000, scale: nil).displayWatts ?? 1_000

        #expect(risingAt100ms < 500)
        #expect(fallingAt100ms < 500)
    }

    @Test("stale evidence retains the accepted number but removes active gauge motion")
    func staleEvidenceStopsActiveGauge() throws {
        var model = PropulsionGaugeDisplayModel(identity: identity, policy: try motionPolicy(stale: 1_000_000_000))
        let scale = try simulatorScale(ceilingWatts: 600)
        try model.accept(simulatorSample(watts: 300, uptime: 1_000_000_000))

        let frame = model.frame(atUptimeNanoseconds: 2_000_000_001, scale: scale)

        #expect(frame.availability == .retained)
        #expect(frame.origin == .retainedAcceptedMeasurement)
        #expect(frame.displayWatts == 300)
        #expect(frame.latestAcceptedWatts == 300)
        #expect(frame.normalizedPropulsion == nil)
        #expect(frame.acceptedPeakNormalized == nil)
        #expect(frame.scaleOrigin == nil)
    }

    @Test("explicit unavailability never becomes measured zero")
    func disconnectDoesNotManufactureZero() throws {
        var model = PropulsionGaugeDisplayModel(identity: identity, policy: try motionPolicy())
        try model.accept(simulatorSample(watts: 420, uptime: 1_000_000_000))
        model.markUnavailable()

        let frame = model.frame(atUptimeNanoseconds: 1_100_000_000, scale: nil)

        #expect(frame.availability == .unavailable)
        #expect(frame.origin == .unavailable)
        #expect(frame.displayWatts == nil)
        #expect(frame.latestAcceptedWatts == 420)
    }

    @Test("new continuity generation snaps to new evidence instead of bridging a gap")
    func continuityGenerationDoesNotBridgeUnknownInterval() throws {
        var model = PropulsionGaugeDisplayModel(identity: identity, policy: try motionPolicy())
        try model.accept(simulatorSample(watts: 100, uptime: 1_000_000_000, generation: 1))
        try model.accept(simulatorSample(watts: 700, uptime: 1_100_000_000, generation: 2))

        let frame = model.frame(atUptimeNanoseconds: 1_100_000_000, scale: nil)

        #expect(frame.origin == .acceptedMeasurement)
        #expect(frame.displayWatts == 700)
        #expect(frame.latestAcceptedWatts == 700)
    }

    @Test("stale generation and replayed receipt time reject")
    func chronologyFailsClosed() throws {
        var model = PropulsionGaugeDisplayModel(identity: identity, policy: try motionPolicy())
        try model.accept(simulatorSample(watts: 100, uptime: 1_000, generation: 2))

        #expect(throws: PropulsionGaugeDisplayError.staleContinuityGeneration) {
            try model.accept(simulatorSample(watts: 200, uptime: 2_000, generation: 1))
        }
        #expect(throws: PropulsionGaugeDisplayError.nonMonotonicMeasurement) {
            try model.accept(simulatorSample(watts: 200, uptime: 1_000, generation: 2))
        }
    }

    @Test("accepted peak marker comes from measurements rather than interpolated display frames")
    func peakHoldUsesAcceptedMeasurements() throws {
        var model = PropulsionGaugeDisplayModel(identity: identity, policy: try motionPolicy(peakHold: 400_000_000))
        let scale = try simulatorScale(ceilingWatts: 1_000)
        try model.accept(simulatorSample(watts: 100, uptime: 1_000_000_000))
        try model.accept(simulatorSample(watts: 800, uptime: 1_100_000_000))

        let immediate = model.frame(atUptimeNanoseconds: 1_100_000_000, scale: scale)
        let expired = model.frame(atUptimeNanoseconds: 1_500_000_001, scale: scale)

        #expect(immediate.displayWatts == 100)
        #expect(immediate.normalizedPropulsion == 0.1)
        #expect(immediate.acceptedPeakNormalized == 0.8)
        #expect(expired.acceptedPeakNormalized == nil)
    }

    @Test("scale authority cannot cross simulator and verified evidence")
    func scaleAuthorityDoesNotCrossEvidenceDomains() throws {
        let verifiedEnvelopeScale = try verifiedScale(ceilingWatts: 500)

        var simulatorModel = PropulsionGaugeDisplayModel(identity: identity, policy: try motionPolicy())
        try simulatorModel.accept(simulatorSample(watts: 250, uptime: 1_000))
        let simulatorWithVerifiedScale = simulatorModel.frame(
            atUptimeNanoseconds: 1_000,
            scale: verifiedEnvelopeScale
        )

        var verifiedModel = PropulsionGaugeDisplayModel(identity: identity, policy: try motionPolicy())
        try verifiedModel.accept(verifiedSample(watts: 250, uptime: 1_000))
        let verifiedWithSimulatorScale = verifiedModel.frame(
            atUptimeNanoseconds: 1_000,
            scale: try simulatorScale(ceilingWatts: 500)
        )

        #expect(simulatorWithVerifiedScale.normalizedPropulsion == nil)
        #expect(simulatorWithVerifiedScale.scaleOrigin == nil)
        #expect(verifiedWithSimulatorScale.normalizedPropulsion == nil)
        #expect(verifiedWithSimulatorScale.scaleOrigin == nil)
    }

    @Test("verified envelope scale normalizes only verified measurement presentation")
    func verifiedEnvelopeScaleMatchesVerifiedMeasurement() throws {
        var model = PropulsionGaugeDisplayModel(identity: identity, policy: try motionPolicy())
        try model.accept(verifiedSample(watts: 250, uptime: 1_000))

        let frame = model.frame(
            atUptimeNanoseconds: 1_000,
            scale: try verifiedScale(ceilingWatts: 500)
        )

        #expect(frame.normalizedPropulsion == 0.5)
        #expect(frame.acceptedPeakNormalized == 0.5)
        #expect(frame.scaleOrigin == .verifiedObservedEnvelope)
        #expect(frame.latestAcceptedWatts == 250)
    }

    @Test("visual scale cannot cross vehicle identity even within one authority domain")
    func scaleCannotCrossVehicleIdentity() throws {
        let otherIdentity = PropulsionGaugeIdentity(vehicleID: "another-es80")
        let foreignScale = try simulatorScale(ceilingWatts: 500, identity: otherIdentity)
        var model = PropulsionGaugeDisplayModel(identity: identity, policy: try motionPolicy())
        try model.accept(simulatorSample(watts: 250, uptime: 1_000))

        let frame = model.frame(atUptimeNanoseconds: 1_000, scale: foreignScale)

        #expect(foreignScale.identity == otherIdentity)
        #expect(frame.normalizedPropulsion == nil)
        #expect(frame.acceptedPeakNormalized == nil)
        #expect(frame.scaleOrigin == nil)
    }

    @Test("verified envelope scale preserves exact vehicle and mode identity")
    func verifiedScalePreservesCalibrationIdentity() throws {
        let sportIdentity = PropulsionGaugeIdentity(vehicleID: "es80-test", modeKey: "confirmed-sport")
        let scale = try verifiedScale(ceilingWatts: 500, identity: sportIdentity)

        #expect(scale.identity == sportIdentity)
        #expect(scale.ceilingWatts == 500)
        #expect(scale.origin == .verifiedObservedEnvelope)
    }
}
