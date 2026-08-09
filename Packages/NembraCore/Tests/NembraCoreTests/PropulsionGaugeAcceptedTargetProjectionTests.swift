import Testing
@testable import NembraCore

@Suite("Propulsion gauge accepted target projection")
struct PropulsionGaugeAcceptedTargetProjectionTests {
    private func identity(_ vehicleID: String = "es80-accepted-target") throws -> PropulsionGaugeIdentity {
        try PropulsionGaugeIdentity(vehicleID: vehicleID, modeKey: nil)
    }

    private func model(identity: PropulsionGaugeIdentity) throws -> PropulsionGaugeDisplayModel {
        PropulsionGaugeDisplayModel(
            identity: identity,
            animationPolicy: try PropulsionGaugeAnimationPolicy(
                riseSettlingDurationNanoseconds: 1_000_000_000,
                fallSettlingDurationNanoseconds: 500_000_000,
                acceptedPeakHoldNanoseconds: 750_000_000
            ),
            freshnessPolicy: try PropulsionGaugeFreshnessPolicy(
                staleAfterNanoseconds: 1_000_000_000
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

    @Test("accepted normalized target is stable while display fraction interpolates")
    func acceptedTargetDoesNotFollowDisplayClock() throws {
        let identity = try identity()
        var model = try model(identity: identity)
        let scale = try PropulsionGaugeScale.simulator(identity: identity, ceilingWatts: 1_000)

        try model.accept(simulatorSample(
            identity: identity,
            watts: 100,
            receipt: 1,
            uptime: 1_000_000_000
        ))
        try model.accept(simulatorSample(
            identity: identity,
            watts: 800,
            receipt: 2,
            uptime: 1_100_000_000
        ))

        let early = model.cockpitSnapshot(
            atUptimeNanoseconds: 1_200_000_000,
            scale: scale
        )
        let later = model.cockpitSnapshot(
            atUptimeNanoseconds: 1_500_000_000,
            scale: scale
        )

        #expect(early.visualPropulsionFraction != later.visualPropulsionFraction)
        #expect(early.acceptedPropulsionFraction == 0.8)
        #expect(later.acceptedPropulsionFraction == 0.8)
    }

    @Test("accepted target clamps as presentation geometry without clamping accepted watts")
    func acceptedTargetClampsOnlyPresentation() throws {
        let identity = try identity()
        var model = try model(identity: identity)
        let scale = try PropulsionGaugeScale.simulator(identity: identity, ceilingWatts: 1_000)

        try model.accept(simulatorSample(
            identity: identity,
            watts: 1_200,
            receipt: 3,
            uptime: 1_000_000_000
        ))

        let snapshot = model.cockpitSnapshot(
            atUptimeNanoseconds: 1_000_000_000,
            scale: scale
        )

        guard case let .live(accepted) = snapshot.measurement else {
            #expect(Bool(false))
            return
        }

        #expect(accepted.watts == 1_200)
        #expect(snapshot.acceptedPropulsionFraction == 1)
    }

    @Test("foreign presentation scale cannot create accepted target geometry")
    func foreignScaleFailsAcceptedTargetClosed() throws {
        let identity = try identity()
        let foreignIdentity = try identity("different-es80")
        var model = try model(identity: identity)

        try model.accept(simulatorSample(
            identity: identity,
            watts: 500,
            receipt: 4,
            uptime: 1_000_000_000
        ))

        let snapshot = model.cockpitSnapshot(
            atUptimeNanoseconds: 1_000_000_000,
            scale: try .simulator(identity: foreignIdentity, ceilingWatts: 900)
        )

        guard case let .live(accepted) = snapshot.measurement else {
            #expect(Bool(false))
            return
        }

        #expect(accepted.watts == 500)
        #expect(snapshot.visualPropulsionFraction == nil)
        #expect(snapshot.acceptedPropulsionFraction == nil)
        #expect(snapshot.scaleOrigin == nil)
    }

    @Test("simulator evidence cannot borrow verified-scale target authority")
    func authorityMismatchFailsAcceptedTargetClosed() throws {
        let identity = try identity()
        var model = try model(identity: identity)

        try model.accept(simulatorSample(
            identity: identity,
            watts: 500,
            receipt: 5,
            uptime: 1_000_000_000
        ))

        let snapshot = model.cockpitSnapshot(
            atUptimeNanoseconds: 1_000_000_000,
            scale: try .verifiedObservedEnvelope(identity: identity, ceilingWatts: 1_000)
        )

        #expect(snapshot.acceptedPropulsionFraction == nil)
        #expect(snapshot.visualPropulsionFraction == nil)
        #expect(snapshot.scaleOrigin == nil)
    }

    @Test("retained and unavailable evidence remove accepted target geometry")
    func nonLiveEvidenceHasNoAcceptedTarget() throws {
        let identity = try identity()
        var model = try model(identity: identity)
        let scale = try PropulsionGaugeScale.simulator(identity: identity, ceilingWatts: 1_000)

        try model.accept(simulatorSample(
            identity: identity,
            watts: 640,
            receipt: 6,
            uptime: 1_000_000_000
        ))

        let retained = model.cockpitSnapshot(
            atUptimeNanoseconds: 2_000_000_001,
            scale: scale
        )
        #expect(retained.acceptedPropulsionFraction == nil)
        #expect(retained.visualPropulsionFraction == nil)

        model.markUnavailable()
        let unavailable = model.cockpitSnapshot(
            atUptimeNanoseconds: 2_000_000_002,
            scale: scale
        )
        #expect(unavailable.measurement == .unavailable)
        #expect(unavailable.acceptedPropulsionFraction == nil)
        #expect(unavailable.visualPropulsionFraction == nil)
    }
}
