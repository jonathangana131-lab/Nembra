import Testing
@testable import NembraCore

@Suite("Nembra Energy Rail dual-clock render presentation")
struct PropulsionEnergyRailRenderPresentationTests {
    private func makeIdentity(_ vehicleID: String = "energy-rail-dual-clock") throws -> PropulsionGaugeIdentity {
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

    @Test("display watts move while accepted semantic watts remain fixed")
    func displayClockDoesNotRewriteMeasurementClock() throws {
        let identity = try makeIdentity()
        var model = try makeModel(identity: identity)
        let scale = try PropulsionGaugeScale.simulator(identity: identity, ceilingWatts: 1_000)

        try model.accept(sample(identity: identity, watts: 100, receipt: 1, uptime: 1_000_000_000))
        try model.accept(sample(identity: identity, watts: 800, receipt: 2, uptime: 1_100_000_000))

        let early = model.energyRailRenderPresentation(
            atUptimeNanoseconds: 1_250_000_000,
            scale: scale
        )
        let later = model.energyRailRenderPresentation(
            atUptimeNanoseconds: 1_450_000_000,
            scale: scale
        )

        #expect(early.currentness == .live)
        #expect(later.currentness == .live)
        #expect(early.acceptedWatts == 800)
        #expect(later.acceptedWatts == 800)
        #expect(early.displayWatts != later.displayWatts)
        #expect((early.displayWatts ?? 0) < (later.displayWatts ?? 0))
        #expect((later.displayWatts ?? 0) < 800)
        #expect(early.displayOrigin == .visuallyInterpolated)
        #expect(later.displayOrigin == .visuallyInterpolated)
        #expect(early.allowsDisplayWattsMotion)
        #expect(later.allowsDisplayWattsMotion)
        #expect(early.allowsRailMotion)
        #expect(later.allowsRailMotion)
    }

    @Test("settled live frame keeps one accepted value without fake motion")
    func settledFrameDoesNotClaimInterpolation() throws {
        let identity = try makeIdentity()
        var model = try makeModel(identity: identity)
        let scale = try PropulsionGaugeScale.simulator(identity: identity, ceilingWatts: 1_000)

        try model.accept(sample(identity: identity, watts: 420, receipt: 1, uptime: 1_000_000_000))

        let presentation = model.energyRailRenderPresentation(
            atUptimeNanoseconds: 1_000_000_000,
            scale: scale
        )

        #expect(presentation.currentness == .live)
        #expect(presentation.acceptedWatts == 420)
        #expect(presentation.displayWatts == 420)
        #expect(presentation.displayOrigin == .acceptedMeasurement)
        #expect(!presentation.allowsDisplayWattsMotion)
        #expect(presentation.allowsRailMotion)
    }

    @Test("retained state snaps render watts to accepted truth and stops motion")
    func retainedStateStopsDisplayClock() throws {
        let identity = try makeIdentity()
        var model = try makeModel(identity: identity, staleAfterNanoseconds: 1_000_000_000)
        let scale = try PropulsionGaugeScale.simulator(identity: identity, ceilingWatts: 1_000)

        try model.accept(sample(identity: identity, watts: 640, receipt: 1, uptime: 1_000_000_000))

        let presentation = model.energyRailRenderPresentation(
            atUptimeNanoseconds: 2_000_000_001,
            scale: scale
        )

        #expect(presentation.currentness == .retained)
        #expect(presentation.acceptedWatts == 640)
        #expect(presentation.displayWatts == 640)
        #expect(presentation.displayOrigin == .retainedAcceptedMeasurement)
        #expect(presentation.railFraction == nil)
        #expect(presentation.acceptedPeakMarkerFraction == nil)
        #expect(presentation.scaleOrigin == nil)
        #expect(!presentation.allowsDisplayWattsMotion)
        #expect(!presentation.allowsRailMotion)
    }

    @Test("unavailable and invalid render clocks expose no numeric channel")
    func unavailableFramesDoNotManufactureWatts() throws {
        let identity = try makeIdentity()
        var model = try makeModel(identity: identity)
        let scale = try PropulsionGaugeScale.simulator(identity: identity, ceilingWatts: 1_000)

        let empty = model.energyRailRenderPresentation(
            atUptimeNanoseconds: 1_000,
            scale: scale
        )
        #expect(empty.currentness == .unavailable)
        #expect(empty.acceptedWatts == nil)
        #expect(empty.displayWatts == nil)
        #expect(!empty.allowsDisplayWattsMotion)
        #expect(!empty.allowsRailMotion)

        try model.accept(sample(identity: identity, watts: 300, receipt: 1, uptime: 10_000))
        let backwardsClock = model.energyRailRenderPresentation(
            atUptimeNanoseconds: 9_999,
            scale: scale
        )
        #expect(backwardsClock.currentness == .unavailable)
        #expect(backwardsClock.acceptedWatts == nil)
        #expect(backwardsClock.displayWatts == nil)
        #expect(backwardsClock.displayOrigin == .invalidRenderClock)
    }

    @Test("foreign scale cannot erase watt channels or manufacture rail geometry")
    func incompatibleScaleOnlyDisablesGeometry() throws {
        let identity = try makeIdentity()
        let foreignIdentity = try makeIdentity("foreign-energy-rail")
        var model = try makeModel(identity: identity)

        try model.accept(sample(identity: identity, watts: 500, receipt: 1, uptime: 1_000_000_000))

        let presentation = model.energyRailRenderPresentation(
            atUptimeNanoseconds: 1_000_000_000,
            scale: try .simulator(identity: foreignIdentity, ceilingWatts: 900)
        )

        #expect(presentation.currentness == .live)
        #expect(presentation.acceptedWatts == 500)
        #expect(presentation.displayWatts == 500)
        #expect(presentation.railFraction == nil)
        #expect(presentation.acceptedPeakMarkerFraction == nil)
        #expect(presentation.scaleOrigin == nil)
        #expect(!presentation.allowsRailMotion)
    }
}