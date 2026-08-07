import Foundation
import Testing
@testable import NembraCore

@Suite("Battery adaptive range same-callback evidence")
struct BatteryAdaptiveRangeSameCallbackTests {
    private func policy() throws -> AdaptiveBatteryRangePolicy {
        try AdaptiveBatteryRangePolicy(
            minimumConsumedPercentagePoints: 3,
            minimumDistanceMeters: 300,
            recentWindowCapacity: 3,
            recentWeight: 0.5,
            outlierLowerEfficiencyRatio: 0.4,
            outlierUpperEfficiencyRatio: 2.5,
            estimateDeadbandFraction: 0.05,
            estimateSmoothingFactor: 0.25,
            provisionalEfficiencyMetersPerPercentagePoint: nil,
            lowSOCCautionThresholdPercent: nil,
            lowConfidenceConsumedPercentagePoints: 10,
            normalConfidenceConsumedPercentagePoints: 30,
            highConfidenceConsumedPercentagePoints: 60
        )
    }

    private func observation(
        value: BatterySemanticValue,
        uptime: UInt64,
        continuity: BatteryEvidenceContinuity = .continuous
    ) throws -> BatteryEvidenceObservation {
        try BatteryEvidenceObservation(
            value: value,
            role: .verifiedVehicleMeasurement,
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: Date(timeIntervalSince1970: 1_000),
            continuity: continuity
        )
    }

    @Test("verified voltage first at one callback uptime cannot block verified SoC from closing the window")
    func voltageThenSOCAtSameUptimeClosesCandidate() throws {
        var pipeline = BatteryAdaptiveRangeLearningPipeline()
        let p = try policy()

        _ = try pipeline.acceptBatteryObservation(
            observation(value: BatterySemanticValue.stateOfChargePercent(80), uptime: 100),
            policy: p
        )
        try pipeline.recordDistance(deltaMeters: 300, coverage: .complete)

        let voltageResult = try pipeline.acceptBatteryObservation(
            observation(value: try BatterySemanticValue.voltageVolts(40.0), uptime: 200),
            policy: p
        )
        #expect(voltageResult.disposition == .ignored)
        #expect(voltageResult.candidateLearningWindow == nil)
        #expect(pipeline.evidenceBridge.streamValidator.lastAcceptedUptimeNanoseconds == 200)
        #expect(pipeline.windowAssembler.latestAuthoritativeSOC?.percentage == 80)
        #expect(pipeline.windowAssembler.accumulatedDistanceMeters == 300)

        let socResult = try pipeline.acceptBatteryObservation(
            observation(value: BatterySemanticValue.stateOfChargePercent(77), uptime: 200),
            policy: p
        )
        let candidate = try #require(socResult.candidateLearningWindow)

        #expect(socResult.disposition == .authoritativeSOCIngested)
        #expect(candidate.startSOC.percentage == 80)
        #expect(candidate.endSOC.percentage == 77)
        #expect(candidate.startSOC.receivedAtUptimeNanoseconds == 100)
        #expect(candidate.endSOC.receivedAtUptimeNanoseconds == 200)
        #expect(candidate.distanceMeters == 300)
        #expect(candidate.distanceCoverage == .complete)
        #expect(candidate.transportGapOccurred == false)
        #expect(pipeline.evidenceBridge.streamValidator.lastAcceptedUptimeNanoseconds == 200)
        #expect(pipeline.windowAssembler.anchorSOC?.percentage == 77)
        #expect(pipeline.windowAssembler.accumulatedDistanceMeters == 0)
    }

