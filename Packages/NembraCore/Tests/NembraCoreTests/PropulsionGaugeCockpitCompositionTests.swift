import Testing
@testable import NembraCore

@Suite("Propulsion gauge cockpit composition")
struct PropulsionGaugeCockpitCompositionTests {
    private func identity(_ suffix: String = "a") throws -> PropulsionGaugeIdentity {
        try PropulsionGaugeIdentity(vehicleID: "cockpit-composition-\(suffix)", modeKey: "sport")
    }

    private func model(
        identity: PropulsionGaugeIdentity,
        rise: UInt64 = 1_000_000_000,
        fall: UInt64 = 500_000_000,
        staleAfter: UInt64 = 3_000_000_000,
        peakHold: UInt64 = 750_000_000
    ) throws -> PropulsionGaugeDisplayModel {
        PropulsionGaugeDisplayModel(
            identity: identity,
            animationPolicy: try PropulsionGaugeAnimationPolicy(
                riseSettlingDurationNanoseconds: rise,
                fallSettlingDurationNanoseconds: fall,
                acceptedPeakHoldNanoseconds: peakHold
            ),
            freshnessPolicy: try PropulsionGaugeFreshnessPolicy(
                staleAfterNanoseconds: staleAfter
            )
        )
    }

    private func simulatorSample(
        identity: PropulsionGaugeIdentity,
        watts: Double,
        sequence: UInt64,
        uptime: UInt64,
        generation: UInt64 = 1
    ) throws -> PropulsionPowerSample {
        try .simulator(
            identity: identity,
            watts: watts,
            receiptSequenceNumber: sequence,
            receivedAtUptimeNanoseconds: uptime,
            continuityGeneration: generation
        )
    }

    private func verifiedSample(
        identity: PropulsionGaugeIdentity,
        watts: Double,
        sequence: UInt64,
        uptime: UInt64,
        generation: UInt64 = 1
    ) throws -> PropulsionPowerSample {
        try .verifiedVehicleMeasurement(
            identity: identity,
            watts: watts,
            receiptSequenceNumber: sequence,
            receivedAtUptimeNanoseconds: uptime,
            continuityGeneration: generation
        )
    }

    private func nearEdgePolicy() throws -> PropulsionObservedScaleRegionPolicy {
        try PropulsionObservedScaleRegionPolicy(nearEdgeFraction: 0.9)
    }

    @Test("one composition keeps accepted near-edge truth ahead of a rising render band")
    func acceptedNearEdgeAndRenderMotionStaySeparate() throws {
        let id = try identity()
        let scale = try PropulsionGaugeScale.simulator(identity: id, ceilingWatts: 1_000)
        var gauge = try model(identity: id)

        try gauge.accept(simulatorSample(
            identity: id,
            watts: 100,
            sequence: 1,
            uptime: 1_000_000_000
        ))
        try gauge.accept(simulatorSample(
            identity: id,
            watts: 950,
            sequence: 2,
            uptime: 2_000_000_000
        ))

        let snapshot = gauge.cockpitCompositionSnapshot(
            atUptimeNanoseconds: 2_000_000_000,
            scale: scale,
            observedScaleRegionPolicy: try nearEdgePolicy()
        )

        guard case let .live(measurement) = snapshot.cockpit.measurement else {
            #expect(Bool(false))
            return
        }

        #expect(measurement.watts == 950)
        #expect(measurement.receiptSequenceNumber == 2)
        #expect(measurement.authority == .simulator)
        #expect(snapshot.cockpit.visualPropulsionFraction == 0.1)
        #expect(snapshot.cockpit.recentAcceptedPeakMarkerFraction == 0.95)
        #expect(snapshot.observedScaleRegion.region == .nearObservedScaleEdge)
        #expect(snapshot.observedScaleRegion.latestAcceptedWatts == 950)
        #expect(snapshot.observedScaleRegion.acceptedObservedScaleFraction == 0.95)
        #expect(snapshot.observedScaleRegion.isSimulatorNearObservedScaleEdge)
        #expect(!snapshot.observedScaleRegion.permitsVerifiedNearObservedMaximumWording)
    }

