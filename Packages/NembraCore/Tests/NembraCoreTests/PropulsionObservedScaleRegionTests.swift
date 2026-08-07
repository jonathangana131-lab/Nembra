import Testing
@testable import NembraCore

@Suite("Propulsion observed scale region")
struct PropulsionObservedScaleRegionTests {
    private func identity(_ suffix: String = "a") throws -> PropulsionGaugeIdentity {
        try PropulsionGaugeIdentity(vehicleID: "sim-es80-\(suffix)", modeKey: "sport")
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
                acceptedPeakHoldNanoseconds: 500_000_000
            ),
            freshnessPolicy: try PropulsionGaugeFreshnessPolicy(
                staleAfterNanoseconds: staleAfter
            )
        )
    }

    private func sample(
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

    @Test("near-edge threshold is a finite positive fraction no greater than one")
    func policyValidation() throws {
        #expect(throws: PropulsionObservedScaleRegionPolicyError.invalidNearEdgeFraction) {
            _ = try PropulsionObservedScaleRegionPolicy(nearEdgeFraction: 0)
        }
        #expect(throws: PropulsionObservedScaleRegionPolicyError.invalidNearEdgeFraction) {
            _ = try PropulsionObservedScaleRegionPolicy(nearEdgeFraction: 1.01)
        }
        #expect(throws: PropulsionObservedScaleRegionPolicyError.invalidNearEdgeFraction) {
            _ = try PropulsionObservedScaleRegionPolicy(nearEdgeFraction: .nan)
        }
        #expect(try PropulsionObservedScaleRegionPolicy(nearEdgeFraction: 0.9).nearEdgeFraction == 0.9)
    }

    @Test("accepted high power enters near-edge semantics before render interpolation catches up")
    func acceptedMeasurementDrivesNearEdgeImmediately() throws {
        let id = try identity()
        let scale = try PropulsionGaugeScale.simulator(identity: id, ceilingWatts: 1_000)
        let policy = try PropulsionObservedScaleRegionPolicy(nearEdgeFraction: 0.9)
        var gauge = try model(identity: id)

        try gauge.accept(sample(identity: id, watts: 100, sequence: 1, uptime: 1_000_000_000))
        try gauge.accept(sample(identity: id, watts: 950, sequence: 2, uptime: 2_000_000_000))

        let frame = gauge.frame(atUptimeNanoseconds: 2_000_000_000, scale: scale)
        #expect(frame.origin == .visuallyInterpolated)
        #expect(frame.displayWatts == 100)

        let region = gauge.observedScaleRegionSnapshot(
            atUptimeNanoseconds: 2_000_000_000,
            scale: scale,
            policy: policy
        )
        #expect(region.region == .nearObservedScaleEdge)
        #expect(region.latestAcceptedWatts == 950)
        #expect(region.acceptedObservedScaleFraction == 0.95)
        #expect(region.scaleOrigin == .simulator)
        #expect(region.isSimulatorNearObservedScaleEdge)
        #expect(!region.permitsVerifiedNearObservedMaximumWording)
    }

    @Test("verified near-edge wording requires verified measurement and observed-envelope scale")
    func verifiedWordingGateIsAuthoritySealed() throws {
        let id = try identity()
        let policy = try PropulsionObservedScaleRegionPolicy(nearEdgeFraction: 0.9)
        var gauge = try model(identity: id)
        try gauge.accept(verifiedSample(
            identity: id,
            watts: 950,
            sequence: 1,
            uptime: 1_000
        ))

        let verified = gauge.observedScaleRegionSnapshot(
            atUptimeNanoseconds: 1_000,
            scale: try .verifiedObservedEnvelope(identity: id, ceilingWatts: 1_000),
            policy: policy
        )
        #expect(verified.region == .nearObservedScaleEdge)
        #expect(verified.latestAuthority == .verifiedVehicleMeasurement)
        #expect(verified.scaleOrigin == .verifiedObservedEnvelope)
        #expect(verified.permitsVerifiedNearObservedMaximumWording)
        #expect(!verified.isSimulatorNearObservedScaleEdge)

        let wrongScaleAuthority = gauge.observedScaleRegionSnapshot(
            atUptimeNanoseconds: 1_000,
            scale: try .simulator(identity: id, ceilingWatts: 1_000),
            policy: policy
        )
        #expect(wrongScaleAuthority.region == .observedScaleUnavailable)
        #expect(!wrongScaleAuthority.permitsVerifiedNearObservedMaximumWording)
    }

    @Test("interpolated high tail cannot keep near-edge semantics after accepted power falls")
    func interpolatedTailCannotMasqueradeAsNearEdge() throws {
        let id = try identity()
        let scale = try PropulsionGaugeScale.simulator(identity: id, ceilingWatts: 1_000)
        let policy = try PropulsionObservedScaleRegionPolicy(nearEdgeFraction: 0.9)
        var gauge = try model(identity: id)

        try gauge.accept(sample(identity: id, watts: 950, sequence: 1, uptime: 1_000_000_000))
        try gauge.accept(sample(identity: id, watts: 100, sequence: 2, uptime: 2_000_000_000))

        let frame = gauge.frame(atUptimeNanoseconds: 2_000_000_000, scale: scale)
        #expect(frame.origin == .visuallyInterpolated)
        #expect(frame.displayWatts == 950)

        let region = gauge.observedScaleRegionSnapshot(
            atUptimeNanoseconds: 2_000_000_000,
            scale: scale,
            policy: policy
        )
        #expect(region.region == .normal)
        #expect(region.latestAcceptedWatts == 100)
        #expect(region.acceptedObservedScaleFraction == 0.1)
        #expect(!region.permitsVerifiedNearObservedMaximumWording)
    }

    @Test("freshness policy expires near-edge truth independently from slow animation tuning")
    func freshnessIndependentFromAnimation() throws {
        let id = try identity()
        let scale = try PropulsionGaugeScale.simulator(identity: id, ceilingWatts: 1_000)
        let policy = try PropulsionObservedScaleRegionPolicy(nearEdgeFraction: 0.9)
        var gauge = try model(
            identity: id,
            rise: 2_000_000_000,
            fall: 2_000_000_000,
            staleAfter: 100
        )
        try gauge.accept(sample(identity: id, watts: 950, sequence: 1, uptime: 1_000))

        let live = gauge.observedScaleRegionSnapshot(
            atUptimeNanoseconds: 1_100,
            scale: scale,
            policy: policy
        )
        #expect(live.region == .nearObservedScaleEdge)
        #expect(live.isSimulatorNearObservedScaleEdge)

        let retained = gauge.observedScaleRegionSnapshot(
            atUptimeNanoseconds: 1_101,
            scale: scale,
            policy: policy
        )
        #expect(retained.region == .retained)
        #expect(retained.latestAcceptedWatts == 950)
        #expect(retained.acceptedObservedScaleFraction == nil)
        #expect(!retained.isSimulatorNearObservedScaleEdge)
        #expect(!retained.permitsVerifiedNearObservedMaximumWording)
    }

    @Test("incompatible or absent scale keeps live accepted watts but withholds observed-region semantics")
    func incompatibleScaleFailsRegionClosed() throws {
        let id = try identity("a")
        let foreign = try identity("b")
        let foreignScale = try PropulsionGaugeScale.simulator(identity: foreign, ceilingWatts: 1_000)
        let policy = try PropulsionObservedScaleRegionPolicy(nearEdgeFraction: 0.9)
        var gauge = try model(identity: id)
        try gauge.accept(sample(identity: id, watts: 950, sequence: 1, uptime: 1_000_000_000))

        for scale in [nil, foreignScale] as [PropulsionGaugeScale?] {
            let region = gauge.observedScaleRegionSnapshot(
                atUptimeNanoseconds: 1_000_000_000,
                scale: scale,
                policy: policy
            )
            #expect(region.availability == .live)
            #expect(region.region == .observedScaleUnavailable)
            #expect(region.latestAcceptedWatts == 950)
            #expect(region.acceptedObservedScaleFraction == nil)
            #expect(region.scaleOrigin == nil)
            #expect(!region.isSimulatorNearObservedScaleEdge)
            #expect(!region.permitsVerifiedNearObservedMaximumWording)
        }
    }

    @Test("explicit unavailable evidence never keeps near-edge state")
    func unavailableFailsClosed() throws {
        let id = try identity()
        let scale = try PropulsionGaugeScale.simulator(identity: id, ceilingWatts: 1_000)
        let policy = try PropulsionObservedScaleRegionPolicy(nearEdgeFraction: 0.9)
        var gauge = try model(identity: id)
        try gauge.accept(sample(identity: id, watts: 950, sequence: 1, uptime: 1_000))

        gauge.markUnavailable()
        let unavailable = gauge.observedScaleRegionSnapshot(
            atUptimeNanoseconds: 1_000,
            scale: scale,
            policy: policy
        )
        #expect(unavailable.region == .unavailable)
        #expect(unavailable.latestAcceptedWatts == 950)
        #expect(unavailable.acceptedObservedScaleFraction == nil)
        #expect(!unavailable.isSimulatorNearObservedScaleEdge)
        #expect(!unavailable.permitsVerifiedNearObservedMaximumWording)
    }

    @Test("threshold comparison is inclusive and remains presentation-only")
    func thresholdIsInclusive() throws {
        let id = try identity()
        let scale = try PropulsionGaugeScale.simulator(identity: id, ceilingWatts: 1_000)
        let policy = try PropulsionObservedScaleRegionPolicy(nearEdgeFraction: 0.9)
        var gauge = try model(identity: id)
        try gauge.accept(sample(identity: id, watts: 900, sequence: 1, uptime: 1_000))

        let region = gauge.observedScaleRegionSnapshot(
            atUptimeNanoseconds: 1_000,
            scale: scale,
            policy: policy
        )
        #expect(region.region == .nearObservedScaleEdge)
        #expect(region.isNearObservedScaleEdge)
        #expect(region.isSimulatorNearObservedScaleEdge)
        #expect(!region.permitsVerifiedNearObservedMaximumWording)
        #expect(region.acceptedObservedScaleFraction == 0.9)
    }
}