    @Test("repeated boundary tags from one resumed callback reset once then accept same-uptime SoC")
    func voltageGapBoundaryThenSOCBoundaryAtSameUptimeReanchorsCleanly() throws {
        var pipeline = BatteryAdaptiveRangeLearningPipeline()
        let p = try policy()

        _ = try pipeline.acceptBatteryObservation(
            observation(value: BatterySemanticValue.stateOfChargePercent(80), uptime: 100),
            policy: p
        )
        try pipeline.recordDistance(deltaMeters: 500, coverage: .partial)
        pipeline.recordTransportGap()

        let voltageBoundary = try pipeline.acceptBatteryObservation(
            observation(
                value: try BatterySemanticValue.voltageVolts(39.5),
                uptime: 1,
                continuity: .afterUnobservedInterval
            ),
            policy: p
        )

        #expect(voltageBoundary.disposition == .continuityReset)
        #expect(voltageBoundary.candidateLearningWindow == nil)
        #expect(pipeline.evidenceBridge.lastContinuityResetReceiptUptimeNanoseconds == 1)
        #expect(pipeline.windowAssembler.anchorSOC == nil)
        #expect(pipeline.windowAssembler.accumulatedDistanceMeters == 0)
        #expect(pipeline.windowAssembler.distanceCoverage == .complete)
        #expect(pipeline.windowAssembler.transportGapOccurred == false)

        let socAtSameCallback = try pipeline.acceptBatteryObservation(
            observation(
                value: BatterySemanticValue.stateOfChargePercent(59),
                uptime: 1,
                continuity: .afterUnobservedInterval
            ),
            policy: p
        )

        #expect(socAtSameCallback.disposition == .authoritativeSOCIngested)
        #expect(socAtSameCallback.candidateLearningWindow == nil)
        #expect(pipeline.evidenceBridge.streamValidator.lastAcceptedUptimeNanoseconds == 1)
        #expect(pipeline.evidenceBridge.lastContinuityResetReceiptUptimeNanoseconds == 1)
        #expect(pipeline.windowAssembler.anchorSOC?.percentage == 59)
        #expect(pipeline.windowAssembler.latestAuthoritativeSOC?.percentage == 59)
        #expect(pipeline.windowAssembler.accumulatedDistanceMeters == 0)

        try pipeline.recordDistance(deltaMeters: 300, coverage: .complete)
        let endResult = try pipeline.acceptBatteryObservation(
            observation(value: BatterySemanticValue.stateOfChargePercent(56), uptime: 2),
            policy: p
        )
        let candidate = try #require(endResult.candidateLearningWindow)

        #expect(candidate.startSOC.percentage == 59)
        #expect(candidate.endSOC.percentage == 56)
        #expect(candidate.distanceMeters == 300)
        #expect(candidate.distanceCoverage == .complete)
        #expect(candidate.transportGapOccurred == false)
        #expect(pipeline.evidenceBridge.lastContinuityResetReceiptUptimeNanoseconds == nil)
    }

    @Test("verified SoC first at one callback uptime is not disturbed by later verified voltage")
    func SOCThenVoltageAtSameUptimePreservesNewAnchor() throws {
        var pipeline = BatteryAdaptiveRangeLearningPipeline()
        let p = try policy()

        _ = try pipeline.acceptBatteryObservation(
            observation(value: BatterySemanticValue.stateOfChargePercent(80), uptime: 100),
            policy: p
        )
        try pipeline.recordDistance(deltaMeters: 300, coverage: .complete)

        let socResult = try pipeline.acceptBatteryObservation(
            observation(value: BatterySemanticValue.stateOfChargePercent(77), uptime: 200),
            policy: p
        )
        let candidate = try #require(socResult.candidateLearningWindow)
        #expect(candidate.startSOC.percentage == 80)
        #expect(candidate.endSOC.percentage == 77)
        #expect(pipeline.windowAssembler.anchorSOC?.percentage == 77)
        #expect(pipeline.windowAssembler.accumulatedDistanceMeters == 0)

        let voltageResult = try pipeline.acceptBatteryObservation(
            observation(value: try BatterySemanticValue.voltageVolts(40.0), uptime: 200),
            policy: p
        )

        #expect(voltageResult.disposition == .ignored)
        #expect(voltageResult.candidateLearningWindow == nil)
        #expect(pipeline.evidenceBridge.streamValidator.lastAcceptedUptimeNanoseconds == 200)
        #expect(pipeline.windowAssembler.anchorSOC?.percentage == 77)
        #expect(pipeline.windowAssembler.latestAuthoritativeSOC?.percentage == 77)
        #expect(pipeline.windowAssembler.accumulatedDistanceMeters == 0)
        #expect(pipeline.windowAssembler.distanceCoverage == .complete)
        #expect(pipeline.windowAssembler.transportGapOccurred == false)
    }

