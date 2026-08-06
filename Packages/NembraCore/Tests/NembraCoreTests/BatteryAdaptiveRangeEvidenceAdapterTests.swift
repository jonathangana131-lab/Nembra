import Foundation
import Testing
@testable import NembraCore

@Suite("Battery evidence to adaptive range bridge")
struct BatteryAdaptiveRangeEvidenceAdapterTests {
    private func observation(
        value: BatterySemanticValue,
        role: BatteryEvidenceRole,
        uptime: UInt64 = 100,
        continuity: BatteryEvidenceContinuity = .continuous
    ) throws -> BatteryEvidenceObservation {
        try BatteryEvidenceObservation(
            value: value,
            role: role,
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: Date(timeIntervalSince1970: 1_000),
            continuity: continuity
        )
    }

    private func policy(
        minimumConsumedPercentagePoints: Double = 3,
        minimumDistanceMeters: Double = 100
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

    @Test("verified continuous SoC becomes authoritative adaptive-range evidence")
    func verifiedSOCMapsExactly() throws {
        let source = try observation(
            value: BatterySemanticValue.stateOfChargePercent(73.5),
            role: .verifiedVehicleMeasurement,
            uptime: 42
        )

        let action = try BatteryAdaptiveRangeEvidenceAdapter.action(for: source)
        guard case let .ingestSOC(reading) = action else {
            Issue.record("Expected continuous verified SoC to be ingested")
            return
        }

        #expect(reading.percentage == 73.5)
        #expect(reading.provenance == .authoritativeMeasurement)
        #expect(reading.receivedAtUptimeNanoseconds == 42)
    }

    @Test("all non-verified continuous SoC roles remain outside production range learning")
    func nonVerifiedSOCRolesAreIgnored() throws {
        let roles: [BatteryEvidenceRole] = [
            .stockAppCorrelationAnchor,
            .simulationFixture,
            .derivedEstimate,
            .presentationOnly
        ]

        for role in roles {
            let source = try observation(
                value: BatterySemanticValue.stateOfChargePercent(61),
                role: role
            )
            let action = try BatteryAdaptiveRangeEvidenceAdapter.action(for: source)
            #expect(action == .ignore)
        }
    }

    @Test("an explicit continuity gap resets range even when the value is not authoritative")
    func nonVerifiedGapMarkersStillResetContinuity() throws {
        let roles: [BatteryEvidenceRole] = [
            .stockAppCorrelationAnchor,
            .simulationFixture,
            .derivedEstimate,
            .presentationOnly
        ]

        for role in roles {
            let source = try observation(
                value: BatterySemanticValue.stateOfChargePercent(60),
                role: role,
                continuity: .afterUnobservedInterval
            )
            let action = try BatteryAdaptiveRangeEvidenceAdapter.action(for: source)
            #expect(action == .resetContinuity)
        }
    }

    @Test("verified non-SoC battery fields never become percentage learning evidence")
    func verifiedElectricalValuesDoNotTrainRange() throws {
        let values: [BatterySemanticValue] = [
            try BatterySemanticValue.voltageVolts(39.8),
            try BatterySemanticValue.currentAmps(-2.5),
            try BatterySemanticValue.powerWatts(98),
            try BatterySemanticValue.chargingState(false)
        ]

        for value in values {
            let source = try observation(
                value: value,
                role: .verifiedVehicleMeasurement
            )
            let action = try BatteryAdaptiveRangeEvidenceAdapter.action(for: source)
            #expect(action == .ignore)
        }
    }

    @Test("every verified non-SoC first value after a gap resets range continuity")
    func verifiedElectricalGapResetsContinuity() throws {
        let values: [BatterySemanticValue] = [
            try BatterySemanticValue.voltageVolts(40.2),
            try BatterySemanticValue.currentAmps(-1.5),
            try BatterySemanticValue.powerWatts(60),
            try BatterySemanticValue.chargingState(true)
        ]

        for value in values {
            let source = try observation(
                value: value,
                role: .verifiedVehicleMeasurement,
                continuity: .afterUnobservedInterval
            )
            let action = try BatteryAdaptiveRangeEvidenceAdapter.action(for: source)
            #expect(action == .resetContinuity)
        }
    }

    @Test("verified non-SoC gap can reset before a later continuous SoC becomes clean evidence")
    func verifiedNonSOCGapThenSOCProducesSeparateActions() throws {
        let firstAfterGap = try observation(
            value: BatterySemanticValue.voltageVolts(40.2),
            role: .verifiedVehicleMeasurement,
            uptime: 4_999,
            continuity: .afterUnobservedInterval
        )
        let laterSOC = try observation(
            value: BatterySemanticValue.stateOfChargePercent(52.25),
            role: .verifiedVehicleMeasurement,
            uptime: 5_000,
            continuity: .continuous
        )

        let resetAction = try BatteryAdaptiveRangeEvidenceAdapter.action(for: firstAfterGap)
        let socAction = try BatteryAdaptiveRangeEvidenceAdapter.action(for: laterSOC)

        #expect(resetAction == .resetContinuity)
        guard case let .ingestSOC(reading) = socAction else {
            Issue.record("Expected later continuous verified SoC to become clean evidence")
            return
        }
        #expect(reading.percentage == 52.25)
        #expect(reading.receivedAtUptimeNanoseconds == 5_000)
    }

    @Test("verified SoC after an unobserved interval resets then establishes new evidence")
    func verifiedSOCAfterGapResetsAndIngests() throws {
        let source = try observation(
            value: BatterySemanticValue.stateOfChargePercent(52.25),
            role: .verifiedVehicleMeasurement,
            uptime: 5_000,
            continuity: .afterUnobservedInterval
        )

        let action = try BatteryAdaptiveRangeEvidenceAdapter.action(for: source)
        guard case let .resetContinuityAndIngestSOC(reading) = action else {
            Issue.record("Expected reset plus new verified SoC evidence")
            return
        }

        #expect(reading.percentage == 52.25)
        #expect(reading.provenance == .authoritativeMeasurement)
        #expect(reading.receivedAtUptimeNanoseconds == 5_000)
    }

    @Test("valid empty and full SoC boundaries survive the bridge unchanged")
    func socBoundariesArePreserved() throws {
        for percentage in [0.0, 100.0] {
            let source = try observation(
                value: BatterySemanticValue.stateOfChargePercent(percentage),
                role: .verifiedVehicleMeasurement
            )

            let action = try BatteryAdaptiveRangeEvidenceAdapter.action(for: source)
            guard case let .ingestSOC(reading) = action else {
                Issue.record("Expected boundary SoC to remain eligible")
                continue
            }
            #expect(reading.percentage == percentage)
        }
    }

    @Test("wall clock metadata is not substituted for process-local range ordering")
    func bridgeUsesMonotonicUptimeEvidence() throws {
        let source = try BatteryEvidenceObservation(
            value: BatterySemanticValue.stateOfChargePercent(48),
            role: .verifiedVehicleMeasurement,
            receivedAtUptimeNanoseconds: 9_999,
            receivedAtDate: Date(timeIntervalSince1970: 10),
            continuity: .continuous
        )

        let action = try BatteryAdaptiveRangeEvidenceAdapter.action(for: source)
        guard case let .ingestSOC(reading) = action else {
            Issue.record("Expected verified SoC evidence")
            return
        }
        #expect(reading.receivedAtUptimeNanoseconds == 9_999)
    }

    @Test("stateful bridge requires an explicit first-post-gap boundary")
    func statefulBridgeFailsClosedWhenBoundaryIsMissing() throws {
        var bridge = BatteryAdaptiveRangeEvidenceBridge()
        bridge.markUnobservedInterval()

        let source = try observation(
            value: BatterySemanticValue.stateOfChargePercent(51),
            role: .verifiedVehicleMeasurement,
            uptime: 5,
            continuity: .continuous
        )

        #expect(throws: BatteryEvidenceStreamValidationError.missingContinuityBoundary) {
            _ = try bridge.accept(source)
        }
        #expect(bridge.streamValidator.requiresContinuityBoundary)
        #expect(bridge.streamValidator.lastAcceptedUptimeNanoseconds == nil)
    }

