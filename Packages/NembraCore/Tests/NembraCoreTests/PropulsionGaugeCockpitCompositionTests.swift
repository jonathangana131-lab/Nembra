import Testing
@testable import NembraCore

@Suite("Propulsion gauge cockpit composition")
struct PropulsionGaugeCockpitCompositionTests {
    private func identity(
        vehicleID: String = "es80-cockpit-composition",
        modeKey: String? = "sport"
    ) throws -> PropulsionGaugeIdentity {
        try PropulsionGaugeIdentity(vehicleID: vehicleID, modeKey: modeKey)
    }

    private func model(
        identity: PropulsionGaugeIdentity,
        rise: UInt64 = 1_000_000_000,
        fall: UInt64 = 500_000_000,
        staleAfter: UInt64 = 3_000_000_000
    ) throws -> PropulsionGaugeDisplayModel {
        PropulsionGaugeDisplayModel(
            identity: identity,
            animationPolicy: try PropulsionGaugeAnimationPolicy(
                riseSettlingDurationNanoseconds: rise,
                fallSettlingDurationNanoseconds: fall,
                acceptedPeakHoldNanoseconds: 750_000_000
            ),
            freshnessPolicy: try PropulsionGaugeFreshnessPolicy(
                staleAfterNanoseconds: staleAfter
            )
        )
    }

    private func simulatorSample(
        identity: PropulsionGaugeIdentity,
        watts: Double,
        receipt: UInt64,
        uptime: UInt64
    ) throws -> PropulsionPowerSample {
        try .simulator(
            identity: identity,
            watts: watts,
            receiptSequenceNumber: receipt,
            receivedAtUptimeNanoseconds: uptime,
            continuityGeneration: 1
        )
    }

    private func verifiedSample(
        identity: PropulsionGaugeIdentity,
        watts: Double,
        receipt: UInt64,
        uptime: UInt64
    ) throws -> PropulsionPowerSample {
        try .verifiedVehicleMeasurement(
            identity: identity,
            watts: watts,
            receiptSequenceNumber: receipt,
            receivedAtUptimeNanoseconds: uptime,
            continuityGeneration: 1
        )
    }

    private func policy() throws -> PropulsionObservedScaleRegionPolicy {
        try PropulsionObservedScaleRegionPolicy(nearEdgeFraction: 0.9)
    }

    @Test("one cockpit cut keeps interpolated motion separate from accepted near-edge truth")
    func acceptedNearEdgeDoesNotWaitForRenderMotion() throws {
        let id = try identity()
        let scale = try PropulsionGaugeScale.simulator(
            identity: id,
            ceilingWatts: 1_000
        )
        var gauge = try model(identity: id)
        try gauge.accept(simulatorSample(
            identity: id,
            watts: 100,
            receipt: 1,
            uptime: 1_000_000_000
        ))
        try gauge.accept(simulatorSample(
            identity: id,
            watts: 950,
            receipt: 2,
            uptime: 2_000_000_000
        ))

        let snapshot = gauge.cockpitPresentationSnapshot(
            atUptimeNanoseconds: 2_000_000_000,
            scale: scale,
            observedScalePolicy: try policy()
        )

        guard case let .live(measurement) = snapshot.cockpit.measurement else {
            #expect(Bool(false))
            return
        }

        #expect(measurement.watts == 950)
        #expect(measurement.receiptSequenceNumber == 2)
        #expect(snapshot.cockpit.visualPropulsionFraction == 0.1)
        #expect(snapshot.accessibility.latestAcceptedWatts == 950)
        #expect(snapshot.accessibility.latestAcceptedReceiptSequenceNumber == 2)
        #expect(snapshot.accessibility.acceptedObservedScaleFraction == 0.95)
        #expect(snapshot.observedScaleRegion.region == .nearObservedScaleEdge)
        #expect(snapshot.observedScaleRegion.latestAcceptedReceiptSequenceNumber == 2)
        #expect(snapshot.observedScaleRegion.isSimulatorNearObservedScaleEdge)
        #expect(!snapshot.observedScaleRegion.permitsVerifiedNearObservedMaximumWording)
    }

