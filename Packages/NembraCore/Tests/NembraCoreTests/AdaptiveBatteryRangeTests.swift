import Foundation
import Testing
@testable import NembraCore

@Suite("Adaptive battery range")
struct AdaptiveBatteryRangeTests {
    private func reading(
        _ percentage: Double,
        provenance: BatterySOCProvenance = .authoritativeMeasurement,
        uptime: UInt64
    ) throws -> BatterySOCReading {
        try BatterySOCReading(
            percentage: percentage,
            provenance: provenance,
            receivedAtUptimeNanoseconds: uptime
        )
    }

    private func window(
        distanceMeters: Double,
        startPercentage: Double,
        endPercentage: Double,
        startProvenance: BatterySOCProvenance = .authoritativeMeasurement,
        endProvenance: BatterySOCProvenance = .authoritativeMeasurement,
        startUptime: UInt64 = 1,
        endUptime: UInt64 = 2
    ) throws -> BatteryRangeLearningWindow {
        try BatteryRangeLearningWindow(
            distanceMeters: distanceMeters,
            startSOC: reading(startPercentage, provenance: startProvenance, uptime: startUptime),
            endSOC: reading(endPercentage, provenance: endProvenance, uptime: endUptime)
        )
    }

    private func policy(
        minimumConsumedPercentagePoints: Double = 3,
        minimumDistanceMeters: Double = 100,
        recentWindowCapacity: Int = 2,
        recentWeight: Double = 0.5,
        outlierLowerEfficiencyRatio: Double = 0.4,
        outlierUpperEfficiencyRatio: Double = 2.5,
        estimateDeadbandFraction: Double = 0.05,
        estimateSmoothingFactor: Double = 0.25,
        lowSOCCautionThresholdPercent: Double? = nil,
        lowSOCEfficiencyMultiplier: Double? = nil,
        lowConfidenceConsumedPercentagePoints: Double = 10,
        normalConfidenceConsumedPercentagePoints: Double = 30,
        highConfidenceConsumedPercentagePoints: Double = 60
    ) throws -> AdaptiveBatteryRangePolicy {
        try AdaptiveBatteryRangePolicy(
            minimumConsumedPercentagePoints: minimumConsumedPercentagePoints,
            minimumDistanceMeters: minimumDistanceMeters,
            recentWindowCapacity: recentWindowCapacity,
            recentWeight: recentWeight,
            outlierLowerEfficiencyRatio: outlierLowerEfficiencyRatio,
            outlierUpperEfficiencyRatio: outlierUpperEfficiencyRatio,
            estimateDeadbandFraction: estimateDeadbandFraction,
            estimateSmoothingFactor: estimateSmoothingFactor,
            lowSOCCautionThresholdPercent: lowSOCCautionThresholdPercent,
            lowSOCEfficiencyMultiplier: lowSOCEfficiencyMultiplier,
            lowConfidenceConsumedPercentagePoints: lowConfidenceConsumedPercentagePoints,
            normalConfidenceConsumedPercentagePoints: normalConfidenceConsumedPercentagePoints,
            highConfidenceConsumedPercentagePoints: highConfidenceConsumedPercentagePoints
        )
    }