    @Test("non-authoritative first-post-gap evidence resets learning and starts a fresh stream epoch")
    func nonAuthoritativeBoundaryCannotBeDroppedByStatefulBridge() throws {
        var bridge = BatteryAdaptiveRangeEvidenceBridge()
        bridge.markUnobservedInterval()

        let boundary = try observation(
            value: BatterySemanticValue.stateOfChargePercent(60),
            role: .stockAppCorrelationAnchor,
            uptime: 4,
            continuity: .afterUnobservedInterval
        )
        let laterVerifiedSOC = try observation(
            value: BatterySemanticValue.stateOfChargePercent(59),
            role: .verifiedVehicleMeasurement,
            uptime: 5,
            continuity: .continuous
        )

        let boundaryAction = try bridge.accept(boundary)
        let socAction = try bridge.accept(laterVerifiedSOC)

        #expect(boundaryAction == .resetContinuity)
        #expect(bridge.streamValidator.requiresContinuityBoundary == false)
        guard case let .ingestSOC(reading) = socAction else {
            Issue.record("Expected later verified SoC to enter the fresh epoch")
            return
        }
        #expect(reading.percentage == 59)
    }

    @Test("stateful bridge rejects uptime regression atomically before range ingest")
    func statefulBridgeRejectsUptimeRegressionAtomically() throws {
        var bridge = BatteryAdaptiveRangeEvidenceBridge()
        let first = try observation(
            value: BatterySemanticValue.stateOfChargePercent(70),
            role: .verifiedVehicleMeasurement,
            uptime: 100
        )
        let regressed = try observation(
            value: BatterySemanticValue.stateOfChargePercent(69),
            role: .verifiedVehicleMeasurement,
            uptime: 99
        )

        _ = try bridge.accept(first)
        #expect(throws: BatteryEvidenceStreamValidationError.nonMonotonicUptime) {
            _ = try bridge.accept(regressed)
        }
        #expect(bridge.streamValidator.lastAcceptedUptimeNanoseconds == 100)
    }

    @Test("equal uptime battery fields from one callback remain valid and only SoC is ingested")
    func statefulBridgeAllowsEqualUptimeFields() throws {
        var bridge = BatteryAdaptiveRangeEvidenceBridge()
        let voltage = try observation(
            value: BatterySemanticValue.voltageVolts(40.0),
            role: .verifiedVehicleMeasurement,
            uptime: 200
        )
        let soc = try observation(
            value: BatterySemanticValue.stateOfChargePercent(68),
            role: .verifiedVehicleMeasurement,
            uptime: 200
        )

        let voltageAction = try bridge.accept(voltage)
        let socAction = try bridge.accept(soc)

        #expect(voltageAction == .ignore)
        guard case let .ingestSOC(reading) = socAction else {
            Issue.record("Expected same-callback SoC to remain eligible")
            return
        }
        #expect(reading.percentage == 68)
        #expect(bridge.streamValidator.lastAcceptedUptimeNanoseconds == 200)
    }

    @Test("pipeline emits a learning window only from verified SoC plus classified distance")
    func pipelineEmitsLearningWindow() throws {
        var pipeline = BatteryAdaptiveRangeLearningPipeline()
        let p = try policy(minimumConsumedPercentagePoints: 3, minimumDistanceMeters: 300)

        let start = try observation(
            value: BatterySemanticValue.stateOfChargePercent(80),
            role: .verifiedVehicleMeasurement,
            uptime: 1
        )
        let end = try observation(
            value: BatterySemanticValue.stateOfChargePercent(77),
            role: .verifiedVehicleMeasurement,
            uptime: 2
        )

        let startResult = try pipeline.acceptBatteryObservation(start, policy: p)
        #expect(startResult.learningWindow == nil)
        try pipeline.recordDistance(deltaMeters: 360, coverage: .complete)
        let endResult = try pipeline.acceptBatteryObservation(end, policy: p)

        guard let window = endResult.learningWindow else {
            Issue.record("Expected a complete learning window")
            return
        }
        #expect(window.startSOC.percentage == 80)
        #expect(window.endSOC.percentage == 77)
        #expect(window.distanceMeters == 360)
        #expect(window.distanceCoverage == .complete)
        #expect(window.transportGapOccurred == false)
    }

    @Test("known unobserved interval immediately discards pre-gap distance and anchor")
    func pipelineKnownGapDiscardsPreGapSpan() throws {
        var pipeline = BatteryAdaptiveRangeLearningPipeline()
        let p = try policy(minimumConsumedPercentagePoints: 3, minimumDistanceMeters: 300)

        let preGapAnchor = try observation(
            value: BatterySemanticValue.stateOfChargePercent(80),
            role: .verifiedVehicleMeasurement,
            uptime: 100
        )
        _ = try pipeline.acceptBatteryObservation(preGapAnchor, policy: p)
        try pipeline.recordDistance(deltaMeters: 500)

        pipeline.markUnobservedInterval()
        #expect(pipeline.windowAssembler.anchorSOC == nil)
        #expect(pipeline.windowAssembler.accumulatedDistanceMeters == 0)

        let boundary = try observation(
            value: BatterySemanticValue.stateOfChargePercent(60),
            role: .stockAppCorrelationAnchor,
            uptime: 1,
            continuity: .afterUnobservedInterval
        )
        let freshAnchor = try observation(
            value: BatterySemanticValue.stateOfChargePercent(59),
            role: .verifiedVehicleMeasurement,
            uptime: 2
        )
        let freshEnd = try observation(
            value: BatterySemanticValue.stateOfChargePercent(56),
            role: .verifiedVehicleMeasurement,
            uptime: 3
        )

        let boundaryResult = try pipeline.acceptBatteryObservation(boundary, policy: p)
        #expect(boundaryResult.action == .resetContinuity)
        #expect(boundaryResult.learningWindow == nil)

        _ = try pipeline.acceptBatteryObservation(freshAnchor, policy: p)
        try pipeline.recordDistance(deltaMeters: 300)
        let endResult = try pipeline.acceptBatteryObservation(freshEnd, policy: p)

        guard let window = endResult.learningWindow else {
            Issue.record("Expected only the fresh post-gap span to close")
            return
        }
        #expect(window.startSOC.percentage == 59)
        #expect(window.endSOC.percentage == 56)
        #expect(window.distanceMeters == 300)
    }

    @Test("continuous stock-app SoC cannot disturb an authoritative assembler span")
    func pipelineIgnoresContinuousStockAppSOC() throws {
        var pipeline = BatteryAdaptiveRangeLearningPipeline()
        let p = try policy()

        let anchor = try observation(
            value: BatterySemanticValue.stateOfChargePercent(80),
            role: .verifiedVehicleMeasurement,
            uptime: 1
        )
        let stockApp = try observation(
            value: BatterySemanticValue.stateOfChargePercent(62),
            role: .stockAppCorrelationAnchor,
            uptime: 2
        )

        _ = try pipeline.acceptBatteryObservation(anchor, policy: p)
        try pipeline.recordDistance(deltaMeters: 125)
        let result = try pipeline.acceptBatteryObservation(stockApp, policy: p)

        #expect(result.action == .ignore)
        #expect(result.learningWindow == nil)
        #expect(pipeline.windowAssembler.anchorSOC?.percentage == 80)
        #expect(pipeline.windowAssembler.accumulatedDistanceMeters == 125)
    }

    @Test("observed transport gap remains attached to emitted candidate rather than being erased")
    func pipelinePreservesObservedTransportGap() throws {
        var pipeline = BatteryAdaptiveRangeLearningPipeline()
        let p = try policy(minimumConsumedPercentagePoints: 3, minimumDistanceMeters: 300)

        let start = try observation(
            value: BatterySemanticValue.stateOfChargePercent(80),
            role: .verifiedVehicleMeasurement,
            uptime: 1
        )
        let end = try observation(
            value: BatterySemanticValue.stateOfChargePercent(77),
            role: .verifiedVehicleMeasurement,
            uptime: 2
        )

        _ = try pipeline.acceptBatteryObservation(start, policy: p)
        try pipeline.recordDistance(deltaMeters: 300)
        pipeline.recordTransportGap()
        let result = try pipeline.acceptBatteryObservation(end, policy: p)

        guard let window = result.learningWindow else {
            Issue.record("Expected tainted candidate to be preserved for model rejection")
            return
        }
        #expect(window.transportGapOccurred)
        #expect(window.distanceMeters == 300)
    }

    @Test("stream rejection leaves range-window state unchanged")
    func pipelineStreamFailureIsAtomic() throws {
        var pipeline = BatteryAdaptiveRangeLearningPipeline()
        let p = try policy()

        let anchor = try observation(
            value: BatterySemanticValue.stateOfChargePercent(80),
            role: .verifiedVehicleMeasurement,
            uptime: 100
        )
        let regressed = try observation(
            value: BatterySemanticValue.stateOfChargePercent(79),
            role: .verifiedVehicleMeasurement,
            uptime: 99
        )

        _ = try pipeline.acceptBatteryObservation(anchor, policy: p)
        try pipeline.recordDistance(deltaMeters: 200)

        #expect(throws: BatteryEvidenceStreamValidationError.nonMonotonicUptime) {
            _ = try pipeline.acceptBatteryObservation(regressed, policy: p)
        }

        #expect(pipeline.evidenceBridge.streamValidator.lastAcceptedUptimeNanoseconds == 100)
        #expect(pipeline.windowAssembler.anchorSOC?.percentage == 80)
        #expect(pipeline.windowAssembler.accumulatedDistanceMeters == 200)
    }

    @Test("assembler rejection after stream acceptance is atomic across both pipeline components")
    func pipelineAssemblerFailureIsAtomic() throws {
        var pipeline = BatteryAdaptiveRangeLearningPipeline()
        let p = try policy()

        let anchor = try observation(
            value: BatterySemanticValue.stateOfChargePercent(80),
            role: .verifiedVehicleMeasurement,
            uptime: 100
        )
        let duplicateTimestampSOC = try observation(
            value: BatterySemanticValue.stateOfChargePercent(79),
            role: .verifiedVehicleMeasurement,
            uptime: 100
        )

        _ = try pipeline.acceptBatteryObservation(anchor, policy: p)
        try pipeline.recordDistance(deltaMeters: 200)

        #expect(throws: BatteryRangeWindowAssemblyError.nonMonotonicAuthoritativeSOC) {
            _ = try pipeline.acceptBatteryObservation(duplicateTimestampSOC, policy: p)
        }

        #expect(pipeline.evidenceBridge.streamValidator.lastAcceptedUptimeNanoseconds == 100)
        #expect(pipeline.windowAssembler.anchorSOC?.percentage == 80)
        #expect(pipeline.windowAssembler.accumulatedDistanceMeters == 200)
    }
}
