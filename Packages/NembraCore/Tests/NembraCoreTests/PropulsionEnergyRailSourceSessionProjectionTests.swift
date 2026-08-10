import Testing
@testable import NembraCore

@Suite("Energy Rail source-session app projection")
struct PropulsionEnergyRailSourceSessionProjectionTests {
    private let identity = try! PropulsionGaugeIdentity(
        vehicleID: "energy-rail-session-simulator",
        modeKey: "qa"
    )

    private func session() throws -> PropulsionGaugeSourceSession {
        PropulsionGaugeSourceSession(
            identity: identity,
            animationPolicy: try PropulsionGaugeAnimationPolicy(
                riseSettlingDurationNanoseconds: 300_000_000,
                fallSettlingDurationNanoseconds: 200_000_000,
                acceptedPeakHoldNanoseconds: 2_000_000_000
            ),
            freshnessPolicy: try PropulsionGaugeFreshnessPolicy(
                staleAfterNanoseconds: 1_000_000_000
            )
        )
    }

    private func scale() throws -> PropulsionGaugeScale {
        try .simulator(identity: identity, ceilingWatts: 500)
    }

    @Test("session interruption fences app projection and newer generation recovers")
    func interruptionAndRecoveryStayBoundToSessionAuthority() throws {
        var session = try session()
        let scale = try scale()

        try session.accept(.simulator(
            identity: identity,
            watts: 250,
            receiptSequenceNumber: 7,
            receivedAtUptimeNanoseconds: 700,
            continuityGeneration: 1
        ))

        let live = session.energyRailAppProjection(
            atUptimeNanoseconds: 700,
            scale: scale
        )
        #expect(live.currentness == .live)
        #expect(live.acceptedWatts == 250)
        #expect(live.acceptedMeasurement?.authority == .simulator)
        #expect(live.railFraction == 0.5)
        #expect(live.acceptedTargetFraction == 0.5)

        let disposition = session.markUnavailable(
            authority: .simulator,
            continuityGeneration: 1
        )
        #expect(disposition == .appliedToActiveAuthority)

        let unavailable = session.energyRailAppProjection(
            atUptimeNanoseconds: 800,
            scale: scale
        )
        #expect(unavailable.currentness == .unavailable)
        #expect(unavailable.acceptedWatts == nil)
        #expect(unavailable.displayWatts == nil)
        #expect(unavailable.railFraction == nil)
        #expect(unavailable.acceptedPeakMarkerFraction == nil)
        #expect(unavailable.allowsLiveMotion == false)

        #expect(throws: PropulsionGaugeDisplayError.retiredContinuityGeneration) {
            try session.accept(.simulator(
                identity: identity,
                watts: 300,
                receiptSequenceNumber: 8,
                receivedAtUptimeNanoseconds: 900,
                continuityGeneration: 1
            ))
        }

        try session.accept(.simulator(
            identity: identity,
            watts: 300,
            receiptSequenceNumber: 1,
            receivedAtUptimeNanoseconds: 100,
            continuityGeneration: 2
        ))

        let recovered = session.energyRailAppProjection(
            atUptimeNanoseconds: 100,
            scale: scale
        )
        #expect(recovered.currentness == .live)
        #expect(recovered.acceptedWatts == 300)
        #expect(recovered.acceptedMeasurement?.continuityGeneration == 2)
        #expect(recovered.acceptedMeasurement?.authority == .simulator)
        #expect(recovered.railFraction == 0.6)
        #expect(recovered.acceptedTargetFraction == 0.6)
    }

    @Test("older interruption cannot hide newer projected generation")
    func staleInterruptionCannotHideNewerProjection() throws {
        var session = try session()
        let scale = try scale()

        try session.accept(.simulator(
            identity: identity,
            watts: 200,
            receiptSequenceNumber: 4,
            receivedAtUptimeNanoseconds: 400,
            continuityGeneration: 3
        ))
        try session.accept(.simulator(
            identity: identity,
            watts: 350,
            receiptSequenceNumber: 1,
            receivedAtUptimeNanoseconds: 50,
            continuityGeneration: 4
        ))

        let disposition = session.markUnavailable(
            authority: .simulator,
            continuityGeneration: 3
        )
        #expect(disposition == .ignoredOlderGeneration)

        let projection = session.energyRailAppProjection(
            atUptimeNanoseconds: 50,
            scale: scale
        )
        #expect(projection.currentness == .live)
        #expect(projection.acceptedWatts == 350)
        #expect(projection.acceptedMeasurement?.continuityGeneration == 4)
        #expect(projection.acceptedMeasurement?.authority == .simulator)
    }
}
