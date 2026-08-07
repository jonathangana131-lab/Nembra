import Testing
@testable import NembraCore

@Suite("Propulsion gauge accessibility")
struct PropulsionGaugeAccessibilityTests {
    private func makeIdentity(
        vehicleID: String = "es80-accessibility-test",
        modeKey: String? = nil
    ) throws -> PropulsionGaugeIdentity {
        try PropulsionGaugeIdentity(vehicleID: vehicleID, modeKey: modeKey)
    }

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
        identity: PropulsionGaugeIdentity,
        watts: Double,
        receipt: UInt64? = nil,
        uptime: UInt64,
        generation: UInt64 = 1
    ) throws -> PropulsionPowerSample {
        try .simulator(
            identity: identity,
            watts: watts,
            receiptSequenceNumber: receipt,
            receivedAtUptimeNanoseconds: uptime,
            continuityGeneration: generation
        )
    }

    private func verifiedSample(
        identity: PropulsionGaugeIdentity,
        watts: Double,
        receipt: UInt64,
        uptime: UInt64,
        generation: UInt64 = 1
    ) throws -> PropulsionPowerSample {
        try .verifiedVehicleMeasurement(
            identity: identity,
            watts: watts,
            receiptSequenceNumber: receipt,
            receivedAtUptimeNanoseconds: uptime,
            continuityGeneration: generation
        )
    }

    @Test("no accepted measurement is unavailable rather than zero")
    func noMeasurementIsUnavailable() throws {
        let identity = try makeIdentity()
        let model = PropulsionGaugeDisplayModel(identity: identity, policy: try motionPolicy())

        let snapshot = model.accessibilitySnapshot(
            atUptimeNanoseconds: 1_000,
            scale: try .simulator(identity: identity, ceilingWatts: 1_000)
        )

        #expect(snapshot.availability == .unavailable)
        #expect(snapshot.latestAcceptedWatts == nil)
        #expect(snapshot.latestAcceptedReceiptSequenceNumber == nil)
        #expect(snapshot.latestAcceptedUptimeNanoseconds == nil)
        #expect(snapshot.latestAuthority == nil)
        #expect(snapshot.acceptedObservedScaleFraction == nil)
        #expect(snapshot.scaleOrigin == nil)
    }

    @Test("VoiceOver projection stays on accepted watts while visual power interpolates")
    func interpolationNeverBecomesAccessibilityMeasurement() throws {
        let identity = try makeIdentity()
        var model = PropulsionGaugeDisplayModel(identity: identity, policy: try motionPolicy())
        let scale = try PropulsionGaugeScale.simulator(identity: identity, ceilingWatts: 1_000)

        try model.accept(simulatorSample(identity: identity, watts: 100, receipt: 10, uptime: 1_000_000_000))
        try model.accept(simulatorSample(identity: identity, watts: 500, receipt: 11, uptime: 1_100_000_000))

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
        #expect(snapshot.latestAcceptedReceiptSequenceNumber == 11)
        #expect(snapshot.latestAcceptedUptimeNanoseconds == 1_100_000_000)
        #expect(snapshot.latestAuthority == .simulator)
        #expect(snapshot.acceptedObservedScaleFraction == 0.5)
        #expect(snapshot.scaleOrigin == .simulator)
    }

    @Test("accessibility measurement remains stable across changing display frames")
    func acceptedMeasurementIsStableAcrossDisplayClock() throws {
        let identity = try makeIdentity()
        var model = PropulsionGaugeDisplayModel(identity: identity, policy: try motionPolicy())
        let scale = try PropulsionGaugeScale.simulator(identity: identity, ceilingWatts: 800)

        try model.accept(simulatorSample(identity: identity, watts: 0, receipt: 20, uptime: 1_000_000_000))
        try model.accept(simulatorSample(identity: identity, watts: 600, receipt: 21, uptime: 1_100_000_000))

        let earlyVisual = model.frame(atUptimeNanoseconds: 1_250_000_000, scale: scale)
        let lateVisual = model.frame(atUptimeNanoseconds: 1_750_000_000, scale: scale)
        let earlyAccessible = model.accessibilitySnapshot(atUptimeNanoseconds: 1_250_000_000, scale: scale)
        let lateAccessible = model.accessibilitySnapshot(atUptimeNanoseconds: 1_750_000_000, scale: scale)

        #expect(earlyVisual.displayWatts != lateVisual.displayWatts)
        #expect(earlyAccessible.latestAcceptedWatts == 600)
        #expect(lateAccessible.latestAcceptedWatts == 600)
        #expect(earlyAccessible.latestAcceptedReceiptSequenceNumber == 21)
        #expect(lateAccessible.latestAcceptedReceiptSequenceNumber == 21)
        #expect(earlyAccessible.acceptedObservedScaleFraction == 0.75)
        #expect(lateAccessible.acceptedObservedScaleFraction == 0.75)
    }

    @Test("stale evidence remains retained without a live scale position")
    func staleEvidenceDoesNotExposeLiveScalePosition() throws {
        let identity = try makeIdentity()
        var model = PropulsionGaugeDisplayModel(
            identity: identity,
            policy: try motionPolicy(stale: 1_000_000_000)
        )
        let scale = try PropulsionGaugeScale.simulator(identity: identity, ceilingWatts: 600)
        try model.accept(simulatorSample(identity: identity, watts: 300, receipt: 30, uptime: 1_000_000_000))

        let snapshot = model.accessibilitySnapshot(
            atUptimeNanoseconds: 2_000_000_001,
            scale: scale
        )

        #expect(snapshot.availability == .retained)
        #expect(snapshot.latestAcceptedWatts == 300)
        #expect(snapshot.latestAcceptedReceiptSequenceNumber == 30)
        #expect(snapshot.latestAuthority == .simulator)
        #expect(snapshot.acceptedObservedScaleFraction == nil)
        #expect(snapshot.scaleOrigin == nil)
    }

    @Test("explicit unavailability preserves accepted provenance without manufacturing zero")
    func unavailablePreservesLastAcceptedMeasurement() throws {
        let identity = try makeIdentity()
        var model = PropulsionGaugeDisplayModel(identity: identity, policy: try motionPolicy())
        try model.accept(simulatorSample(identity: identity, watts: 420, receipt: 40, uptime: 1_000_000_000))
        model.markUnavailable()

        let snapshot = model.accessibilitySnapshot(
            atUptimeNanoseconds: 1_100_000_000,
            scale: try .simulator(identity: identity, ceilingWatts: 600)
        )

        #expect(snapshot.availability == .unavailable)
        #expect(snapshot.latestAcceptedWatts == 420)
        #expect(snapshot.latestAcceptedReceiptSequenceNumber == 40)
        #expect(snapshot.latestAcceptedUptimeNanoseconds == 1_000_000_000)
        #expect(snapshot.latestAuthority == .simulator)
        #expect(snapshot.acceptedObservedScaleFraction == nil)
        #expect(snapshot.scaleOrigin == nil)
    }

    @Test("render clock before accepted receipt cannot expose future evidence")
    func backwardsRenderClockFailsClosed() throws {
        let identity = try makeIdentity()
        var model = PropulsionGaugeDisplayModel(identity: identity, policy: try motionPolicy())
        try model.accept(simulatorSample(identity: identity, watts: 350, receipt: 50, uptime: 1_000))

        let snapshot = model.accessibilitySnapshot(
            atUptimeNanoseconds: 999,
            scale: try .simulator(identity: identity, ceilingWatts: 500)
        )

        #expect(snapshot.availability == .unavailable)
        #expect(snapshot.latestAcceptedWatts == nil)
        #expect(snapshot.latestAcceptedReceiptSequenceNumber == nil)
        #expect(snapshot.latestAcceptedUptimeNanoseconds == nil)
        #expect(snapshot.latestAuthority == nil)
        #expect(snapshot.acceptedObservedScaleFraction == nil)
        #expect(snapshot.scaleOrigin == nil)
    }

    @Test("newer accepted receipt replaces accessibility provenance even at equal uptime")
    func receiptChronologyRemainsVisible() throws {
        let identity = try makeIdentity()
        var model = PropulsionGaugeDisplayModel(identity: identity, policy: try motionPolicy())
        let scale = try PropulsionGaugeScale.simulator(identity: identity, ceilingWatts: 1_000)

        try model.accept(simulatorSample(identity: identity, watts: 200, receipt: 60, uptime: 1_000))
        try model.accept(simulatorSample(identity: identity, watts: 450, receipt: 61, uptime: 1_000))

        let snapshot = model.accessibilitySnapshot(atUptimeNanoseconds: 1_000, scale: scale)

        #expect(snapshot.latestAcceptedWatts == 450)
        #expect(snapshot.latestAcceptedReceiptSequenceNumber == 61)
        #expect(snapshot.latestAcceptedUptimeNanoseconds == 1_000)
        #expect(snapshot.acceptedObservedScaleFraction == 0.45)
    }

    @Test("foreign vehicle scale cannot create an accessibility percentage")
    func foreignIdentityScaleFailsClosed() throws {
        let identity = try makeIdentity()
        var model = PropulsionGaugeDisplayModel(identity: identity, policy: try motionPolicy())
        try model.accept(simulatorSample(identity: identity, watts: 250, receipt: 70, uptime: 1_000))

        let foreignIdentity = try makeIdentity(vehicleID: "different-es80")
        let snapshot = model.accessibilitySnapshot(
            atUptimeNanoseconds: 1_000,
            scale: try .simulator(identity: foreignIdentity, ceilingWatts: 500)
        )

        #expect(snapshot.availability == .live)
        #expect(snapshot.latestAcceptedWatts == 250)
        #expect(snapshot.latestAcceptedReceiptSequenceNumber == 70)
        #expect(snapshot.acceptedObservedScaleFraction == nil)
        #expect(snapshot.scaleOrigin == nil)
    }

    @Test("mode-scoped scale cannot normalize a different confirmed mode")
    func foreignModeScaleFailsClosed() throws {
        let sportIdentity = try makeIdentity(modeKey: "sport")
        let ecoIdentity = try makeIdentity(modeKey: "eco")
        var model = PropulsionGaugeDisplayModel(identity: sportIdentity, policy: try motionPolicy())
        try model.accept(simulatorSample(identity: sportIdentity, watts: 300, receipt: 80, uptime: 1_000))

        let snapshot = model.accessibilitySnapshot(
            atUptimeNanoseconds: 1_000,
            scale: try .simulator(identity: ecoIdentity, ceilingWatts: 600)
        )

        #expect(snapshot.latestAcceptedWatts == 300)
        #expect(snapshot.acceptedObservedScaleFraction == nil)
        #expect(snapshot.scaleOrigin == nil)
    }

    @Test("simulator and verified authority never cross accessibility scale domains")
    func authorityDomainsDoNotCross() throws {
        let identity = try makeIdentity()
        var simulatorModel = PropulsionGaugeDisplayModel(identity: identity, policy: try motionPolicy())
        try simulatorModel.accept(simulatorSample(identity: identity, watts: 250, receipt: 90, uptime: 1_000))
        let simulatorWithVerifiedScale = simulatorModel.accessibilitySnapshot(
            atUptimeNanoseconds: 1_000,
            scale: try .verifiedObservedEnvelope(identity: identity, ceilingWatts: 500)
        )

        var verifiedModel = PropulsionGaugeDisplayModel(identity: identity, policy: try motionPolicy())
        try verifiedModel.accept(verifiedSample(identity: identity, watts: 250, receipt: 91, uptime: 1_000))
        let verifiedWithSimulatorScale = verifiedModel.accessibilitySnapshot(
            atUptimeNanoseconds: 1_000,
            scale: try .simulator(identity: identity, ceilingWatts: 500)
        )

        #expect(simulatorWithVerifiedScale.latestAcceptedWatts == 250)
        #expect(simulatorWithVerifiedScale.acceptedObservedScaleFraction == nil)
        #expect(simulatorWithVerifiedScale.scaleOrigin == nil)
        #expect(verifiedWithSimulatorScale.latestAcceptedWatts == 250)
        #expect(verifiedWithSimulatorScale.latestAcceptedReceiptSequenceNumber == 91)
        #expect(verifiedWithSimulatorScale.acceptedObservedScaleFraction == nil)
        #expect(verifiedWithSimulatorScale.scaleOrigin == nil)
    }

    @Test("verified evidence may expose only its compatible observed scale position")
    func verifiedEvidenceUsesVerifiedObservedEnvelope() throws {
        let identity = try makeIdentity()
        var model = PropulsionGaugeDisplayModel(identity: identity, policy: try motionPolicy())
        try model.accept(verifiedSample(identity: identity, watts: 250, receipt: 100, uptime: 1_000))

        let snapshot = model.accessibilitySnapshot(
            atUptimeNanoseconds: 1_000,
            scale: try .verifiedObservedEnvelope(identity: identity, ceilingWatts: 500)
        )

        #expect(snapshot.availability == .live)
        #expect(snapshot.latestAcceptedWatts == 250)
        #expect(snapshot.latestAcceptedReceiptSequenceNumber == 100)
        #expect(snapshot.latestAuthority == .verifiedVehicleMeasurement)
        #expect(snapshot.acceptedObservedScaleFraction == 0.5)
        #expect(snapshot.scaleOrigin == .verifiedObservedEnvelope)
    }

    @Test("accepted output above the observed presentation ceiling clamps without changing watts")
    func observedScaleFractionClampsWithoutChangingMeasurement() throws {
        let identity = try makeIdentity()
        var model = PropulsionGaugeDisplayModel(identity: identity, policy: try motionPolicy())
        try model.accept(simulatorSample(identity: identity, watts: 750, receipt: 110, uptime: 1_000))

        let snapshot = model.accessibilitySnapshot(
            atUptimeNanoseconds: 1_000,
            scale: try .simulator(identity: identity, ceilingWatts: 500)
        )

        #expect(snapshot.latestAcceptedWatts == 750)
        #expect(snapshot.latestAcceptedReceiptSequenceNumber == 110)
        #expect(snapshot.acceptedObservedScaleFraction == 1)
        #expect(snapshot.scaleOrigin == .simulator)
    }
}