    @Test("verified near-observed-max wording stays authority sealed in the composed handoff")
    func verifiedWordingRemainsSealed() throws {
        let id = try identity()
        var gauge = try model(identity: id)
        try gauge.accept(verifiedSample(
            identity: id,
            watts: 950,
            receipt: 10,
            uptime: 1_000
        ))

        let snapshot = gauge.cockpitPresentationSnapshot(
            atUptimeNanoseconds: 1_000,
            scale: try .verifiedObservedEnvelope(
                identity: id,
                ceilingWatts: 1_000
            ),
            observedScalePolicy: try policy()
        )

        guard case let .live(measurement) = snapshot.cockpit.measurement else {
            #expect(Bool(false))
            return
        }

        #expect(measurement.authority == .verifiedVehicleMeasurement)
        #expect(snapshot.accessibility.latestAuthority == .verifiedVehicleMeasurement)
        #expect(snapshot.observedScaleRegion.scaleOrigin == .verifiedObservedEnvelope)
        #expect(snapshot.observedScaleRegion.permitsVerifiedNearObservedMaximumWording)
        #expect(!snapshot.observedScaleRegion.isSimulatorNearObservedScaleEdge)
    }

    @Test("falling render tail cannot preserve near-edge semantics after accepted power falls")
    func fallingRenderTailCannotMasqueradeAsNearEdge() throws {
        let id = try identity()
        let scale = try PropulsionGaugeScale.simulator(
            identity: id,
            ceilingWatts: 1_000
        )
        var gauge = try model(identity: id)
        try gauge.accept(simulatorSample(
            identity: id,
            watts: 950,
            receipt: 20,
            uptime: 1_000_000_000
        ))
        try gauge.accept(simulatorSample(
            identity: id,
            watts: 100,
            receipt: 21,
            uptime: 2_000_000_000
        ))

        let snapshot = gauge.cockpitPresentationSnapshot(
            atUptimeNanoseconds: 2_000_000_000,
            scale: scale,
            observedScalePolicy: try policy()
        )

        guard case let .live(measurement) = snapshot.cockpit.measurement else {
            #expect(Bool(false))
            return
        }

        #expect(measurement.watts == 100)
        #expect(snapshot.cockpit.visualPropulsionFraction == 0.95)
        #expect(snapshot.accessibility.acceptedObservedScaleFraction == 0.1)
        #expect(snapshot.observedScaleRegion.region == .normal)
        #expect(!snapshot.observedScaleRegion.isNearObservedScaleEdge)
    }

    @Test("stale accepted power remains retained while every live normalized surface turns off")
    func retainedPowerCannotLookLive() throws {
        let id = try identity()
        var gauge = try model(
            identity: id,
            staleAfter: 100
        )
        try gauge.accept(simulatorSample(
            identity: id,
            watts: 900,
            receipt: 30,
            uptime: 1_000
        ))

        let snapshot = gauge.cockpitPresentationSnapshot(
            atUptimeNanoseconds: 1_101,
            scale: try .simulator(identity: id, ceilingWatts: 1_000),
            observedScalePolicy: try policy()
        )

        guard case let .retained(measurement) = snapshot.cockpit.measurement else {
            #expect(Bool(false))
            return
        }

        #expect(measurement.watts == 900)
        #expect(snapshot.cockpit.visualPropulsionFraction == nil)
        #expect(snapshot.cockpit.recentAcceptedPeakMarkerFraction == nil)
        #expect(snapshot.accessibility.availability == .retained)
        #expect(snapshot.accessibility.latestAcceptedWatts == 900)
        #expect(snapshot.accessibility.acceptedObservedScaleFraction == nil)
        #expect(snapshot.observedScaleRegion.region == .retained)
        #expect(!snapshot.observedScaleRegion.permitsVerifiedNearObservedMaximumWording)
    }

