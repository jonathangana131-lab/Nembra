import Testing
@testable import NembraCore

@Suite("Propulsion gauge cockpit projection")
struct PropulsionGaugeCockpitProjectionTests {
    private func makeIdentity(
        vehicleID: String = "es80-cockpit-test",
        modeKey: String? = nil
    ) throws -> PropulsionGaugeIdentity {
        try PropulsionGaugeIdentity(vehicleID: vehicleID, modeKey: modeKey)
    }

    private func motionPolicy(
        rise: UInt64 = 1_000_000_000,
        fall: UInt64 = 500_000_000,
        stale: UInt64 = 2_000_000_000,
        peakHold: UInt64 = 750_000_000
    ) throws -> PropulsionGaugeMotionPolicy {
        try PropulsionGaugeMotionPolicy(
            riseSettlingDurationNanoseconds: rise,
            fallSettlingDurationNanoseconds: fall,
            staleAfterNanoseconds: stale,
            acceptedPeakHoldNanoseconds: peakHold
        )
    }

    private func simulatorSample(
        identity: PropulsionGaugeIdentity,
        watts: Double,
        receipt: UInt64,
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

    @Test("no accepted measurement keeps every cockpit power surface unavailable")
    func noMeasurementIsUnavailable() throws {
        let identity = try makeIdentity()
        let model = PropulsionGaugeDisplayModel(identity: identity, policy: try motionPolicy())

        let snapshot = model.cockpitSnapshot(
            atUptimeNanoseconds: 1_000,
            scale: try .simulator(identity: identity, ceilingWatts: 1_000)
        )

        #expect(snapshot.measurement == .unavailable)
        #expect(snapshot.visualPropulsionFraction == nil)
        #expect(snapshot.recentAcceptedPeakMarkerFraction == nil)
        #expect(snapshot.scaleOrigin == nil)
    }

    @Test("numeric cockpit power stays accepted while the live band interpolates")
    func interpolatedBandNeverBecomesNumericMeasurement() throws {
        let identity = try makeIdentity()
        var model = PropulsionGaugeDisplayModel(identity: identity, policy: try motionPolicy())
        let scale = try PropulsionGaugeScale.simulator(identity: identity, ceilingWatts: 1_000)

        try model.accept(simulatorSample(identity: identity, watts: 100, receipt: 10, uptime: 1_000_000_000))
        try model.accept(simulatorSample(identity: identity, watts: 800, receipt: 11, uptime: 1_100_000_000))

        let snapshot = model.cockpitSnapshot(
            atUptimeNanoseconds: 1_300_000_000,
            scale: scale
        )

        guard case let .live(measurement) = snapshot.measurement else {
            #expect(Bool(false))
            return
        }

        #expect(measurement.watts == 800)
        #expect(measurement.receiptSequenceNumber == 11)
        #expect(measurement.receivedAtUptimeNanoseconds == 1_100_000_000)
        #expect(measurement.authority == .simulator)
        #expect(snapshot.visualPropulsionFraction != nil)
        #expect((snapshot.visualPropulsionFraction ?? 0) < 0.8)
        #expect(snapshot.scaleOrigin == .simulator)
    }

    @Test("falling render motion and a held accepted peak stay separate from numeric power")
    func fallingMotionKeepsMeasurementAndPeakDistinct() throws {
        let identity = try makeIdentity()
        var model = PropulsionGaugeDisplayModel(identity: identity, policy: try motionPolicy())
        let scale = try PropulsionGaugeScale.simulator(identity: identity, ceilingWatts: 1_000)

        try model.accept(simulatorSample(identity: identity, watts: 950, receipt: 20, uptime: 1_000_000_000))
        try model.accept(simulatorSample(identity: identity, watts: 600, receipt: 21, uptime: 1_100_000_000))

        let snapshot = model.cockpitSnapshot(
            atUptimeNanoseconds: 1_110_000_000,
            scale: scale
        )

        guard case let .live(measurement) = snapshot.measurement else {
            #expect(Bool(false))
            return
        }

        #expect(measurement.watts == 600)
        #expect((snapshot.visualPropulsionFraction ?? 0) > 0.9)
        #expect(snapshot.recentAcceptedPeakMarkerFraction == 0.95)
        #expect(snapshot.scaleOrigin == .simulator)
    }

    @Test("accepted watts above the learned presentation ceiling remain unclamped numeric evidence")
    func acceptedWattsRemainUnclampedAbovePresentationScale() throws {
        let identity = try makeIdentity()
        var model = PropulsionGaugeDisplayModel(identity: identity, policy: try motionPolicy())
        try model.accept(verifiedSample(identity: identity, watts: 1_200, receipt: 30, uptime: 1_000))

        let snapshot = model.cockpitSnapshot(
            atUptimeNanoseconds: 1_000,
            scale: try .verifiedObservedEnvelope(identity: identity, ceilingWatts: 1_000)
        )

        guard case let .live(measurement) = snapshot.measurement else {
            #expect(Bool(false))
            return
        }

        #expect(measurement.watts == 1_200)
        #expect(snapshot.visualPropulsionFraction == 1)
        #expect(snapshot.recentAcceptedPeakMarkerFraction == 1)
        #expect(snapshot.scaleOrigin == .verifiedObservedEnvelope)
    }

    @Test("stale evidence becomes a typed retained measurement and stops live gauge motion")
    func staleEvidenceIsRetainedNotLive() throws {
        let identity = try makeIdentity()
        var model = PropulsionGaugeDisplayModel(
            identity: identity,
            policy: try motionPolicy(stale: 1_000_000_000)
        )
        try model.accept(simulatorSample(identity: identity, watts: 700, receipt: 40, uptime: 1_000_000_000))

        let snapshot = model.cockpitSnapshot(
            atUptimeNanoseconds: 2_000_000_001,
            scale: try .simulator(identity: identity, ceilingWatts: 800)
        )

        guard case let .retained(measurement) = snapshot.measurement else {
            #expect(Bool(false))
            return
        }

        #expect(measurement.watts == 700)
        #expect(measurement.receiptSequenceNumber == 40)
        #expect(snapshot.visualPropulsionFraction == nil)
        #expect(snapshot.recentAcceptedPeakMarkerFraction == nil)
        #expect(snapshot.scaleOrigin == nil)
    }

    @Test("explicit interruption hides the primary numeric power instead of manufacturing zero")
    func explicitUnavailabilityHidesPrimaryNumericPower() throws {
        let identity = try makeIdentity()
        var model = PropulsionGaugeDisplayModel(identity: identity, policy: try motionPolicy())
        try model.accept(simulatorSample(identity: identity, watts: 420, receipt: 50, uptime: 1_000))
        model.markUnavailable()

        let snapshot = model.cockpitSnapshot(
            atUptimeNanoseconds: 1_100,
            scale: try .simulator(identity: identity, ceilingWatts: 600)
        )

        #expect(snapshot.measurement == .unavailable)
        #expect(snapshot.visualPropulsionFraction == nil)
        #expect(snapshot.recentAcceptedPeakMarkerFraction == nil)
        #expect(snapshot.scaleOrigin == nil)
    }

    @Test("foreign scale keeps accepted watts but removes normalized cockpit presentation")
    func foreignScaleFailsClosed() throws {
        let identity = try makeIdentity()
        let foreignIdentity = try makeIdentity(vehicleID: "different-es80")
        var model = PropulsionGaugeDisplayModel(identity: identity, policy: try motionPolicy())
        try model.accept(simulatorSample(identity: identity, watts: 500, receipt: 60, uptime: 1_000))

        let snapshot = model.cockpitSnapshot(
            atUptimeNanoseconds: 1_000,
            scale: try .simulator(identity: foreignIdentity, ceilingWatts: 800)
        )

        guard case let .live(measurement) = snapshot.measurement else {
            #expect(Bool(false))
            return
        }

        #expect(measurement.watts == 500)
        #expect(snapshot.visualPropulsionFraction == nil)
        #expect(snapshot.recentAcceptedPeakMarkerFraction == nil)
        #expect(snapshot.scaleOrigin == nil)
    }

    @Test("simulator measurement cannot use a verified observed-envelope scale")
    func authorityDomainsDoNotCross() throws {
        let identity = try makeIdentity()
        var model = PropulsionGaugeDisplayModel(identity: identity, policy: try motionPolicy())
        try model.accept(simulatorSample(identity: identity, watts: 950, receipt: 70, uptime: 1_000))

        let snapshot = model.cockpitSnapshot(
            atUptimeNanoseconds: 1_000,
            scale: try .verifiedObservedEnvelope(identity: identity, ceilingWatts: 1_000)
        )

        guard case let .live(measurement) = snapshot.measurement else {
            #expect(Bool(false))
            return
        }

        #expect(measurement.watts == 950)
        #expect(measurement.authority == .simulator)
        #expect(snapshot.visualPropulsionFraction == nil)
        #expect(snapshot.recentAcceptedPeakMarkerFraction == nil)
        #expect(snapshot.scaleOrigin == nil)
    }

    @Test("render clock before the latest accepted receipt fails the cockpit closed")
    func backwardsRenderClockFailsClosed() throws {
        let identity = try makeIdentity()
        var model = PropulsionGaugeDisplayModel(identity: identity, policy: try motionPolicy())
        try model.accept(simulatorSample(identity: identity, watts: 500, receipt: 80, uptime: 1_000))

        let snapshot = model.cockpitSnapshot(
            atUptimeNanoseconds: 999,
            scale: try .simulator(identity: identity, ceilingWatts: 800)
        )

        #expect(snapshot.measurement == .unavailable)
        #expect(snapshot.visualPropulsionFraction == nil)
        #expect(snapshot.recentAcceptedPeakMarkerFraction == nil)
        #expect(snapshot.scaleOrigin == nil)
    }
}
