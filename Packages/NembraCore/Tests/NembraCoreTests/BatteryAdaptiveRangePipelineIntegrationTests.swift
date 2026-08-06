import Foundation
import Testing
@testable import NembraCore

@Suite("Battery adaptive range pipeline integration")
struct BatteryAdaptiveRangePipelineIntegrationTests {
    private func observation(
        _ percentage: Double,
        role: BatteryEvidenceRole = .verifiedVehicleMeasurement,
        uptime: UInt64,
        continuity: BatteryEvidenceContinuity = .continuous
    ) throws -> BatteryEvidenceObservation {
        try BatteryEvidenceObservation(
            value: BatterySemanticValue.stateOfChargePercent(percentage),
            role: role,
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: Date(timeIntervalSince1970: 1_000),
            continuity: continuity
        )
    }

    private func policy(
        minimumConsumedPercentagePoints: Double = 3,
        minimumDistanceMeters: Double = 300
    ) throws -> AdaptiveBatteryRangePolicy {
        try AdaptiveBatteryRangePolicy(
            minimumConsumedPercentagePoints: minimumConsumedPercentagePoints,
            minimumDistanceMeters: minimumDistanceMeters,
            recentWindowCapacity: 3,
            recentWeight: 0.5,
            outlierLowerEfficiencyRatio: 0.4,
            outlierUpperEfficiencyRatio: 2.5,
            estimateDeadbandFraction: 0.05,
            estimateSmoothingFactor: 0.25,
            provisionalEfficiencyMetersPerPercentagePoint: nil,
            lowSOCCautionThresholdPercent: nil,
            lowSOCEfficiencyMultiplier: nil,
            lowConfidenceConsumedPercentagePoints: 10,
            normalConfidenceConsumedPercentagePoints: 30,
            highConfidenceConsumedPercentagePoints: 60
        )
    }

    @Test("distance coverage degradation survives the evidence-to-window seam")
    func coveragePropagation() throws {
        var pipeline = BatteryAdaptiveRangeLearningPipeline()
        let p = try policy()

        _ = try pipeline.acceptBatteryObservation(
            observation(80, uptime: 1),
            policy: p
        )
        try pipeline.recordDistance(deltaMeters: 100, coverage: .partial)
        try pipeline.recordDistance(deltaMeters: 200, coverage: .unknown)

        let result = try pipeline.acceptBatteryObservation(
            observation(77, uptime: 2),
            policy: p
        )
        let window = try #require(result.learningWindow)

        #expect(window.distanceMeters == 300)
        #expect(window.distanceCoverage == .unknown)
        #expect(window.startSOC.percentage == 80)
        #expect(window.endSOC.percentage == 77)
    }

    @Test("invalid distance leaves pipeline assembly state unchanged")
    func invalidDistanceIsAtomic() throws {
        var pipeline = BatteryAdaptiveRangeLearningPipeline()
        let p = try policy()

        _ = try pipeline.acceptBatteryObservation(
            observation(80, uptime: 10),
            policy: p
        )
        try pipeline.recordDistance(deltaMeters: 125, coverage: .partial)

        #expect(throws: BatteryRangeWindowAssemblyError.invalidDistanceDelta) {
            try pipeline.recordDistance(deltaMeters: .nan)
        }

