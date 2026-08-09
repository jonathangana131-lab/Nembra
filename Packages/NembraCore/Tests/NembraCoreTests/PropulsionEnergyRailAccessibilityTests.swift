import Testing
@testable import NembraCore

@Suite("Nembra Energy Rail accessibility")
struct PropulsionEnergyRailAccessibilityTests {
    private func makeIdentity(_ vehicleID: String = "es80-energy-rail-accessibility") throws
        -> PropulsionGaugeIdentity {
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

    @Test("60 Hz render motion cannot advance Energy Rail accessibility semantics")
    func renderFramesKeepOneAcceptedSemanticRevision() throws {
        let identity = try makeIdentity()
        var model = try displayModel(identity: identity)
        let scale = try PropulsionGaugeScale.simulator(identity: identity, ceilingWatts: 1_000)

        try model.accept(sample(identity: identity, watts: 100, receipt: 1, uptime: 1_000_000_000))
        try model.accept(sample(identity: identity, watts: 800, receipt: 2, uptime: 1_100_000_000))

        let earlySnapshot = model.cockpitSnapshot(
            atUptimeNanoseconds: 1_200_000_000,
            scale: scale
        )
        let laterSnapshot = model.cockpitSnapshot(
            atUptimeNanoseconds: 1_500_000_000,
            scale: scale
        )

        #expect(earlySnapshot.visualPropulsionFraction != laterSnapshot.visualPropulsionFraction)

        let early = earlySnapshot.energyRailAccessibilityPresentation
        let later = laterSnapshot.energyRailAccessibilityPresentation

        #expect(early == later)
        #expect(early.identity == identity)
        #expect(early.currentness == .live)
        #expect(early.acceptedWatts == 800)
        #expect(early.acceptedRevision?.authority == .simulator)
        #expect(early.acceptedRevision?.continuityGeneration == 1)
        #expect(early.acceptedRevision?.receiptSequenceNumber == 2)
        #expect(early.acceptedRevision?.receivedAtUptimeNanoseconds == 1_100_000_000)
    }

    @Test("a new accepted measurement advances semantic revision exactly once")
    func acceptedMeasurementAdvancesRevision() throws {
        let identity = try makeIdentity()
        var model = try displayModel(identity: identity)

        try model.accept(sample(identity: identity, watts: 420, receipt: 4, uptime: 1_000_000_000))
        let first = model.cockpitSnapshot(
            atUptimeNanoseconds: 1_000_000_000,
            scale: nil
        ).energyRailAccessibilityPresentation

        try model.accept(sample(identity: identity, watts: 510, receipt: 5, uptime: 1_100_000_000))
        let second = model.cockpitSnapshot(
            atUptimeNanoseconds: 1_100_000_000,
            scale: nil
        ).energyRailAccessibilityPresentation

        #expect(first.acceptedRevision != second.acceptedRevision)
        #expect(first.acceptedWatts == 420)
        #expect(second.acceptedWatts == 510)
        #expect(second.acceptedRevision?.receiptSequenceNumber == 5)
    }

    @Test("retained watts stay semantic but remain explicitly retained")
    func retainedMeasurementPreservesAcceptedRevision() throws {
        let identity = try makeIdentity()
        var model = try displayModel(identity: identity, staleAfterNanoseconds: 1_000_000_000)

        try model.accept(sample(identity: identity, watts: 640, receipt: 6, uptime: 1_000_000_000))
        let presentation = model.cockpitSnapshot(
            atUptimeNanoseconds: 2_000_000_001,
            scale: nil
        ).energyRailAccessibilityPresentation

        #expect(presentation.currentness == .retained)
        #expect(presentation.acceptedWatts == 640)
        #expect(presentation.acceptedRevision?.receiptSequenceNumber == 6)
        #expect(presentation.acceptedRevision?.receivedAtUptimeNanoseconds == 1_000_000_000)
    }

    @Test("unavailable Energy Rail semantics never manufacture zero or a revision")
    func unavailableHasNoNumericSemanticTruth() throws {
        let identity = try makeIdentity()
        var model = try displayModel(identity: identity)

        try model.accept(sample(identity: identity, watts: 350, receipt: 7, uptime: 1_000_000_000))
        model.markUnavailable()

        let presentation = model.cockpitSnapshot(
            atUptimeNanoseconds: 1_100_000_000,
            scale: nil
        ).energyRailAccessibilityPresentation

        #expect(presentation.identity == identity)
        #expect(presentation.currentness == .unavailable)
        #expect(presentation.acceptedWatts == nil)
        #expect(presentation.acceptedRevision == nil)
    }

    @Test("continuity generation distinguishes restarted receipt identities")
    func restartedSourceGenerationGetsDistinctSemanticRevision() throws {
        let identity = try makeIdentity()
        var model = try displayModel(identity: identity)

        try model.accept(sample(
            identity: identity,
            watts: 500,
            receipt: 1,
            uptime: 1_000_000_000,
            generation: 1
        ))
        let first = model.cockpitSnapshot(
            atUptimeNanoseconds: 1_000_000_000,
            scale: nil
        ).energyRailAccessibilityPresentation

        try model.accept(sample(
            identity: identity,
            watts: 500,
            receipt: 1,
            uptime: 1_000_000_000,
            generation: 2
        ))
        let second = model.cockpitSnapshot(
            atUptimeNanoseconds: 1_000_000_000,
            scale: nil
        ).energyRailAccessibilityPresentation

        #expect(first.acceptedWatts == second.acceptedWatts)
        #expect(first.acceptedRevision?.receiptSequenceNumber == second.acceptedRevision?.receiptSequenceNumber)
        #expect(first.acceptedRevision?.receivedAtUptimeNanoseconds == second.acceptedRevision?.receivedAtUptimeNanoseconds)
        #expect(first.acceptedRevision != second.acceptedRevision)
        #expect(second.acceptedRevision?.continuityGeneration == 2)
    }
}
