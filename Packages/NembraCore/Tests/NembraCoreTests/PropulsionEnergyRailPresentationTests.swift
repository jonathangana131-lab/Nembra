import Testing
@testable import NembraCore

@Suite("Nembra Energy Rail presentation")
struct PropulsionEnergyRailPresentationTests {
    private func makeIdentity(_ vehicleID: String = "es80-energy-rail-test") throws -> PropulsionGaugeIdentity {
        try PropulsionGaugeIdentity(vehicleID: vehicleID, modeKey: nil)
    }

    private func displayModel(
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

    @Test("live accepted watts stay independent from display-clock rail motion")
    func liveMeasurementAndRailRemainSeparate() throws {
        let identity = try makeIdentity()
        var model = try displayModel(identity: identity)
        let scale = try PropulsionGaugeScale.simulator(identity: identity, ceilingWatts: 1_000)

        try model.accept(sample(identity: identity, watts: 100, receipt: 1, uptime: 1_000_000_000))
        try model.accept(sample(identity: identity, watts: 800, receipt: 2, uptime: 1_100_000_000))

        let presentation = model.cockpitSnapshot(
            atUptimeNanoseconds: 1_300_000_000,
            scale: scale
        ).energyRailPresentation

        #expect(presentation.identity == identity)
        #expect(presentation.currentness == .live)
        #expect(presentation.acceptedWatts == 800)
        #expect(presentation.railFraction != nil)
        #expect((presentation.railFraction ?? 0) < 0.8)
        #expect(presentation.scaleOrigin == .simulator)
        #expect(presentation.allowsLiveMotion)
    }

    @Test("accepted watts above presentation scale remain exact while rail clamps canonically")
    func acceptedWattsAreNotReconstructedFromRailFraction() throws {
        let identity = try makeIdentity()
        var model = try displayModel(identity: identity)
        let scale = try PropulsionGaugeScale.simulator(identity: identity, ceilingWatts: 1_000)

        try model.accept(sample(identity: identity, watts: 1_200, receipt: 3, uptime: 1_000_000_000))

        let presentation = model.cockpitSnapshot(
            atUptimeNanoseconds: 1_000_000_000,
            scale: scale
        ).energyRailPresentation

        #expect(presentation.currentness == .live)
        #expect(presentation.acceptedWatts == 1_200)
        #expect(presentation.railFraction == 1)
        #expect(presentation.acceptedPeakMarkerFraction == 1)
        #expect(presentation.allowsLiveMotion)
    }

    @Test("retained accepted watts stay visible but live rail motion stops")
    func retainedMeasurementSettlesRail() throws {
        let identity = try makeIdentity()
        var model = try displayModel(identity: identity, staleAfterNanoseconds: 1_000_000_000)
        let scale = try PropulsionGaugeScale.simulator(identity: identity, ceilingWatts: 1_000)

        try model.accept(sample(identity: identity, watts: 640, receipt: 4, uptime: 1_000_000_000))

        let presentation = model.cockpitSnapshot(
            atUptimeNanoseconds: 2_000_000_001,
            scale: scale
        ).energyRailPresentation

        #expect(presentation.currentness == .retained)
        #expect(presentation.acceptedWatts == 640)
        #expect(presentation.railFraction == nil)
        #expect(presentation.acceptedPeakMarkerFraction == nil)
        #expect(presentation.scaleOrigin == nil)
        #expect(!presentation.allowsLiveMotion)
    }

    @Test("unavailable evidence never manufactures zero watts or moving rail geometry")
    func unavailableDoesNotManufactureMeasurement() throws {
        let identity = try makeIdentity()
        let model = try displayModel(identity: identity)

        let presentation = model.cockpitSnapshot(
            atUptimeNanoseconds: 1_000,
            scale: try .simulator(identity: identity, ceilingWatts: 1_000)
        ).energyRailPresentation

        #expect(presentation.identity == identity)
        #expect(presentation.currentness == .unavailable)
        #expect(presentation.acceptedWatts == nil)
        #expect(presentation.railFraction == nil)
        #expect(presentation.acceptedPeakMarkerFraction == nil)
        #expect(presentation.scaleOrigin == nil)
        #expect(!presentation.allowsLiveMotion)
    }

    @Test("foreign normalization scale keeps live accepted watts but fails rail motion closed")
    func incompatibleScaleDoesNotHideAcceptedNumericTruth() throws {
        let identity = try makeIdentity()
        let foreignIdentity = try makeIdentity("different-es80")
        var model = try displayModel(identity: identity)

        try model.accept(sample(identity: identity, watts: 500, receipt: 5, uptime: 1_000_000_000))

        let presentation = model.cockpitSnapshot(
            atUptimeNanoseconds: 1_000_000_000,
            scale: try .simulator(identity: foreignIdentity, ceilingWatts: 900)
        ).energyRailPresentation

        #expect(presentation.currentness == .live)
        #expect(presentation.acceptedWatts == 500)
        #expect(presentation.railFraction == nil)
        #expect(presentation.acceptedPeakMarkerFraction == nil)
        #expect(presentation.scaleOrigin == nil)
        #expect(!presentation.allowsLiveMotion)
    }
}