        #expect(pipeline.windowAssembler.anchorSOC?.percentage == 80)
        #expect(pipeline.windowAssembler.latestAuthoritativeSOC?.percentage == 80)
        #expect(pipeline.windowAssembler.accumulatedDistanceMeters == 125)
        #expect(pipeline.windowAssembler.distanceCoverage == .partial)
    }

    @Test("known missing evidence clears every ephemeral assembler flag immediately")
    func knownGapClearsAssemblerState() throws {
        var pipeline = BatteryAdaptiveRangeLearningPipeline()
        let p = try policy(minimumConsumedPercentagePoints: 10, minimumDistanceMeters: 1_000)

        _ = try pipeline.acceptBatteryObservation(
            observation(80, uptime: 10),
            policy: p
        )
        try pipeline.recordDistance(deltaMeters: 250, coverage: .partial)
        pipeline.recordTransportGap()
        _ = try pipeline.acceptBatteryObservation(
            observation(79, uptime: 11),
            policy: p
        )

        #expect(pipeline.windowAssembler.anchorSOC?.percentage == 80)
        #expect(pipeline.windowAssembler.latestAuthoritativeSOC?.percentage == 79)
        #expect(pipeline.windowAssembler.transportGapOccurred)

        pipeline.markUnobservedInterval()

        #expect(pipeline.evidenceBridge.streamValidator.requiresContinuityBoundary)
        #expect(pipeline.windowAssembler.anchorSOC == nil)
        #expect(pipeline.windowAssembler.latestAuthoritativeSOC == nil)
        #expect(pipeline.windowAssembler.accumulatedDistanceMeters == 0)
        #expect(pipeline.windowAssembler.distanceCoverage == .complete)
        #expect(pipeline.windowAssembler.transportGapOccurred == false)
    }

    @Test("verified SoC boundary directly re-anchors after an unobserved interval")
    func verifiedBoundaryReanchorsCleanly() throws {
        var pipeline = BatteryAdaptiveRangeLearningPipeline()
        let p = try policy()

        _ = try pipeline.acceptBatteryObservation(
            observation(80, uptime: 100),
            policy: p
        )
        try pipeline.recordDistance(deltaMeters: 500)
        pipeline.markUnobservedInterval()

        let boundaryResult = try pipeline.acceptBatteryObservation(
            observation(59, uptime: 1, continuity: .afterUnobservedInterval),
            policy: p
        )

        guard case let .resetContinuityAndIngestSOC(boundaryReading) = boundaryResult.action else {
            Issue.record("Expected verified first-post-gap SoC to reset and re-anchor")
            return
        }
        #expect(boundaryReading.percentage == 59)
        #expect(boundaryResult.learningWindow == nil)
        #expect(pipeline.windowAssembler.anchorSOC?.percentage == 59)
        #expect(pipeline.windowAssembler.latestAuthoritativeSOC?.percentage == 59)
        #expect(pipeline.windowAssembler.accumulatedDistanceMeters == 0)

        try pipeline.recordDistance(deltaMeters: 300)
        let endResult = try pipeline.acceptBatteryObservation(
            observation(56, uptime: 2),
            policy: p
        )
        let window = try #require(endResult.learningWindow)
        #expect(window.startSOC.percentage == 59)
        #expect(window.endSOC.percentage == 56)
        #expect(window.distanceMeters == 300)
    }

    @Test("distance before the first verified post-gap SoC anchor is discarded")
    func preAnchorDistanceAfterNonAuthoritativeBoundaryIsDiscarded() throws {
        var pipeline = BatteryAdaptiveRangeLearningPipeline()
        let p = try policy()

        _ = try pipeline.acceptBatteryObservation(
            observation(80, uptime: 100),
            policy: p
        )
        try pipeline.recordDistance(deltaMeters: 500)
        pipeline.markUnobservedInterval()

        let boundary = try observation(
            60,
            role: .stockAppCorrelationAnchor,
            uptime: 1,
            continuity: .afterUnobservedInterval
        )
        let boundaryResult = try pipeline.acceptBatteryObservation(boundary, policy: p)
        #expect(boundaryResult.action == .resetContinuity)
        #expect(pipeline.windowAssembler.anchorSOC == nil)

        try pipeline.recordDistance(deltaMeters: 400)
        #expect(pipeline.windowAssembler.accumulatedDistanceMeters == 400)

        let anchorResult = try pipeline.acceptBatteryObservation(
            observation(59, uptime: 2),
            policy: p
        )
        #expect(anchorResult.learningWindow == nil)
        #expect(pipeline.windowAssembler.anchorSOC?.percentage == 59)
        #expect(pipeline.windowAssembler.latestAuthoritativeSOC?.percentage == 59)
        #expect(pipeline.windowAssembler.accumulatedDistanceMeters == 0)

        try pipeline.recordDistance(deltaMeters: 300)
        let endResult = try pipeline.acceptBatteryObservation(
            observation(56, uptime: 3),
            policy: p
        )
        let window = try #require(endResult.learningWindow)

        #expect(window.startSOC.percentage == 59)
        #expect(window.endSOC.percentage == 56)
        #expect(window.distanceMeters == 300)
    }

    @Test("spontaneous explicit boundary can start a lower-uptime epoch and resets assembly")
    func spontaneousBoundaryStartsFreshLowerUptimeEpoch() throws {
        var pipeline = BatteryAdaptiveRangeLearningPipeline()
        let p = try policy(minimumConsumedPercentagePoints: 10, minimumDistanceMeters: 1_000)

        _ = try pipeline.acceptBatteryObservation(
            observation(80, uptime: 100),
            policy: p
        )
        try pipeline.recordDistance(deltaMeters: 200, coverage: .partial)
        pipeline.recordTransportGap()

        let spontaneousBoundary = try observation(
            60,
            role: .stockAppCorrelationAnchor,
            uptime: 1,
            continuity: .afterUnobservedInterval
        )
        let result = try pipeline.acceptBatteryObservation(spontaneousBoundary, policy: p)

        #expect(result.action == .resetContinuity)
        #expect(result.learningWindow == nil)
        #expect(pipeline.evidenceBridge.streamValidator.requiresContinuityBoundary == false)
        #expect(pipeline.evidenceBridge.streamValidator.lastAcceptedUptimeNanoseconds == 1)
        #expect(pipeline.windowAssembler.anchorSOC == nil)
        #expect(pipeline.windowAssembler.latestAuthoritativeSOC == nil)
        #expect(pipeline.windowAssembler.accumulatedDistanceMeters == 0)
        #expect(pipeline.windowAssembler.distanceCoverage == .complete)
        #expect(pipeline.windowAssembler.transportGapOccurred == false)
    }

    @Test("in-span measured recovery rebases using latest authoritative SoC")
    func measuredRecoveryRebasesThroughPipeline() throws {
        var pipeline = BatteryAdaptiveRangeLearningPipeline()
        let p = try policy(minimumConsumedPercentagePoints: 3, minimumDistanceMeters: 1_000)

        _ = try pipeline.acceptBatteryObservation(
            observation(80, uptime: 1),
            policy: p
        )
        try pipeline.recordDistance(deltaMeters: 500)

        let dropResult = try pipeline.acceptBatteryObservation(
            observation(77, uptime: 2),
            policy: p
        )
        #expect(dropResult.learningWindow == nil)
        #expect(pipeline.windowAssembler.anchorSOC?.percentage == 80)
        #expect(pipeline.windowAssembler.latestAuthoritativeSOC?.percentage == 77)
        #expect(pipeline.windowAssembler.accumulatedDistanceMeters == 500)

        try pipeline.recordDistance(deltaMeters: 500)
        let recoveryResult = try pipeline.acceptBatteryObservation(
            observation(79, uptime: 3),
            policy: p
        )

        #expect(recoveryResult.learningWindow == nil)
        #expect(pipeline.windowAssembler.anchorSOC?.percentage == 79)
        #expect(pipeline.windowAssembler.latestAuthoritativeSOC?.percentage == 79)
        #expect(pipeline.windowAssembler.accumulatedDistanceMeters == 0)

        try pipeline.recordDistance(deltaMeters: 1_000)
        let cleanResult = try pipeline.acceptBatteryObservation(
            observation(76, uptime: 4),
            policy: p
        )
        let cleanWindow = try #require(cleanResult.learningWindow)

        #expect(cleanWindow.startSOC.percentage == 79)
        #expect(cleanWindow.endSOC.percentage == 76)
        #expect(cleanWindow.distanceMeters == 1_000)
    }

    @Test("continuous non-authoritative SoC cannot advance latest authoritative cursor")
    func nonAuthoritativeSOCDoesNotAdvanceLatestCursor() throws {
        var pipeline = BatteryAdaptiveRangeLearningPipeline()
        let p = try policy(minimumConsumedPercentagePoints: 10, minimumDistanceMeters: 1_000)

        _ = try pipeline.acceptBatteryObservation(
            observation(80, uptime: 1),
            policy: p
        )
        try pipeline.recordDistance(deltaMeters: 200)

        let stock = try observation(
            50,
            role: .stockAppCorrelationAnchor,
            uptime: 2
        )
        let result = try pipeline.acceptBatteryObservation(stock, policy: p)

        #expect(result.action == .ignore)
        #expect(pipeline.windowAssembler.anchorSOC?.percentage == 80)
        #expect(pipeline.windowAssembler.latestAuthoritativeSOC?.percentage == 80)
        #expect(pipeline.windowAssembler.accumulatedDistanceMeters == 200)
    }
}