    @Test("SoC, window, and policy validation fail closed")
    func validation() throws {
        #expect(throws: BatteryRangeValidationError.self) {
            _ = try BatterySOCReading(
                percentage: 101,
                provenance: .authoritativeMeasurement,
                receivedAtUptimeNanoseconds: 1
            )
        }
        #expect(throws: BatteryRangeValidationError.self) {
            _ = try window(
                distanceMeters: 100,
                startPercentage: 80,
                endPercentage: 70,
                startUptime: 2,
                endUptime: 2
            )
        }
        #expect(throws: BatteryRangeValidationError.self) {
            _ = try policy(recentWindowCapacity: 0)
        }
        #expect(throws: BatteryRangeValidationError.self) {
            _ = try policy(
                lowSOCCautionThresholdPercent: 20,
                lowSOCEfficiencyMultiplier: nil
            )
        }
    }

    @Test("estimated SoC is representable but never trains the model")
    func estimatedSOCDoesNotTrain() throws {
        var model = AdaptiveBatteryRangeModel()
        let result = model.ingest(
            try window(
                distanceMeters: 2_000,
                startPercentage: 80,
                endPercentage: 60,
                startProvenance: .estimate
            ),
            policy: try policy()
        )

        #expect(result.disposition == .rejected(.nonAuthoritativeSOC))
        #expect(result.sample == nil)
        #expect(model.hasLearnedEfficiency == false)
        #expect(model.acceptedWindowCount == 0)
    }

    @Test("tiny percentage drops are not treated as trustworthy efficiency windows")
    func tinyWindowRejected() throws {
        var model = AdaptiveBatteryRangeModel()
        let result = model.ingest(
            try window(distanceMeters: 250, startPercentage: 80, endPercentage: 79),
            policy: try policy(minimumConsumedPercentagePoints: 3)
        )

        #expect(result.disposition == .rejected(.insufficientSOCConsumption))
        #expect(model.historicalConsumedPercentagePoints == 0)
    }

    @Test("meaningful measured window teaches distance per percentage point")
    func meaningfulWindowLearns() throws {
        var model = AdaptiveBatteryRangeModel()
        let result = model.ingest(
            try window(distanceMeters: 2_400, startPercentage: 80, endPercentage: 60),
            policy: try policy()
        )

        #expect(result.disposition == .accepted)
        #expect(abs((result.sample?.metersPerPercentagePoint ?? 0) - 120) < 0.000_001)
        #expect(abs((model.historicalEfficiencyMetersPerPercentagePoint ?? 0) - 120) < 0.000_001)
        #expect(model.historicalConsumedPercentagePoints == 20)
        #expect(model.acceptedWindowCount == 1)
    }

    @Test("recent behavior can move the estimate without erasing long-term learning")
    func recentAndHistoricalBlend() throws {
        var model = AdaptiveBatteryRangeModel()
        let p = try policy(
            recentWindowCapacity: 1,
            recentWeight: 0.5,
            outlierUpperEfficiencyRatio: 3
        )

        _ = model.ingest(
            try window(distanceMeters: 2_000, startPercentage: 100, endPercentage: 80),
            policy: p
        )
        _ = model.ingest(
            try window(distanceMeters: 1_800, startPercentage: 80, endPercentage: 70),
            policy: p
        )

        let historical = model.historicalEfficiencyMetersPerPercentagePoint ?? 0
        let blended = model.blendedEfficiencyMetersPerPercentagePoint(using: p) ?? 0

        #expect(abs(historical - (3_800.0 / 30.0)) < 0.000_001)
        #expect(abs(blended - (((3_800.0 / 30.0) + 180.0) / 2.0)) < 0.000_001)
        #expect(blended > historical)
    }

    @Test("large efficiency outliers are rejected instead of poisoning history")
    func outlierRejected() throws {
        var model = AdaptiveBatteryRangeModel()
        let p = try policy(
            minimumConsumedPercentagePoints: 2,
            outlierLowerEfficiencyRatio: 0.5,
            outlierUpperEfficiencyRatio: 2
        )

        _ = model.ingest(
            try window(distanceMeters: 2_000, startPercentage: 80, endPercentage: 60),
            policy: p
        )
        let before = model

        let result = model.ingest(
            try window(distanceMeters: 900, startPercentage: 60, endPercentage: 58),
            policy: p
        )

        #expect(result.disposition == .rejected(.efficiencyOutlier))
        #expect(model == before)
    }

    @Test("range is unavailable until the scooter has learned real consumption")
    func coldStartStaysUnavailable() throws {
        let model = AdaptiveBatteryRangeModel()
        let estimate = model.estimateRemainingRange(
            at: try reading(80, uptime: 1),
            policy: try policy()
        )

        #expect(estimate == nil)
        #expect(model.typicalFullChargeRangeMeters(using: try policy()) == nil)
    }

    @Test("estimated display SoC stays classified while using learned efficiency")
    func estimatePreservesSOCProvenance() throws {
        var model = AdaptiveBatteryRangeModel()
        let p = try policy()
        _ = model.ingest(
            try window(distanceMeters: 2_000, startPercentage: 80, endPercentage: 60),
            policy: p
        )

        let estimate = model.estimateRemainingRange(
            at: try reading(50, provenance: .estimate, uptime: 3),
            policy: p
        )

        #expect(estimate?.socProvenance == .estimate)
        #expect(abs((estimate?.rawRemainingMeters ?? 0) - 5_000) < 0.000_001)
    }

    @Test("presentation deadband and smoothing avoid range bounce")
    func presentationSmoothing() throws {
        var model = AdaptiveBatteryRangeModel()
        let p = try policy(
            estimateDeadbandFraction: 0.05,
            estimateSmoothingFactor: 0.25
        )
        _ = model.ingest(
            try window(distanceMeters: 2_000, startPercentage: 80, endPercentage: 60),
            policy: p
        )

        let insideDeadband = model.estimateRemainingRange(
            at: try reading(97, uptime: 3),
            previousPresentedRemainingMeters: 10_000,
            policy: p
        )
        #expect(insideDeadband?.presentedRemainingMeters == 10_000)

        let smoothed = model.estimateRemainingRange(
            at: try reading(80, uptime: 4),
            previousPresentedRemainingMeters: 10_000,
            policy: p
        )
        #expect(abs((smoothed?.rawRemainingMeters ?? 0) - 8_000) < 0.000_001)
        #expect(abs((smoothed?.presentedRemainingMeters ?? 0) - 9_500) < 0.000_001)
    }

    @Test("low-SoC conservatism is opt-in until field evidence supports it")
    func lowSOCPolicyIsExplicit() throws {
        var model = AdaptiveBatteryRangeModel()
        let neutral = try policy()
        _ = model.ingest(
            try window(distanceMeters: 2_000, startPercentage: 80, endPercentage: 60),
            policy: neutral
        )

        let neutralEstimate = model.estimateRemainingRange(
            at: try reading(10, uptime: 3),
            policy: neutral
        )
        #expect(neutralEstimate?.lowSOCConservatismApplied == false)
        #expect(abs((neutralEstimate?.rawRemainingMeters ?? 0) - 1_000) < 0.000_001)

        let fieldBackedPolicy = try policy(
            lowSOCCautionThresholdPercent: 20,
            lowSOCEfficiencyMultiplier: 0.8
        )
        let conservativeEstimate = model.estimateRemainingRange(
            at: try reading(10, uptime: 4),
            policy: fieldBackedPolicy
        )

        #expect(conservativeEstimate?.lowSOCConservatismApplied == true)
        #expect(abs((conservativeEstimate?.rawRemainingMeters ?? 0) - 900) < 0.000_001)
    }

    @Test("confidence grows only from accepted authoritative percentage consumption")
    func confidenceUsesAcceptedEvidence() throws {
        var model = AdaptiveBatteryRangeModel()
        let p = try policy(
            minimumConsumedPercentagePoints: 5,
            lowConfidenceConsumedPercentagePoints: 10,
            normalConfidenceConsumedPercentagePoints: 20,
            highConfidenceConsumedPercentagePoints: 40
        )

        #expect(model.confidence(using: p) == .learning)

        _ = model.ingest(
            try window(distanceMeters: 500, startPercentage: 100, endPercentage: 95),
            policy: p
        )
        #expect(model.confidence(using: p) == .learning)

        _ = model.ingest(
            try window(distanceMeters: 500, startPercentage: 95, endPercentage: 90),
            policy: p
        )
        #expect(model.confidence(using: p) == .low)

        _ = model.ingest(
            try window(distanceMeters: 1_000, startPercentage: 90, endPercentage: 80),
            policy: p
        )
        #expect(model.confidence(using: p) == .normal)

        _ = model.ingest(
            try window(distanceMeters: 2_000, startPercentage: 80, endPercentage: 60),
            policy: p
        )
        #expect(model.confidence(using: p) == .high)
    }

    @Test("learning state is Codable for persistence across launches")
    func persistenceRoundTrip() throws {
        var model = AdaptiveBatteryRangeModel()
        let p = try policy()
        _ = model.ingest(
            try window(distanceMeters: 2_400, startPercentage: 80, endPercentage: 60),
            policy: p
        )

        let data = try JSONEncoder().encode(model)
        let decoded = try JSONDecoder().decode(AdaptiveBatteryRangeModel.self, from: data)

        #expect(decoded == model)
    }
}