    @Test("composition is behaviorally identical to the existing standalone projections at one clock")
    func compositionPreservesStandaloneProjectionBehavior() throws {
        let id = try identity()
        let scale = try PropulsionGaugeScale.simulator(identity: id, ceilingWatts: 1_000)
        let policy = try nearEdgePolicy()
        var gauge = try model(identity: id)

        try gauge.accept(simulatorSample(
            identity: id,
            watts: 850,
            sequence: 10,
            uptime: 1_000_000_000
        ))
        try gauge.accept(simulatorSample(
            identity: id,
            watts: 500,
            sequence: 11,
            uptime: 1_100_000_000
        ))

        let now: UInt64 = 1_120_000_000
        let composed = gauge.cockpitCompositionSnapshot(
            atUptimeNanoseconds: now,
            scale: scale,
            observedScaleRegionPolicy: policy
        )

        #expect(composed.cockpit == gauge.cockpitSnapshot(
            atUptimeNanoseconds: now,
            scale: scale
        ))
        #expect(composed.observedScaleRegion == gauge.observedScaleRegionSnapshot(
            atUptimeNanoseconds: now,
            scale: scale,
            policy: policy
        ))
    }

    @Test("retained accepted power keeps its number but loses live motion and near-edge semantics")
    func retainedEvidenceFailsLivePresentationClosed() throws {
        let id = try identity()
        let scale = try PropulsionGaugeScale.simulator(identity: id, ceilingWatts: 1_000)
        var gauge = try model(identity: id, staleAfter: 100)
        try gauge.accept(simulatorSample(
            identity: id,
            watts: 950,
            sequence: 20,
            uptime: 1_000
        ))

        let snapshot = gauge.cockpitCompositionSnapshot(
            atUptimeNanoseconds: 1_101,
            scale: scale,
            observedScaleRegionPolicy: try nearEdgePolicy()
        )

        guard case let .retained(measurement) = snapshot.cockpit.measurement else {
            #expect(Bool(false))
            return
        }

        #expect(measurement.watts == 950)
        #expect(snapshot.cockpit.visualPropulsionFraction == nil)
        #expect(snapshot.cockpit.recentAcceptedPeakMarkerFraction == nil)
        #expect(snapshot.cockpit.scaleOrigin == nil)
        #expect(snapshot.observedScaleRegion.region == .retained)
        #expect(snapshot.observedScaleRegion.latestAcceptedWatts == 950)
        #expect(snapshot.observedScaleRegion.acceptedObservedScaleFraction == nil)
        #expect(!snapshot.observedScaleRegion.isNearObservedScaleEdge)
    }

    @Test("foreign scale preserves accepted watts while withholding every normalized product claim")
    func foreignScaleFailsNormalizedCompositionClosed() throws {
        let id = try identity("target")
        let foreignID = try identity("foreign")
        var gauge = try model(identity: id)
        try gauge.accept(simulatorSample(
            identity: id,
            watts: 950,
            sequence: 30,
            uptime: 1_000
        ))

        let snapshot = gauge.cockpitCompositionSnapshot(
            atUptimeNanoseconds: 1_000,
            scale: try .simulator(identity: foreignID, ceilingWatts: 1_000),
            observedScaleRegionPolicy: try nearEdgePolicy()
        )

        guard case let .live(measurement) = snapshot.cockpit.measurement else {
            #expect(Bool(false))
            return
        }

        #expect(measurement.watts == 950)
        #expect(snapshot.cockpit.visualPropulsionFraction == nil)
        #expect(snapshot.cockpit.recentAcceptedPeakMarkerFraction == nil)
        #expect(snapshot.cockpit.scaleOrigin == nil)
        #expect(snapshot.observedScaleRegion.region == .observedScaleUnavailable)
        #expect(snapshot.observedScaleRegion.latestAcceptedWatts == 950)
        #expect(snapshot.observedScaleRegion.acceptedObservedScaleFraction == nil)
        #expect(snapshot.observedScaleRegion.scaleOrigin == nil)
    }

    @Test("verified wording eligibility remains authority sealed inside the combined snapshot")
    func verifiedWordingGateSurvivesComposition() throws {
        let id = try identity()
        var gauge = try model(identity: id)
        try gauge.accept(verifiedSample(
            identity: id,
            watts: 950,
            sequence: 40,
            uptime: 1_000
        ))

        let snapshot = gauge.cockpitCompositionSnapshot(
            atUptimeNanoseconds: 1_000,
            scale: try .verifiedObservedEnvelope(identity: id, ceilingWatts: 1_000),
            observedScaleRegionPolicy: try nearEdgePolicy()
        )

        guard case let .live(measurement) = snapshot.cockpit.measurement else {
            #expect(Bool(false))
            return
        }

        #expect(measurement.watts == 950)
        #expect(measurement.authority == .verifiedVehicleMeasurement)
        #expect(snapshot.cockpit.scaleOrigin == .verifiedObservedEnvelope)
        #expect(snapshot.observedScaleRegion.region == .nearObservedScaleEdge)
        #expect(snapshot.observedScaleRegion.permitsVerifiedNearObservedMaximumWording)
        #expect(!snapshot.observedScaleRegion.isSimulatorNearObservedScaleEdge)
    }

    @Test("invalid render chronology fails both coupled product projections closed")
    func invalidRenderClockCannotSplitProductTruth() throws {
        let id = try identity()
        var gauge = try model(identity: id)
        try gauge.accept(simulatorSample(
            identity: id,
            watts: 500,
            sequence: 50,
            uptime: 1_000
        ))

        let snapshot = gauge.cockpitCompositionSnapshot(
            atUptimeNanoseconds: 999,
            scale: try .simulator(identity: id, ceilingWatts: 1_000),
            observedScaleRegionPolicy: try nearEdgePolicy()
        )

        #expect(snapshot.cockpit.measurement == .unavailable)
        #expect(snapshot.cockpit.visualPropulsionFraction == nil)
        #expect(snapshot.observedScaleRegion.region == .unavailable)
        #expect(snapshot.observedScaleRegion.latestAcceptedWatts == nil)
        #expect(!snapshot.observedScaleRegion.permitsVerifiedNearObservedMaximumWording)
    }

    @Test("explicit source unavailability cannot retain a numeric or near-edge live surface")
    func explicitUnavailabilityFailsBothSurfacesClosed() throws {
        let id = try identity()
        var gauge = try model(identity: id)
        try gauge.accept(simulatorSample(
            identity: id,
            watts: 950,
            sequence: 60,
            uptime: 1_000
        ))
        gauge.markUnavailable()

        let snapshot = gauge.cockpitCompositionSnapshot(
            atUptimeNanoseconds: 1_010,
            scale: try .simulator(identity: id, ceilingWatts: 1_000),
            observedScaleRegionPolicy: try nearEdgePolicy()
        )

        #expect(snapshot.cockpit.measurement == .unavailable)
        #expect(snapshot.cockpit.visualPropulsionFraction == nil)
        #expect(snapshot.cockpit.recentAcceptedPeakMarkerFraction == nil)
        #expect(snapshot.observedScaleRegion.region == .unavailable)
        #expect(snapshot.observedScaleRegion.latestAcceptedWatts == 950)
        #expect(snapshot.observedScaleRegion.acceptedObservedScaleFraction == nil)
        #expect(!snapshot.observedScaleRegion.isNearObservedScaleEdge)
    }
}