    @Test("same-receipt non-SoC boundary after SoC boundary cannot erase the fresh anchor")
    func SOCBoundaryThenVoltageBoundaryAtSameUptimePreservesAnchor() throws {
        var pipeline = BatteryAdaptiveRangeLearningPipeline()
        let p = try policy()

        _ = try pipeline.acceptBatteryObservation(
            observation(value: BatterySemanticValue.stateOfChargePercent(80), uptime: 100),
            policy: p
        )
        try pipeline.recordDistance(deltaMeters: 500, coverage: .partial)
        pipeline.recordTransportGap()

        let socBoundary = try pipeline.acceptBatteryObservation(
            observation(
                value: BatterySemanticValue.stateOfChargePercent(59),
                uptime: 1,
                continuity: .afterUnobservedInterval
            ),
            policy: p
        )
        #expect(socBoundary.disposition == .continuityResetAndAuthoritativeSOCIngested)
        #expect(pipeline.windowAssembler.anchorSOC?.percentage == 59)
        #expect(pipeline.evidenceBridge.lastContinuityResetReceiptUptimeNanoseconds == 1)

        let voltageBoundary = try pipeline.acceptBatteryObservation(
            observation(
                value: try BatterySemanticValue.voltageVolts(39.5),
                uptime: 1,
                continuity: .afterUnobservedInterval
            ),
            policy: p
        )
        #expect(voltageBoundary.disposition == .ignored)
        #expect(voltageBoundary.candidateLearningWindow == nil)
        #expect(pipeline.windowAssembler.anchorSOC?.percentage == 59)
        #expect(pipeline.windowAssembler.latestAuthoritativeSOC?.percentage == 59)
        #expect(pipeline.windowAssembler.accumulatedDistanceMeters == 0)
        #expect(pipeline.windowAssembler.distanceCoverage == .complete)
        #expect(pipeline.windowAssembler.transportGapOccurred == false)

        try pipeline.recordDistance(deltaMeters: 300, coverage: .complete)
        let endResult = try pipeline.acceptBatteryObservation(
            observation(value: BatterySemanticValue.stateOfChargePercent(56), uptime: 2),
            policy: p
        )
        let candidate = try #require(endResult.candidateLearningWindow)
        #expect(candidate.startSOC.percentage == 59)
        #expect(candidate.endSOC.percentage == 56)
        #expect(candidate.distanceMeters == 300)
        #expect(candidate.transportGapOccurred == false)
    }

    @Test("known new gap clears same-receipt boundary coalescing state")
    func markUnobservedIntervalForcesNewBoundaryEvenAtSameNumericUptime() throws {
        var pipeline = BatteryAdaptiveRangeLearningPipeline()
        let p = try policy()

        let firstBoundary = try pipeline.acceptBatteryObservation(
            observation(
                value: BatterySemanticValue.stateOfChargePercent(59),
                uptime: 1,
                continuity: .afterUnobservedInterval
            ),
            policy: p
        )
        #expect(firstBoundary.disposition == .continuityResetAndAuthoritativeSOCIngested)
        #expect(pipeline.evidenceBridge.lastContinuityResetReceiptUptimeNanoseconds == 1)
        #expect(pipeline.windowAssembler.anchorSOC?.percentage == 59)

        pipeline.markUnobservedInterval()
        #expect(pipeline.evidenceBridge.streamValidator.requiresContinuityBoundary)
        #expect(pipeline.evidenceBridge.lastContinuityResetReceiptUptimeNanoseconds == nil)
        #expect(pipeline.windowAssembler.anchorSOC == nil)

        let secondBoundary = try pipeline.acceptBatteryObservation(
            observation(
                value: BatterySemanticValue.stateOfChargePercent(58),
                uptime: 1,
                continuity: .afterUnobservedInterval
            ),
            policy: p
        )

        #expect(secondBoundary.disposition == .continuityResetAndAuthoritativeSOCIngested)
        #expect(pipeline.evidenceBridge.lastContinuityResetReceiptUptimeNanoseconds == 1)
        #expect(pipeline.windowAssembler.anchorSOC?.percentage == 58)
        #expect(pipeline.windowAssembler.latestAuthoritativeSOC?.percentage == 58)
    }
}
