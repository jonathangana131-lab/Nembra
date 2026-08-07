import Testing
@testable import NembraCore

@Suite("Propulsion gauge accessibility")
struct PropulsionGaugeAccessibilityTests {
    private let identity = PropulsionGaugeIdentity(vehicleID: "es80-accessibility-test")

    private func motionPolicy(
        rise: UInt64 = 1_000_000_000,
        fall: UInt64 = 250_000_000,
        stale: UInt64 = 2_000_000_000
    ) throws -> PropulsionGaugeMotionPolicy {
        try PropulsionGaugeMotionPolicy(
            riseSettlingDurationNanoseconds: rise,
            fallSettlingDurationNanoseconds: fall,
            staleAfterNanoseconds: stale,
            acceptedPeakHoldNanoseconds: 500_000_000
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
        identity: PropulsionGaugeIdentity? = nil
    ) throws -> PropulsionPowerSample {
        try .verifiedVehicleMeasurement(
            identity: identity ?? self.identity,
            watts: watts,
            receivedAtUptimeNanoseconds: uptime,
            continuityGeneration: 1
        )
    }

    @Test("no accepted measurement is unavailable rather than zero")
    func noMeasurementIsUnavailable() throws {
        let model = PropulsionGaugeDisplayModel(identity: identity, policy: try motionPolicy())

        let snapshot = model.accessibilitySnapshot(
            atUptimeNanoseconds: 1_000,
            scale: try .simulator(identity: identity, ceilingWatts: 1_000)
        )

        #expect(snapshot.availability == .unavailable)
        #expect(snapshot.latestAcceptedWatts == nil)
        #expect(snapshot.latestAcceptedUptimeNanoseconds == nil)
        #expect(snapshot.latestAuthority == nil)
        #expect(snapshot.acceptedObservedScaleFraction == nil)
        #expect(snapshot.scaleOrigin == nil)
    }

    @Test("VoiceOver projection stays on accepted watts while visual power interpolates")
    func interpolationNeverBecomesAccessibilityMeasurement() throws {
        var model = PropulsionGaugeDisplayModel(identity: identity, policy: try motionPolicy())
        let scale = try PropulsionGaugeScale.simulator(identity: identity, ceilingWatts: 1_000)

        try model.accept(simulatorSample(watts: 100, uptime: 1_000_000_000))
        try model.accept(simulatorSample(watts: 500, uptime: 1_100_000_000))

        let visualFrame = model.frame(
            atUptimeNanoseconds: 1_600_000_000,
            scale: scale
        )
        let snapshot = model.accessibilitySnapshot(
            atUptimeNanoseconds: 1_600_000_000,
            scale: scale
        )

        #expect(visualFrame.origin == .visuallyInterpolated)
        #expect((visualFrame.displayWatts ?? 0) > 100)
        #expect((visualFrame.displayWatts ?? 1_000) < 500)
        #expect(snapshot.availability == .live)
        #expect(snapshot.latestAcceptedWatts == 500)
        #expect(snapshot.latestAcceptedUptimeNanoseconds == 1_100_000_000)
        #expect(snapshot.latestAuthority == .simulator)
        #expect(snapshot.acceptedObservedScaleFraction == 0.5)
        #expect(snapshot.scaleOrigin == .simulator)
    }

    @Test("accessibility measurement remains stable across changing display frames")
    func acceptedMeasurementIsStableAcrossDisplayClock() throws {
        var model = PropulsionGaugeDisplayModel(identity: identity, policy: try motionPolicy())
        let scale = try PropulsionGaugeScale.simulator(identity: identity, ceilingWatts: 800)

        try model.accept(simulatorSample(watts: 0, uptime: 1_000_000_000))
        try model.accept(simulatorSample(watts: 600, uptime: 1_100_000_000))

        let earlyVisual = model.frame(atUptimeNanoseconds: 1_250_000_000, scale: scale)
        let lateVisual = model.frame(atUptimeNanoseconds: 1_750_000_000, scale: scale)
        let earlyAccessible = model.accessibilitySnapshot(atUptimeNanoseconds: 1_250_000_000, scale: scale)
        let lateAccessible = model.accessibilitySnapshot(atUptimeNanoseconds: 1_750_000_000, scale: scale)

        #expect(earlyVisual.displayWatts != lateVisual.displayWatts)
        #expect(earlyAccessible.latestAcceptedWatts == 600)
        #expect(lateAccessible.latestAcceptedWatts == 600)
        #expect(earlyAccessible.acceptedObservedScaleFraction == 0.75)
        #expect(lateAccessible.acceptedObservedScaleFraction == 0.75)
    }

    @Test("stale evidence remains retained without a live scale position")
    func staleEvidenceDoesNotExposeLiveScalePosition() throws {
        var model = PropulsionGaugeDisplayModel(
            identity: identity,
            policy: try motionPolicy(stale: 1_000_000_000)
        )
        let scale = try PropulsionGaugeScale.simulator(identity: identity, ceilingWatts: 600)
        try model.accept(simulatorSample(watts: 300, uptime: 1_000_000_000))

        let snapshot = model.accessibilitySnapshot(
            atUptimeNanoseconds: 2_000_000_001,
            scale: scale
        )

        #expect(snapshot.availability == .retained)
        #expect(snapshot.latestAcceptedWatts == 300)
        #expect(snapshot.latestAuthority == .simulator)
        #expect(snapshot.acceptedObservedScaleFraction == nil)
        #expect(snapshot.scaleOrigin == nil)
    }

    @Test("explicit unavailability preserves provenance without manufacturing zero")
    func unavailablePreservesLastAcceptedMeasurement() throws {
        var model = PropulsionGaugeDisplayModel(identity: identity, policy: try motionPolicy())
        try model.accept(simulatorSample(watts: 420, uptime: 1_000_000_000))
        model.markUnavailable()

        let snapshot = model.accessibilitySnapshot(
            atUptimeNanoseconds: 1_100_000_000,
            scale: try .simulator(identity: identity, ceilingWatts: 600)
        )

        #expect(snapshot.availability == .unavailable)
        #expect(snapshot.latestAcceptedWatts == 420)
        #expect(snapshot.latestAcceptedUptimeNanoseconds == 1_000_000_000)
        #expect(snapshot.latestAuthority == .simulator)
        #expect(snapshot.acceptedObservedScaleFraction == nil)
        #expect(snapshot.scaleOrigin == nil)
    }

    @Test("foreign vehicle scale cannot create an accessibility percentage")
    func foreignIdentityScaleFailsClosed() throws {
        var model = PropulsionGaugeDisplayModel(identity: identity, policy: try motionPolicy())
        try model.accept(simulatorSample(watts: 250, uptime: 1_000))

        let foreignIdentity = PropulsionGaugeIdentity(vehicleID: "different-es80")
        let snapshot = model.accessibilitySnapshot(
            atUptimeNanoseconds: 1_000,
            scale: try .simulator(identity: foreignIdentity, ceilingWatts: 500)
        )

        #expect(snapshot.availability == .live)
        #expect(snapshot.latestAcceptedWatts == 250)
        #expect(snapshot.acceptedObservedScaleFraction == nil)
        #expect(snapshot.scaleOrigin == nil)
    }

    @Test("simulator and verified authority never cross accessibility scale domains")
    func authorityDomainsDoNotCross() throws {
        var simulatorModel = PropulsionGaugeDisplayModel(identity: identity, policy: try motionPolicy())
        try simulatorModel.accept(simulatorSample(watts: 250, uptime: 1_000))
        let simulatorWithVerifiedScale = simulatorModel.accessibilitySnapshot(
            atUptimeNanoseconds: 1_000,
            scale: try .verifiedObservedEnvelope(identity: identity, ceilingWatts: 500)
        )

        var verifiedModel = PropulsionGaugeDisplayModel(identity: identity, policy: try motionPolicy())
        try verifiedModel.accept(verifiedSample(watts: 250, uptime: 1_000))
        let verifiedWithSimulatorScale = verifiedModel.accessibilitySnapshot(
            atUptimeNanoseconds: 1_000,
            scale: try .simulator(identity: identity, ceilingWatts: 500)
        )

        #expect(simulatorWithVerifiedScale.latestAcceptedWatts == 250)
        #expect(simulatorWithVerifiedScale.acceptedObservedScaleFraction == nil)
        #expect(simulatorWithVerifiedScale.scaleOrigin == nil)
        #expect(verifiedWithSimulatorScale.latestAcceptedWatts == 250)
        #expect(verifiedWithSimulatorScale.acceptedObservedScaleFraction == nil)
        #expect(verifiedWithSimulatorScale.scaleOrigin == nil)
    }

    @Test("verified evidence may expose only its compatible observed scale position")
    func verifiedEvidenceUsesVerifiedObservedEnvelope() throws {
        var model = PropulsionGaugeDisplayModel(identity: identity, policy: try motionPolicy())
        try model.accept(verifiedSample(watts: 250, uptime: 1_000))

        let snapshot = model.accessibilitySnapshot(
            atUptimeNanoseconds: 1_000,
            scale: try .verifiedObservedEnvelope(identity: identity, ceilingWatts: 500)
        )

        #expect(snapshot.availability == .live)
        #expect(snapshot.latestAcceptedWatts == 250)
        #expect(snapshot.latestAuthority == .verifiedVehicleMeasurement)
        #expect(snapshot.acceptedObservedScaleFraction == 0.5)
        #expect(snapshot.scaleOrigin == .verifiedObservedEnvelope)
    }

    @Test("accepted output above the observed presentation ceiling clamps without changing watts")
    func observedScaleFractionClampsWithoutChangingMeasurement() throws {
        var model = PropulsionGaugeDisplayModel(identity: identity, policy: try motionPolicy())
        try model.accept(simulatorSample(watts: 750, uptime: 1_000))

        let snapshot = model.accessibilitySnapshot(
            atUptimeNanoseconds: 1_000,
            scale: try .simulator(identity: identity, ceilingWatts: 500)
        )

        #expect(snapshot.latestAcceptedWatts == 750)
        #expect(snapshot.acceptedObservedScaleFraction == 1)
        #expect(snapshot.scaleOrigin == .simulator)
    }
}
