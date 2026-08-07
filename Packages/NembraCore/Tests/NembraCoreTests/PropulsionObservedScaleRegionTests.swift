import Testing
@testable import NembraCore

@Suite("Propulsion observed scale region")
struct PropulsionObservedScaleRegionTests {
    private func identity(_ suffix: String = "a") throws -> PropulsionGaugeIdentity {
        try PropulsionGaugeIdentity(vehicleID: "sim-es80-\(suffix)", modeKey: "sport")
    }

    private func motionPolicy(staleAfter: UInt64 = 3_000_000_000) throws -> PropulsionGaugeMotionPolicy {
        try PropulsionGaugeMotionPolicy(
            riseSettlingDurationNanoseconds: 1_000_000_000,
            fallSettlingDurationNanoseconds: 500_000_000,
            staleAfterNanoseconds: staleAfter,
            acceptedPeakHoldNanoseconds: 500_000_000
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

    @Test("near-edge threshold must be a finite positive fraction no greater than one")
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

    @Test("accepted measurement enters near-edge semantics before render interpolation catches up")
    func acceptedMeasurementDrivesNearEdgeImmediately() throws {
        let id = try identity()
        let scale = try PropulsionGaugeScale.simulator(identity: id, ceilingWatts: 1_000)
        let policy = try PropulsionObservedScaleRegionPolicy(nearEdgeFraction: 0.9)
        var model = PropulsionGaugeDisplayModel(identity: id, policy: try motionPolicy())

        try model.accept(sample(identity: id, watts: 100, sequence: 1, uptime: 1_000_000_000))
        try model.accept(sample(identity: id, watts: 950, sequence: 2, uptime: 2_000_000_000))

        let frame = model.frame(atUptimeNanoseconds: 2_000_000_000, scale: scale)
        #expect(frame.origin == .visuallyInterpolated)
        #expect(frame.displayWatts == 100)

        let region = model.observedScaleRegionSnapshot(
            atUptimeNanoseconds: 2_000_000_000,
            scale: scale,
            policy: policy
        )
        #expect(region.region == .nearObservedScaleEdge)
        #expect(region.latestAcceptedWatts == 950)
        #expect(region.acceptedObservedScaleFraction == 0.95)
        #expect(region.scaleOrigin == .simulator)
    }

    @Test("render-only high power cannot keep near-edge semantics after accepted power falls")
    func interpolatedTailCannotMasqueradeAsNearEdge() throws {
        let id = try identity()
        let scale = try PropulsionGaugeScale.simulator(identity: id, ceilingWatts: 1_000)
        let policy = try PropulsionObservedScaleRegionPolicy(nearEdgeFraction: 0.9)
        var model = PropulsionGaugeDisplayModel(identity: id, policy: try motionPolicy())

        try model.accept(sample(identity: id, watts: 950, sequence: 1, uptime: 1_000_000_000))
        try model.accept(sample(identity: id, watts: 100, sequence: 2, uptime: 2_000_000_000))

        let frame = model.frame(atUptimeNanoseconds: 2_000_000_000, scale: scale)
        #expect(frame.origin == .visuallyInterpolated)
        #expect(frame.displayWatts == 950)

        let region = model.observedScaleRegionSnapshot(
            atUptimeNanoseconds: 2_000_000_000,
            scale: scale,
            policy: policy
        )
        #expect(region.region == .normal)
        #expect(region.latestAcceptedWatts == 100)
        #expect(region.acceptedObservedScaleFraction == 0.1)
    }

    @Test("incompatible or absent scale keeps live power but withholds observed-region semantics")
    func incompatibleScaleFailsRegionClosed() throws {
        let id = try identity("a")
        let foreign = try identity("b")
        let foreignScale = try PropulsionGaugeScale.simulator(identity: foreign, ceilingWatts: 1_000)
        let policy = try PropulsionObservedScaleRegionPolicy(nearEdgeFraction: 0.9)
        var model = PropulsionGaugeDisplayModel(identity: id, policy: try motionPolicy())
        try model.accept(sample(identity: id, watts: 950, sequence: 1, uptime: 1_000_000_000))

        for scale in [nil, foreignScale] as [PropulsionGaugeScale?] {
            let region = model.observedScaleRegionSnapshot(
                atUptimeNanoseconds: 1_000_000_000,
                scale: scale,
                policy: policy
            )
            #expect(region.availability == .live)
            #expect(region.region == .observedScaleUnavailable)
            #expect(region.latestAcceptedWatts == 950)
            #expect(region.acceptedObservedScaleFraction == nil)
            #expect(region.scaleOrigin == nil)
        }
    }

    @Test("retained and explicit-unavailable evidence never keeps a near-edge state")
    func staleAndUnavailableFailClosed() throws {
        let id = try identity()
        let scale = try PropulsionGaugeScale.simulator(identity: id, ceilingWatts: 1_000)
        let policy = try PropulsionObservedScaleRegionPolicy(nearEdgeFraction: 0.9)
        var model = PropulsionGaugeDisplayModel(identity: id, policy: try motionPolicy(staleAfter: 100))
        try model.accept(sample(identity: id, watts: 950, sequence: 1, uptime: 1_000))

        let retained = model.observedScaleRegionSnapshot(
            atUptimeNanoseconds: 1_101,
            scale: scale,
            policy: policy
        )
        #expect(retained.region == .retained)
        #expect(retained.latestAcceptedWatts == 950)
        #expect(retained.acceptedObservedScaleFraction == nil)

        model.markUnavailable()
        let unavailable = model.observedScaleRegionSnapshot(
            atUptimeNanoseconds: 1_101,
            scale: scale,
            policy: policy
        )
        #expect(unavailable.region == .unavailable)
        #expect(unavailable.latestAcceptedWatts == 950)
        #expect(unavailable.acceptedObservedScaleFraction == nil)
    }

    @Test("threshold comparison is inclusive and remains presentation-only")
    func thresholdIsInclusive() throws {
        let id = try identity()
        let scale = try PropulsionGaugeScale.simulator(identity: id, ceilingWatts: 1_000)
        let policy = try PropulsionObservedScaleRegionPolicy(nearEdgeFraction: 0.9)
        var model = PropulsionGaugeDisplayModel(identity: id, policy: try motionPolicy())
        try model.accept(sample(identity: id, watts: 900, sequence: 1, uptime: 1_000))

        let region = model.observedScaleRegionSnapshot(
            atUptimeNanoseconds: 1_000,
            scale: scale,
            policy: policy
        )
        #expect(region.region == .nearObservedScaleEdge)
        #expect(region.isNearObservedScaleEdge)
        #expect(region.acceptedObservedScaleFraction == 0.9)
    }
}
