import Testing
@testable import NembraCore

@Suite("Propulsion verified near-observed-maximum wording policy")
struct PropulsionVerifiedNearObservedMaximumWordingPolicyTests {
    private let identity = try! PropulsionGaugeIdentity(
        vehicleID: "wording-policy-es80",
        modeKey: "sport"
    )

    private func model() throws -> PropulsionGaugeDisplayModel {
        PropulsionGaugeDisplayModel(
            identity: identity,
            animationPolicy: try PropulsionGaugeAnimationPolicy(
                riseSettlingDurationNanoseconds: 500_000_000,
                fallSettlingDurationNanoseconds: 250_000_000,
                acceptedPeakHoldNanoseconds: 500_000_000
            ),
            freshnessPolicy: try PropulsionGaugeFreshnessPolicy(
                staleAfterNanoseconds: 3_000_000_000
            )
        )
    }

    private func verifiedSample(
        watts: Double,
        sequence: UInt64,
        uptime: UInt64
    ) throws -> PropulsionPowerSample {
        try .verifiedVehicleMeasurement(
            identity: identity,
            watts: watts,
            receiptSequenceNumber: sequence,
            receivedAtUptimeNanoseconds: uptime,
            continuityGeneration: 1
        )
    }

    @Test("arbitrarily low visual threshold cannot unlock verified near-max wording")
    func genericVisualThresholdCannotWeakenWordingSemantics() throws {
        let visualPolicy = try PropulsionObservedScaleRegionPolicy(nearEdgeFraction: 0.01)
        let scale = try PropulsionGaugeScale.verifiedObservedEnvelope(
            identity: identity,
            ceilingWatts: 1_000
        )
        var gauge = try model()

        try gauge.accept(verifiedSample(watts: 10, sequence: 1, uptime: 1_000))

        let snapshot = gauge.observedScaleRegionSnapshot(
            atUptimeNanoseconds: 1_000,
            scale: scale,
            policy: visualPolicy
        )

        #expect(snapshot.region == .nearObservedScaleEdge)
        #expect(snapshot.isNearObservedScaleEdge)
        #expect(snapshot.latestAuthority == .verifiedVehicleMeasurement)
        #expect(snapshot.scaleOrigin == .verifiedObservedEnvelope)
        #expect(snapshot.acceptedObservedScaleFraction == 0.01)
        #expect(!snapshot.permitsVerifiedNearObservedMaximumWording)
    }

    @Test("product-owned wording floor is independent, auditable, and inclusive")
    func productWordingFloorIsIndependentAndInclusive() throws {
        #expect(
            PropulsionVerifiedNearObservedMaximumWordingPolicy.product.minimumObservedScaleFraction == 0.9
        )

        let visualPolicy = try PropulsionObservedScaleRegionPolicy(nearEdgeFraction: 0.01)
        let scale = try PropulsionGaugeScale.verifiedObservedEnvelope(
            identity: identity,
            ceilingWatts: 1_000
        )
        var gauge = try model()

        try gauge.accept(verifiedSample(watts: 899, sequence: 1, uptime: 1_000))
        let belowFloor = gauge.observedScaleRegionSnapshot(
            atUptimeNanoseconds: 1_000,
            scale: scale,
            policy: visualPolicy
        )
        #expect(belowFloor.region == .nearObservedScaleEdge)
        #expect(belowFloor.acceptedObservedScaleFraction == 0.899)
        #expect(!belowFloor.permitsVerifiedNearObservedMaximumWording)

        try gauge.accept(verifiedSample(watts: 900, sequence: 2, uptime: 2_000))
        let atFloor = gauge.observedScaleRegionSnapshot(
            atUptimeNanoseconds: 2_000,
            scale: scale,
            policy: visualPolicy
        )
        #expect(atFloor.region == .nearObservedScaleEdge)
        #expect(atFloor.acceptedObservedScaleFraction == 0.9)
        #expect(atFloor.permitsVerifiedNearObservedMaximumWording)
    }

    @Test("Simulator near-edge state cannot satisfy verified wording policy")
    func simulatorCannotSatisfyVerifiedWordingPolicy() throws {
        let visualPolicy = try PropulsionObservedScaleRegionPolicy(nearEdgeFraction: 0.01)
        let scale = try PropulsionGaugeScale.simulator(
            identity: identity,
            ceilingWatts: 1_000
        )
        var gauge = try model()

        try gauge.accept(.simulator(
            identity: identity,
            watts: 1_000,
            receiptSequenceNumber: 1,
            receivedAtUptimeNanoseconds: 1_000,
            continuityGeneration: 1
        ))

        let snapshot = gauge.observedScaleRegionSnapshot(
            atUptimeNanoseconds: 1_000,
            scale: scale,
            policy: visualPolicy
        )

        #expect(snapshot.region == .nearObservedScaleEdge)
        #expect(snapshot.acceptedObservedScaleFraction == 1)
        #expect(snapshot.isSimulatorNearObservedScaleEdge)
        #expect(!snapshot.permitsVerifiedNearObservedMaximumWording)
    }
}
