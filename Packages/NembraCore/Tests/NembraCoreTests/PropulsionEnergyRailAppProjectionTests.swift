import Testing
@testable import NembraCore

@Suite("Nembra Energy Rail app projection")
struct PropulsionEnergyRailAppProjectionTests {
    private func makeIdentity(_ vehicleID: String = "energy-rail-app-projection") throws -> PropulsionGaugeIdentity {
        try PropulsionGaugeIdentity(vehicleID: vehicleID, modeKey: nil)
    }

    private func makeModel(
        identity: PropulsionGaugeIdentity,
        staleAfterNanoseconds: UInt64 = 2_000_000_000
    ) throws -> PropulsionGaugeDisplayModel {
        PropulsionGaugeDisplayModel(
            identity: identity,
            animationPolicy: try PropulsionGaugeAnimationPolicy(
                riseSettlingDurationNanoseconds: 1_000_000_000,
                fallSettlingDurationNanoseconds: 500_000_000,
                acceptedPeakHoldNanoseconds: 750_000_000
            ),
            freshnessPolicy: try PropulsionGaugeFreshnessPolicy(
                staleAfterNanoseconds: staleAfterNanoseconds
            )
        )
    }

    private func sample(
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

    @Test("live app projection carries accepted truth and render-only motion together")
    func liveProjectionCrossBindsSemanticAndRenderChannels() throws {
        let identity = try makeIdentity()
        var model = try makeModel(identity: identity)
        let scale = try PropulsionGaugeScale.simulator(identity: identity, ceilingWatts: 1_000)

        try model.accept(sample(identity: identity, watts: 100, receipt: 1, uptime: 1_000_000_000))
        try model.accept(sample(identity: identity, watts: 800, receipt: 2, uptime: 1_100_000_000))

        let projection = model.energyRailAppProjection(
            atUptimeNanoseconds: 1_300_000_000,
            scale: scale
        )

        #expect(projection.identity == identity)
        #expect(projection.currentness == .live)
        #expect(projection.acceptedWatts == 800)
        #expect(projection.displayWatts != nil)
        #expect((projection.displayWatts ?? 0) < 800)
        #expect(projection.railFraction != nil)
        #expect((projection.railFraction ?? 0) < 0.8)
        #expect(projection.acceptedTargetFraction == 0.8)
        #expect(projection.acceptedPeakMarkerFraction == 0.8)
        #expect(projection.allowsLiveMotion)
    }

    @Test("settled live app projection keeps rail geometry without fake watt interpolation")
    func settledLiveProjectionKeepsRailVisible() throws {
        let identity = try makeIdentity()
        var model = try makeModel(identity: identity)
        let scale = try PropulsionGaugeScale.simulator(identity: identity, ceilingWatts: 1_000)

        try model.accept(sample(identity: identity, watts: 420, receipt: 1, uptime: 1_000_000_000))

        let projection = model.energyRailAppProjection(
            atUptimeNanoseconds: 1_000_000_000,
            scale: scale
        )

        #expect(projection.currentness == .live)
        #expect(projection.acceptedWatts == 420)
        #expect(projection.displayWatts == 420)
        #expect(projection.railFraction == 0.42)
        #expect(projection.acceptedTargetFraction == 0.42)
        #expect(projection.allowsLiveMotion)
    }

    @Test("retained app projection preserves accepted watts and removes moving geometry")
    func retainedProjectionStopsRenderClock() throws {
        let identity = try makeIdentity()
        var model = try makeModel(identity: identity, staleAfterNanoseconds: 1_000_000_000)
        let scale = try PropulsionGaugeScale.simulator(identity: identity, ceilingWatts: 1_000)

        try model.accept(sample(identity: identity, watts: 640, receipt: 1, uptime: 1_000_000_000))

        let projection = model.energyRailAppProjection(
            atUptimeNanoseconds: 2_000_000_001,
            scale: scale
        )

        #expect(projection.currentness == .retained)
        #expect(projection.acceptedWatts == 640)
        #expect(projection.displayWatts == 640)
        #expect(projection.railFraction == nil)
        #expect(projection.acceptedTargetFraction == nil)
        #expect(projection.acceptedPeakMarkerFraction == nil)
        #expect(!projection.allowsLiveMotion)
    }

    @Test("unavailable app projection manufactures no numeric or geometry truth")
    func unavailableProjectionStaysEmpty() throws {
        let identity = try makeIdentity()
        let model = try makeModel(identity: identity)

        let projection = model.energyRailAppProjection(
            atUptimeNanoseconds: 1_000,
            scale: try .simulator(identity: identity, ceilingWatts: 1_000)
        )

        #expect(projection.identity == identity)
        #expect(projection.currentness == .unavailable)
        #expect(projection.acceptedWatts == nil)
        #expect(projection.displayWatts == nil)
        #expect(projection.railFraction == nil)
        #expect(projection.acceptedTargetFraction == nil)
        #expect(projection.acceptedPeakMarkerFraction == nil)
        #expect(!projection.allowsLiveMotion)
    }

    @Test("foreign scale preserves accepted watts while geometry fails closed")
    func foreignScaleCannotManufactureRailAuthority() throws {
        let identity = try makeIdentity()
        let foreignIdentity = try makeIdentity("foreign-energy-rail-app-projection")
        var model = try makeModel(identity: identity)

        try model.accept(sample(identity: identity, watts: 500, receipt: 1, uptime: 1_000_000_000))

        let projection = model.energyRailAppProjection(
            atUptimeNanoseconds: 1_000_000_000,
            scale: try .simulator(identity: foreignIdentity, ceilingWatts: 900)
        )

        #expect(projection.currentness == .live)
        #expect(projection.acceptedWatts == 500)
        #expect(projection.displayWatts == 500)
        #expect(projection.railFraction == nil)
        #expect(projection.acceptedTargetFraction == nil)
        #expect(projection.acceptedPeakMarkerFraction == nil)
        #expect(!projection.allowsLiveMotion)
    }

    @Test("accepted target stays stable while display clock advances")
    func acceptedTargetSupportsReduceMotionWithoutAppSideNormalization() throws {
        let identity = try makeIdentity()
        var model = try makeModel(identity: identity)
        let scale = try PropulsionGaugeScale.simulator(identity: identity, ceilingWatts: 1_000)

        try model.accept(sample(identity: identity, watts: 100, receipt: 1, uptime: 1_000_000_000))
        try model.accept(sample(identity: identity, watts: 800, receipt: 2, uptime: 1_100_000_000))

        let early = model.energyRailAppProjection(
            atUptimeNanoseconds: 1_250_000_000,
            scale: scale
        )
        let later = model.energyRailAppProjection(
            atUptimeNanoseconds: 1_450_000_000,
            scale: scale
        )

        #expect(early.currentness == .live)
        #expect(later.currentness == .live)
        #expect(early.acceptedWatts == 800)
        #expect(later.acceptedWatts == 800)
        #expect(early.acceptedTargetFraction == 0.8)
        #expect(later.acceptedTargetFraction == 0.8)
        #expect(early.displayWatts != later.displayWatts)
        #expect(early.railFraction != later.railFraction)
        #expect((early.railFraction ?? 1) < 0.8)
        #expect((later.railFraction ?? 1) < 0.8)
    }
}