    @Test("foreign scale preserves accepted watts but withholds every normalized claim")
    func foreignScaleFailsNormalizedPresentationClosed() throws {
        let id = try identity(vehicleID: "es80-a")
        let foreign = try identity(vehicleID: "es80-b")
        var gauge = try model(identity: id)
        try gauge.accept(simulatorSample(
            identity: id,
            watts: 700,
            receipt: 40,
            uptime: 1_000
        ))

        let snapshot = gauge.cockpitPresentationSnapshot(
            atUptimeNanoseconds: 1_000,
            scale: try .simulator(identity: foreign, ceilingWatts: 1_000),
            observedScalePolicy: try policy()
        )

        guard case let .live(measurement) = snapshot.cockpit.measurement else {
            #expect(Bool(false))
            return
        }

        #expect(measurement.watts == 700)
        #expect(snapshot.cockpit.visualPropulsionFraction == nil)
        #expect(snapshot.cockpit.scaleOrigin == nil)
        #expect(snapshot.accessibility.latestAcceptedWatts == 700)
        #expect(snapshot.accessibility.acceptedObservedScaleFraction == nil)
        #expect(snapshot.accessibility.scaleOrigin == nil)
        #expect(snapshot.observedScaleRegion.region == .observedScaleUnavailable)
        #expect(snapshot.observedScaleRegion.scaleOrigin == nil)
    }

    @Test("explicit interruption never manufactures zero or leaves live cockpit motion")
    func interruptionFailsPrimaryCockpitClosed() throws {
        let id = try identity()
        var gauge = try model(identity: id)
        try gauge.accept(simulatorSample(
            identity: id,
            watts: 880,
            receipt: 50,
            uptime: 1_000
        ))
        gauge.markUnavailable()

        let snapshot = gauge.cockpitPresentationSnapshot(
            atUptimeNanoseconds: 1_100,
            scale: try .simulator(identity: id, ceilingWatts: 1_000),
            observedScalePolicy: try policy()
        )

        #expect(snapshot.cockpit.measurement == .unavailable)
        #expect(snapshot.cockpit.visualPropulsionFraction == nil)
        #expect(snapshot.cockpit.recentAcceptedPeakMarkerFraction == nil)
        #expect(snapshot.accessibility.availability == .unavailable)
        #expect(snapshot.accessibility.latestAcceptedWatts == 880)
        #expect(snapshot.accessibility.acceptedObservedScaleFraction == nil)
        #expect(snapshot.observedScaleRegion.region == .unavailable)
        #expect(!snapshot.observedScaleRegion.isNearObservedScaleEdge)
    }

    @Test("composed projection stays behaviorally identical to the three standalone projections")
    func compositionMatchesStandaloneContracts() throws {
        let id = try identity()
        let scale = try PropulsionGaugeScale.simulator(
            identity: id,
            ceilingWatts: 1_000
        )
        let regionPolicy = try policy()
        var gauge = try model(identity: id)
        try gauge.accept(simulatorSample(
            identity: id,
            watts: 640,
            receipt: 60,
            uptime: 1_000
        ))

        let composed = gauge.cockpitPresentationSnapshot(
            atUptimeNanoseconds: 1_250,
            scale: scale,
            observedScalePolicy: regionPolicy
        )

        #expect(composed.cockpit == gauge.cockpitSnapshot(
            atUptimeNanoseconds: 1_250,
            scale: scale
        ))
        #expect(composed.accessibility == gauge.accessibilitySnapshot(
            atUptimeNanoseconds: 1_250,
            scale: scale
        ))
        #expect(composed.observedScaleRegion == gauge.observedScaleRegionSnapshot(
            atUptimeNanoseconds: 1_250,
            scale: scale,
            policy: regionPolicy
        ))
    }
}