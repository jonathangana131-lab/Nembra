import Testing
@testable import NembraCore

@Suite("Nembra Energy Rail app accessibility cadence")
struct PropulsionEnergyRailAppAccessibilityCadenceTests {
    private func makeIdentity(
        _ vehicleID: String = "energy-rail-app-accessibility"
    ) throws -> PropulsionGaugeIdentity {
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
        uptime: UInt64,
        generation: UInt64 = 1
    ) throws -> PropulsionPowerSample {
        try .simulator(
            identity: identity,
            watts: watts,
            receiptSequenceNumber: receipt,
            receivedAtUptimeNanoseconds: uptime,
            continuityGeneration: generation
        )
    }

    @Test("render clock changes do not advance app accessibility semantics")
    func displayClockKeepsSemanticRevisionStable() throws {
        let identity = try makeIdentity()
        var model = try makeModel(identity: identity)
        let scale = try PropulsionGaugeScale.simulator(
            identity: identity,
            ceilingWatts: 1_000
        )

        try model.accept(sample(
            identity: identity,
            watts: 100,
            receipt: 1,
            uptime: 1_000_000_000
        ))
        try model.accept(sample(
            identity: identity,
            watts: 800,
            receipt: 2,
            uptime: 1_100_000_000
        ))

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
        #expect(early.displayWatts != later.displayWatts)
        #expect(early.railFraction != later.railFraction)

        #expect(early.accessibilityPresentation == later.accessibilityPresentation)
        #expect(
            early.accessibilityPresentation.semanticRevision
                == later.accessibilityPresentation.semanticRevision
        )
        #expect(early.accessibilityPresentation.currentness == .live)
        #expect(early.accessibilityPresentation.acceptedWatts == 800)
        #expect(
            early.accessibilityPresentation.acceptedRevision?.receiptSequenceNumber == 2
        )
    }

    @Test("live to retained advances app semantics without inventing a new measurement")
    func freshnessTransitionChangesOnlySemanticCurrentness() throws {
        let identity = try makeIdentity("energy-rail-retained-accessibility")
        var model = try makeModel(
            identity: identity,
            staleAfterNanoseconds: 1_000_000_000
        )
        let scale = try PropulsionGaugeScale.simulator(
            identity: identity,
            ceilingWatts: 1_000
        )

        try model.accept(sample(
            identity: identity,
            watts: 640,
            receipt: 6,
            uptime: 1_000_000_000,
            generation: 3
        ))

        let live = model.energyRailAppProjection(
            atUptimeNanoseconds: 1_500_000_000,
            scale: scale
        )
        let retained = model.energyRailAppProjection(
            atUptimeNanoseconds: 2_000_000_001,
            scale: scale
        )

        #expect(live.currentness == .live)
        #expect(retained.currentness == .retained)
        #expect(live.acceptedMeasurement == retained.acceptedMeasurement)
        #expect(live.acceptedWatts == 640)
        #expect(retained.acceptedWatts == 640)

        #expect(
            live.accessibilityPresentation.acceptedRevision
                == retained.accessibilityPresentation.acceptedRevision
        )
        #expect(
            live.accessibilityPresentation.semanticRevision
                != retained.accessibilityPresentation.semanticRevision
        )
        #expect(live.accessibilityPresentation.currentness == .live)
        #expect(retained.accessibilityPresentation.currentness == .retained)
        #expect(retained.displayWatts == 640)
        #expect(retained.railFraction == nil)
        #expect(!retained.allowsLiveMotion)
    }

    @Test("unavailable app projection carries unavailable accessibility semantics")
    func unavailableProjectionHasNoSemanticNumericTruth() throws {
        let identity = try makeIdentity("energy-rail-unavailable-accessibility")
        let model = try makeModel(identity: identity)
        let scale = try PropulsionGaugeScale.simulator(
            identity: identity,
            ceilingWatts: 1_000
        )

        let projection = model.energyRailAppProjection(
            atUptimeNanoseconds: 1_000,
            scale: scale
        )

        #expect(projection.currentness == .unavailable)
        #expect(projection.acceptedMeasurement == nil)
        #expect(projection.acceptedWatts == nil)
        #expect(projection.displayWatts == nil)
        #expect(projection.railFraction == nil)
        #expect(!projection.allowsLiveMotion)

        #expect(projection.accessibilityPresentation.identity == identity)
        #expect(projection.accessibilityPresentation.currentness == .unavailable)
        #expect(projection.accessibilityPresentation.acceptedWatts == nil)
        #expect(projection.accessibilityPresentation.acceptedRevision == nil)
        #expect(
            projection.accessibilityPresentation.semanticRevision.currentness == .unavailable
        )
    }
}
