import Foundation

/// Classifies normalized state-of-charge values before the adaptive range model
/// is allowed to learn from them.
public enum BatterySOCProvenance: String, Codable, Sendable {
    case authoritativeMeasurement
    case estimate
}

public enum BatteryRangeValidationError: Error, Equatable, Sendable {
    case invalidSOCPercentage
    case invalidDistance
    case invalidTimestampOrder
    case invalidPolicy
    case invalidEvidenceRole
    case invalidEstimate
}

/// One normalized SoC reading.
///
/// The role-selecting initializer is package-scoped for Swift Package builds so focused tests
/// and trusted package integration can exercise the pure model, but file-scoped when the same
/// source is compiled directly into the app. Ordinary direct-source app files therefore cannot
/// assert `.authoritativeMeasurement` merely because they share a Swift module.
public struct BatterySOCReading: Equatable, Codable, Sendable {
    public let percentage: Double
    public let provenance: BatterySOCProvenance
    public let receivedAtUptimeNanoseconds: UInt64

#if SWIFT_PACKAGE
    package init(
        percentage: Double,
        provenance: BatterySOCProvenance,
        receivedAtUptimeNanoseconds: UInt64
    ) throws {
        guard percentage.isFinite, (0...100).contains(percentage) else {
            throw BatteryRangeValidationError.invalidSOCPercentage
        }
        self.percentage = percentage
        self.provenance = provenance
        self.receivedAtUptimeNanoseconds = receivedAtUptimeNanoseconds
    }
#else
    fileprivate init(
        percentage: Double,
        provenance: BatterySOCProvenance,
        receivedAtUptimeNanoseconds: UInt64
    ) throws {
        guard percentage.isFinite, (0...100).contains(percentage) else {
            throw BatteryRangeValidationError.invalidSOCPercentage
        }
        self.percentage = percentage
        self.provenance = provenance
        self.receivedAtUptimeNanoseconds = receivedAtUptimeNanoseconds
    }
#endif

    /// Generic/public construction is intentionally estimated-only.
    public static func estimated(
        percentage: Double,
        receivedAtUptimeNanoseconds: UInt64
    ) throws -> Self {
        try Self(
            percentage: percentage,
            provenance: .estimate,
            receivedAtUptimeNanoseconds: receivedAtUptimeNanoseconds
        )
    }

    public var isAuthoritativeMeasurement: Bool {
        provenance == .authoritativeMeasurement
    }
}

/// Coverage of the distance evidence attached to one battery-consumption window.
/// Only complete coverage is allowed to teach efficiency.
public enum BatteryRangeDistanceCoverage: String, Codable, Sendable {
    case complete
    case partial
    case unknown
}

/// A ride segment that can potentially teach the range model how far this
/// scooter travels for each authoritative battery percentage point consumed.
///
/// Direct-source app code cannot construct an authority-bearing window. Generic public
/// construction is estimated/non-authoritative only; package-trusted range assembly retains
/// package-scoped construction for focused tests and future evidence integration.
public struct BatteryRangeLearningWindow: Equatable, Codable, Sendable {
    public let distanceMeters: Double
    public let distanceCoverage: BatteryRangeDistanceCoverage
    public let transportGapOccurred: Bool
    public let startSOC: BatterySOCReading
    public let endSOC: BatterySOCReading

#if SWIFT_PACKAGE
    package init(
        distanceMeters: Double,
        distanceCoverage: BatteryRangeDistanceCoverage,
        transportGapOccurred: Bool,
        startSOC: BatterySOCReading,
        endSOC: BatterySOCReading
    ) throws {
        guard distanceMeters.isFinite, distanceMeters >= 0 else {
            throw BatteryRangeValidationError.invalidDistance
        }
        guard endSOC.receivedAtUptimeNanoseconds > startSOC.receivedAtUptimeNanoseconds else {
            throw BatteryRangeValidationError.invalidTimestampOrder
        }
        self.distanceMeters = distanceMeters
        self.distanceCoverage = distanceCoverage
        self.transportGapOccurred = transportGapOccurred
        self.startSOC = startSOC
        self.endSOC = endSOC
    }
#else
    fileprivate init(
        distanceMeters: Double,
        distanceCoverage: BatteryRangeDistanceCoverage,
        transportGapOccurred: Bool,
        startSOC: BatterySOCReading,
        endSOC: BatterySOCReading
    ) throws {
        guard distanceMeters.isFinite, distanceMeters >= 0 else {
            throw BatteryRangeValidationError.invalidDistance
        }
        guard endSOC.receivedAtUptimeNanoseconds > startSOC.receivedAtUptimeNanoseconds else {
            throw BatteryRangeValidationError.invalidTimestampOrder
        }
        self.distanceMeters = distanceMeters
        self.distanceCoverage = distanceCoverage
        self.transportGapOccurred = transportGapOccurred
        self.startSOC = startSOC
        self.endSOC = endSOC
    }
#endif

    /// Generic/imported windows are representable for offline analysis, but they cannot carry
    /// authoritative SoC and therefore cannot train `AdaptiveBatteryRangeModel`.
    public static func nonAuthoritative(
        distanceMeters: Double,
        distanceCoverage: BatteryRangeDistanceCoverage,
        transportGapOccurred: Bool,
        startSOC: BatterySOCReading,
        endSOC: BatterySOCReading
    ) throws -> Self {
        guard startSOC.isAuthoritativeMeasurement == false,
              endSOC.isAuthoritativeMeasurement == false else {
            throw BatteryRangeValidationError.invalidEvidenceRole
        }
        return try Self(
            distanceMeters: distanceMeters,
            distanceCoverage: distanceCoverage,
            transportGapOccurred: transportGapOccurred,
            startSOC: startSOC,
            endSOC: endSOC
        )
    }

    public var consumedPercentagePoints: Double {
        startSOC.percentage - endSOC.percentage
    }
}

public struct BatteryRangeEfficiencySample: Equatable, Codable, Sendable {
    public let distanceMeters: Double
    public let consumedPercentagePoints: Double
    public let metersPerPercentagePoint: Double

    init(distanceMeters: Double, consumedPercentagePoints: Double) {
        self.distanceMeters = distanceMeters
        self.consumedPercentagePoints = consumedPercentagePoints
        self.metersPerPercentagePoint = distanceMeters / consumedPercentagePoints
    }

    private enum CodingKeys: String, CodingKey {
        case distanceMeters
        case consumedPercentagePoints
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let distanceMeters = try container.decode(Double.self, forKey: .distanceMeters)
        let consumedPercentagePoints = try container.decode(Double.self, forKey: .consumedPercentagePoints)
        let efficiency = distanceMeters / consumedPercentagePoints

        guard distanceMeters.isFinite,
              distanceMeters > 0,
              consumedPercentagePoints.isFinite,
              consumedPercentagePoints > 0,
              consumedPercentagePoints <= 100,
              efficiency.isFinite,
              efficiency > 0,
              (efficiency * 100).isFinite else {
            throw DecodingError.dataCorruptedError(
                forKey: .distanceMeters,
                in: container,
                debugDescription: "Persisted battery-range efficiency sample is invalid."
            )
        }

        self.init(
            distanceMeters: distanceMeters,
            consumedPercentagePoints: consumedPercentagePoints
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(distanceMeters, forKey: .distanceMeters)
        try container.encode(consumedPercentagePoints, forKey: .consumedPercentagePoints)
    }
}

public enum AdaptiveRangeConfidence: String, Codable, Sendable {
    case learning
    case low
    case normal
    case high
}

public enum AdaptiveRangeEstimateBasis: String, Codable, Sendable {
    /// A deliberately conservative seed supplied by a higher layer for a new
    /// scooter. It is not learned history and must remain classified as such.
    case provisionalSeed
    case learned
}

public enum BatteryRangeLearningRejectionReason: String, Equatable, Sendable {
    case incompleteDistanceEvidence
    case transportGap
    case nonAuthoritativeSOC
    case nonConsumptionWindow
    case insufficientSOCConsumption
    case insufficientDistance
    case efficiencyOutlier
    case numericalOverflow
}

public enum BatteryRangeLearningDisposition: Equatable, Sendable {
    case accepted
    case rejected(BatteryRangeLearningRejectionReason)
}

public struct BatteryRangeLearningResult: Equatable, Sendable {
    public let disposition: BatteryRangeLearningDisposition
    public let sample: BatteryRangeEfficiencySample?
    public let confidence: AdaptiveRangeConfidence
}

/// Explicit tuning knobs for the learned percentage-based estimator.
///
/// Values are supplied by the application/vehicle profile rather than hidden
/// inside the model so ES80 field evidence can later change thresholds without
/// rewriting the algorithm.
public struct AdaptiveBatteryRangePolicy: Equatable, Codable, Sendable {
    public let minimumConsumedPercentagePoints: Double
    public let minimumDistanceMeters: Double
    public let recentWindowCapacity: Int
    public let recentWeight: Double
    public let outlierLowerEfficiencyRatio: Double
    public let outlierUpperEfficiencyRatio: Double
    public let estimateDeadbandFraction: Double
    public let estimateSmoothingFactor: Double
    /// Optional low-confidence cold-start seed. Supplying this never makes the
    /// estimate learned; the output remains `.provisionalSeed` until real
    /// authoritative windows are accepted.
    public let provisionalEfficiencyMetersPerPercentagePoint: Double?
    public let lowSOCCautionThresholdPercent: Double?
    public let lowSOCEfficiencyMultiplier: Double?
    public let lowConfidenceConsumedPercentagePoints: Double
    public let normalConfidenceConsumedPercentagePoints: Double
    public let highConfidenceConsumedPercentagePoints: Double

    public init(
        minimumConsumedPercentagePoints: Double,
        minimumDistanceMeters: Double,
        recentWindowCapacity: Int,
        recentWeight: Double,
        outlierLowerEfficiencyRatio: Double,
        outlierUpperEfficiencyRatio: Double,
        estimateDeadbandFraction: Double,
        estimateSmoothingFactor: Double,
        provisionalEfficiencyMetersPerPercentagePoint: Double? = nil,
        lowSOCCautionThresholdPercent: Double? = nil,
        lowSOCEfficiencyMultiplier: Double? = nil,
        lowConfidenceConsumedPercentagePoints: Double,
        normalConfidenceConsumedPercentagePoints: Double,
        highConfidenceConsumedPercentagePoints: Double
    ) throws {
        let finiteScalars = [
            minimumConsumedPercentagePoints,
            minimumDistanceMeters,
            recentWeight,
            outlierLowerEfficiencyRatio,
            outlierUpperEfficiencyRatio,
            estimateDeadbandFraction,
            estimateSmoothingFactor,
            lowConfidenceConsumedPercentagePoints,
            normalConfidenceConsumedPercentagePoints,
            highConfidenceConsumedPercentagePoints
        ]
        guard finiteScalars.allSatisfy({ $0.isFinite }),
              minimumConsumedPercentagePoints > 0,
              minimumConsumedPercentagePoints <= 100,
              minimumDistanceMeters > 0,
              recentWindowCapacity > 0,
              (0...1).contains(recentWeight),
              outlierLowerEfficiencyRatio > 0,
              outlierLowerEfficiencyRatio <= 1,
              outlierUpperEfficiencyRatio >= 1,
              outlierUpperEfficiencyRatio >= outlierLowerEfficiencyRatio,
              estimateDeadbandFraction >= 0,
              estimateDeadbandFraction <= 1,
              estimateSmoothingFactor > 0,
              estimateSmoothingFactor <= 1,
              lowConfidenceConsumedPercentagePoints > 0,
              normalConfidenceConsumedPercentagePoints > lowConfidenceConsumedPercentagePoints,
              highConfidenceConsumedPercentagePoints > normalConfidenceConsumedPercentagePoints else {
            throw BatteryRangeValidationError.invalidPolicy
        }

        if let provisionalEfficiencyMetersPerPercentagePoint {
            guard provisionalEfficiencyMetersPerPercentagePoint.isFinite,
                  provisionalEfficiencyMetersPerPercentagePoint > 0,
                  (provisionalEfficiencyMetersPerPercentagePoint * 100).isFinite else {
                throw BatteryRangeValidationError.invalidPolicy
            }
        }

        switch (lowSOCCautionThresholdPercent, lowSOCEfficiencyMultiplier) {
        case (nil, nil):
            break
        case let (threshold?, multiplier?):
            guard threshold.isFinite,
                  threshold > 0,
                  threshold <= 100,
                  multiplier.isFinite,
                  multiplier > 0,
                  multiplier <= 1 else {
                throw BatteryRangeValidationError.invalidPolicy
            }
        default:
            throw BatteryRangeValidationError.invalidPolicy
        }

        self.minimumConsumedPercentagePoints = minimumConsumedPercentagePoints
        self.minimumDistanceMeters = minimumDistanceMeters
        self.recentWindowCapacity = recentWindowCapacity
        self.recentWeight = recentWeight
        self.outlierLowerEfficiencyRatio = outlierLowerEfficiencyRatio
        self.outlierUpperEfficiencyRatio = outlierUpperEfficiencyRatio
        self.estimateDeadbandFraction = estimateDeadbandFraction
        self.estimateSmoothingFactor = estimateSmoothingFactor
        self.provisionalEfficiencyMetersPerPercentagePoint = provisionalEfficiencyMetersPerPercentagePoint
        self.lowSOCCautionThresholdPercent = lowSOCCautionThresholdPercent
        self.lowSOCEfficiencyMultiplier = lowSOCEfficiencyMultiplier
        self.lowConfidenceConsumedPercentagePoints = lowConfidenceConsumedPercentagePoints
        self.normalConfidenceConsumedPercentagePoints = normalConfidenceConsumedPercentagePoints
        self.highConfidenceConsumedPercentagePoints = highConfidenceConsumedPercentagePoints
    }
}

/// Derived range output. Direct-source app code cannot synthesize a memberwise instance that
/// claims authoritative SoC provenance; package tests retain controlled construction.
public struct AdaptiveBatteryRangeEstimate: Equatable, Codable, Sendable {
    public let rawRemainingMeters: Double
    public let presentedRemainingMeters: Double
    public let metersPerPercentagePoint: Double
    public let basis: AdaptiveRangeEstimateBasis
    public let confidence: AdaptiveRangeConfidence
    public let socProvenance: BatterySOCProvenance
    public let lowSOCConservatismApplied: Bool

#if SWIFT_PACKAGE
    package init(
        rawRemainingMeters: Double,
        presentedRemainingMeters: Double,
        metersPerPercentagePoint: Double,
        basis: AdaptiveRangeEstimateBasis,
        confidence: AdaptiveRangeConfidence,
        socProvenance: BatterySOCProvenance,
        lowSOCConservatismApplied: Bool
    ) {
        self.rawRemainingMeters = rawRemainingMeters
        self.presentedRemainingMeters = presentedRemainingMeters
        self.metersPerPercentagePoint = metersPerPercentagePoint
        self.basis = basis
        self.confidence = confidence
        self.socProvenance = socProvenance
        self.lowSOCConservatismApplied = lowSOCConservatismApplied
    }
#else
    fileprivate init(
        rawRemainingMeters: Double,
        presentedRemainingMeters: Double,
        metersPerPercentagePoint: Double,
        basis: AdaptiveRangeEstimateBasis,
        confidence: AdaptiveRangeConfidence,
        socProvenance: BatterySOCProvenance,
        lowSOCConservatismApplied: Bool
    ) {
        self.rawRemainingMeters = rawRemainingMeters
        self.presentedRemainingMeters = presentedRemainingMeters
        self.metersPerPercentagePoint = metersPerPercentagePoint
        self.basis = basis
        self.confidence = confidence
        self.socProvenance = socProvenance
        self.lowSOCConservatismApplied = lowSOCConservatismApplied
    }
#endif

    /// Generic/imported construction is explicitly non-authoritative and structurally checked.
    public static func nonAuthoritative(
        rawRemainingMeters: Double,
        presentedRemainingMeters: Double,
        metersPerPercentagePoint: Double,
        basis: AdaptiveRangeEstimateBasis,
        confidence: AdaptiveRangeConfidence,
        socProvenance: BatterySOCProvenance,
        lowSOCConservatismApplied: Bool
    ) throws -> Self {
        guard socProvenance != .authoritativeMeasurement else {
            throw BatteryRangeValidationError.invalidEvidenceRole
        }
        let fullChargeRange = metersPerPercentagePoint * 100
        let tolerance = max(1, abs(fullChargeRange)) * 1e-12
        guard rawRemainingMeters.isFinite,
              rawRemainingMeters >= 0,
              presentedRemainingMeters.isFinite,
              presentedRemainingMeters >= 0,
              metersPerPercentagePoint.isFinite,
              metersPerPercentagePoint > 0,
              fullChargeRange.isFinite,
              rawRemainingMeters <= fullChargeRange + tolerance,
              basis != .provisionalSeed || confidence == .learning else {
            throw BatteryRangeValidationError.invalidEstimate
        }
        return Self(
            rawRemainingMeters: rawRemainingMeters,
            presentedRemainingMeters: presentedRemainingMeters,
            metersPerPercentagePoint: metersPerPercentagePoint,
            basis: basis,
            confidence: confidence,
            socProvenance: socProvenance,
            lowSOCConservatismApplied: lowSOCConservatismApplied
        )
    }
}

/// A live derived range result bound to the exact accepted SoC receipt and currentness owner used
/// to compute it.
///
/// The initializer is file-scoped so direct-source app code cannot attach arbitrary receipt or
/// owner metadata to a generic estimate. Callers receive this only from
/// `estimateRemainingRange(atAcceptedSOC:acceptedBy:...)`, which rechecks the anchor's opaque
/// owner lease at calculation time. The wrapper remains non-Codable because receipt identity and
/// owner currentness are process-local.
public struct AdaptiveBatteryRangeLiveEstimate: Equatable, Sendable {
    public let estimate: AdaptiveBatteryRangeEstimate
    public let sourceReceiptIdentity: BatteryEvidenceReceiptIdentity
    public let sourceSOCUptimeNanoseconds: UInt64
    let currentnessLease: BatteryEvidenceCurrentnessLease

    fileprivate init(
        estimate: AdaptiveBatteryRangeEstimate,
        sourceReceiptIdentity: BatteryEvidenceReceiptIdentity,
        sourceSOCUptimeNanoseconds: UInt64,
        currentnessLease: BatteryEvidenceCurrentnessLease
    ) {
        self.estimate = estimate
        self.sourceReceiptIdentity = sourceReceiptIdentity
        self.sourceSOCUptimeNanoseconds = sourceSOCUptimeNanoseconds
        self.currentnessLease = currentnessLease
    }

    /// A validator can confirm this estimate only when it belongs to the same live owner
    /// generation that minted the source SoC anchor. Matching receipt metadata under a fresh,
    /// unrelated owner is insufficient.
    public func isCurrent(in validator: BatteryEvidenceStreamValidator) -> Bool {
        validator.recognizesCurrentnessLease(
            currentnessLease,
            receiptIdentity: sourceReceiptIdentity,
            uptimeNanoseconds: sourceSOCUptimeNanoseconds
        )
    }

    /// Owner-bound currentness without exposing a validator snapshot to presentation code.
    public var isCurrent: Bool {
        currentnessLease.isCurrent(
            receiptIdentity: sourceReceiptIdentity,
            uptimeNanoseconds: sourceSOCUptimeNanoseconds
        )
    }
}

/// Persistable learning state for one physical scooter.
///
/// This model intentionally learns only distance per authoritative battery
/// percentage point. It never invents current, watts, watt-hours, or Wh/mi.
public struct AdaptiveBatteryRangeModel: Equatable, Codable, Sendable {
    public private(set) var historicalEfficiencyMetersPerPercentagePoint: Double?
    public private(set) var historicalConsumedPercentagePoints: Double
    public private(set) var recentSamples: [BatteryRangeEfficiencySample]
    public private(set) var acceptedWindowCount: Int

    public init() {
        historicalEfficiencyMetersPerPercentagePoint = nil
        historicalConsumedPercentagePoints = 0
        recentSamples = []
        acceptedWindowCount = 0
    }

    public var hasLearnedEfficiency: Bool {
        historicalEfficiencyMetersPerPercentagePoint != nil
    }

    public func confidence(using policy: AdaptiveBatteryRangePolicy) -> AdaptiveRangeConfidence {
        let evidence = historicalConsumedPercentagePoints
        if evidence >= policy.highConfidenceConsumedPercentagePoints { return .high }
        if evidence >= policy.normalConfidenceConsumedPercentagePoints { return .normal }
        if evidence >= policy.lowConfidenceConsumedPercentagePoints { return .low }
        return .learning
    }

    public func blendedEfficiencyMetersPerPercentagePoint(
        using policy: AdaptiveBatteryRangePolicy
    ) -> Double? {
        let recentEfficiency = weightedRecentEfficiency(maximumSampleCount: policy.recentWindowCapacity)
        let result: Double?
        switch (historicalEfficiencyMetersPerPercentagePoint, recentEfficiency) {
        case let (historical?, recent?):
            result = historical * (1 - policy.recentWeight) + recent * policy.recentWeight
        case let (historical?, nil): result = historical
        case let (nil, recent?): result = recent
        case (nil, nil): result = nil
        }
        guard let result, result.isFinite, result > 0 else { return nil }
        return result
    }

    public func typicalFullChargeRangeMeters(
        using policy: AdaptiveBatteryRangePolicy
    ) -> Double? {
        guard let efficiency = blendedEfficiencyMetersPerPercentagePoint(using: policy) else { return nil }
        let range = efficiency * 100
        guard range.isFinite else { return nil }
        return range
    }

    @discardableResult
    public mutating func ingest(
        _ window: BatteryRangeLearningWindow,
        policy: AdaptiveBatteryRangePolicy
    ) -> BatteryRangeLearningResult {
        guard window.distanceCoverage == .complete else { return rejected(.incompleteDistanceEvidence, policy: policy) }
        guard window.transportGapOccurred == false else { return rejected(.transportGap, policy: policy) }
        guard window.startSOC.isAuthoritativeMeasurement,
              window.endSOC.isAuthoritativeMeasurement else { return rejected(.nonAuthoritativeSOC, policy: policy) }

        let consumed = window.consumedPercentagePoints
        guard consumed > 0 else { return rejected(.nonConsumptionWindow, policy: policy) }
        guard consumed >= policy.minimumConsumedPercentagePoints else { return rejected(.insufficientSOCConsumption, policy: policy) }
        guard window.distanceMeters >= policy.minimumDistanceMeters else { return rejected(.insufficientDistance, policy: policy) }

        let sample = BatteryRangeEfficiencySample(distanceMeters: window.distanceMeters, consumedPercentagePoints: consumed)
        guard sample.metersPerPercentagePoint.isFinite,
              sample.metersPerPercentagePoint > 0,
              (sample.metersPerPercentagePoint * 100).isFinite else { return rejected(.numericalOverflow, policy: policy) }

        if let baseline = blendedEfficiencyMetersPerPercentagePoint(using: policy) {
            let ratio = sample.metersPerPercentagePoint / baseline
            guard ratio.isFinite else { return rejected(.numericalOverflow, policy: policy) }
            if ratio < policy.outlierLowerEfficiencyRatio || ratio > policy.outlierUpperEfficiencyRatio {
                return rejected(.efficiencyOutlier, policy: policy)
            }
        }

        guard acceptedWindowCount < Int.max else { return rejected(.numericalOverflow, policy: policy) }

        let oldConsumed = historicalConsumedPercentagePoints
        if let historical = historicalEfficiencyMetersPerPercentagePoint {
            let totalConsumed = oldConsumed + consumed
            guard totalConsumed.isFinite, totalConsumed > 0 else { return rejected(.numericalOverflow, policy: policy) }
            let weight = consumed / totalConsumed
            let candidate = historical + (sample.metersPerPercentagePoint - historical) * weight
            guard candidate.isFinite, candidate > 0, (candidate * 100).isFinite else {
                return rejected(.numericalOverflow, policy: policy)
            }
            historicalConsumedPercentagePoints = totalConsumed
            historicalEfficiencyMetersPerPercentagePoint = candidate
        } else {
            historicalConsumedPercentagePoints = consumed
            historicalEfficiencyMetersPerPercentagePoint = sample.metersPerPercentagePoint
        }

        recentSamples.append(sample)
        if recentSamples.count > policy.recentWindowCapacity {
            recentSamples.removeFirst(recentSamples.count - policy.recentWindowCapacity)
        }
        acceptedWindowCount += 1

        return BatteryRangeLearningResult(disposition: .accepted, sample: sample, confidence: confidence(using: policy))
    }

    /// Generic/public estimation accepts estimated SoC only. This keeps simulator/offline math
    /// available without allowing direct-source app code to throw away an accepted receipt and
    /// still receive an estimate labeled as authoritative.
    public func estimateRemainingRange(
        atEstimatedSOC soc: BatterySOCReading,
        previousPresentedRemainingMeters: Double? = nil,
        policy: AdaptiveBatteryRangePolicy
    ) -> AdaptiveBatteryRangeEstimate? {
        guard soc.isAuthoritativeMeasurement == false else { return nil }
        return estimateRemainingRangeImpl(
            at: soc,
            previousPresentedRemainingMeters: previousPresentedRemainingMeters,
            policy: policy
        )
    }

#if SWIFT_PACKAGE
    /// Package-only raw estimator retained for focused pure-model tests and trusted package
    /// integration. Direct-source app code does not receive this overload.
    package func estimateRemainingRange(
        at soc: BatterySOCReading,
        previousPresentedRemainingMeters: Double? = nil,
        policy: AdaptiveBatteryRangePolicy
    ) -> AdaptiveBatteryRangeEstimate? {
        estimateRemainingRangeImpl(
            at: soc,
            previousPresentedRemainingMeters: previousPresentedRemainingMeters,
            policy: policy
        )
    }
#endif

    /// Production live estimation requires both a sealed accepted SoC anchor and the validator
    /// that still owns that exact anchor lease. A retained anchor cannot be recomputed into a
    /// fresh-looking live estimate after a gap, newer battery callback, or replay through a fresh
    /// unrelated owner that merely sees matching receipt metadata.
    public func estimateRemainingRange(
        atAcceptedSOC soc: AcceptedBatterySOCAnchor,
        acceptedBy validator: BatteryEvidenceStreamValidator,
        previousPresentedRemainingMeters: Double? = nil,
        policy: AdaptiveBatteryRangePolicy
    ) -> AdaptiveBatteryRangeLiveEstimate? {
        guard soc.isCurrent(in: validator),
              let normalizedSOC = try? BatterySOCReading(
                percentage: soc.percentage,
                provenance: .authoritativeMeasurement,
                receivedAtUptimeNanoseconds: soc.receivedAtUptimeNanoseconds
              ),
              let estimate = estimateRemainingRangeImpl(
                at: normalizedSOC,
                previousPresentedRemainingMeters: previousPresentedRemainingMeters,
                policy: policy
              ) else { return nil }

        return AdaptiveBatteryRangeLiveEstimate(
            estimate: estimate,
            sourceReceiptIdentity: soc.sourceReceiptIdentity,
            sourceSOCUptimeNanoseconds: soc.receivedAtUptimeNanoseconds,
            currentnessLease: soc.currentnessLease
        )
    }

    private func estimateRemainingRangeImpl(
        at soc: BatterySOCReading,
        previousPresentedRemainingMeters: Double?,
        policy: AdaptiveBatteryRangePolicy
    ) -> AdaptiveBatteryRangeEstimate? {
        let selected: (efficiency: Double, basis: AdaptiveRangeEstimateBasis)
        if let learned = blendedEfficiencyMetersPerPercentagePoint(using: policy) {
            selected = (learned, .learned)
        } else if let provisional = policy.provisionalEfficiencyMetersPerPercentagePoint {
            selected = (provisional, .provisionalSeed)
        } else { return nil }

        guard selected.efficiency.isFinite, selected.efficiency > 0 else { return nil }
        var rawRemainingMeters = selected.efficiency * soc.percentage
        guard rawRemainingMeters.isFinite else { return nil }
        var lowSOCConservatismApplied = false

        if let threshold = policy.lowSOCCautionThresholdPercent,
           let multiplier = policy.lowSOCEfficiencyMultiplier,
           soc.percentage < threshold {
            let fractionOfThreshold = soc.percentage / threshold
            let gradualMultiplier = multiplier + (1 - multiplier) * fractionOfThreshold
            rawRemainingMeters *= gradualMultiplier
            guard rawRemainingMeters.isFinite else { return nil }
            lowSOCConservatismApplied = true
        }

        let presentedRemainingMeters = smoothEstimate(
            rawRemainingMeters,
            previousPresentedRemainingMeters: previousPresentedRemainingMeters,
            policy: policy
        )
        guard presentedRemainingMeters.isFinite, presentedRemainingMeters >= 0 else { return nil }

        return AdaptiveBatteryRangeEstimate(
            rawRemainingMeters: rawRemainingMeters,
            presentedRemainingMeters: presentedRemainingMeters,
            metersPerPercentagePoint: selected.efficiency,
            basis: selected.basis,
            confidence: confidence(using: policy),
            socProvenance: soc.provenance,
            lowSOCConservatismApplied: lowSOCConservatismApplied
        )
    }

    private func weightedRecentEfficiency(maximumSampleCount: Int) -> Double? {
        guard maximumSampleCount > 0 else { return nil }
        var totalConsumed = 0.0
        var weightedMean = 0.0
        for sample in recentSamples.suffix(maximumSampleCount) {
            let newTotal = totalConsumed + sample.consumedPercentagePoints
            guard newTotal.isFinite, newTotal > 0 else { return nil }
            let weight = sample.consumedPercentagePoints / newTotal
            let candidate = weightedMean + (sample.metersPerPercentagePoint - weightedMean) * weight
            guard candidate.isFinite, candidate > 0 else { return nil }
            weightedMean = candidate
            totalConsumed = newTotal
        }
        guard totalConsumed > 0 else { return nil }
        return weightedMean
    }

    private func rejected(
        _ reason: BatteryRangeLearningRejectionReason,
        policy: AdaptiveBatteryRangePolicy
    ) -> BatteryRangeLearningResult {
        BatteryRangeLearningResult(disposition: .rejected(reason), sample: nil, confidence: confidence(using: policy))
    }

    private func smoothEstimate(
        _ rawRemainingMeters: Double,
        previousPresentedRemainingMeters: Double?,
        policy: AdaptiveBatteryRangePolicy
    ) -> Double {
        guard let previous = previousPresentedRemainingMeters,
              previous.isFinite,
              previous >= 0 else { return rawRemainingMeters }
        let deadbandMeters = max(previous, rawRemainingMeters) * policy.estimateDeadbandFraction
        let delta = rawRemainingMeters - previous
        guard abs(delta) > deadbandMeters else { return previous }
        return previous + delta * policy.estimateSmoothingFactor
    }

    private enum CodingKeys: String, CodingKey {
        case historicalEfficiencyMetersPerPercentagePoint
        case historicalConsumedPercentagePoints
        case recentSamples
        case acceptedWindowCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let historicalEfficiency = try container.decodeIfPresent(Double.self, forKey: .historicalEfficiencyMetersPerPercentagePoint)
        let historicalConsumed = try container.decode(Double.self, forKey: .historicalConsumedPercentagePoints)
        let recentSamples = try container.decode([BatteryRangeEfficiencySample].self, forKey: .recentSamples)
        let acceptedWindowCount = try container.decode(Int.self, forKey: .acceptedWindowCount)
        let recentConsumed = recentSamples.reduce(into: 0.0) { total, sample in total += sample.consumedPercentagePoints }
        let evidenceTolerance = max(1, abs(historicalConsumed)) * 1e-12
        let maximumPlausibleConsumed = Double(acceptedWindowCount) * 100
        let maximumPlausibleTolerance = max(1, abs(maximumPlausibleConsumed)) * 1e-12

        guard historicalConsumed.isFinite,
              historicalConsumed >= 0,
              recentConsumed.isFinite,
              acceptedWindowCount >= 0,
              recentConsumed <= historicalConsumed + evidenceTolerance,
              maximumPlausibleConsumed.isFinite,
              historicalConsumed <= maximumPlausibleConsumed + maximumPlausibleTolerance,
              recentSamples.count <= acceptedWindowCount else { throw Self.corruptedStateError(container) }

        if let historicalEfficiency {
            guard historicalEfficiency.isFinite,
                  historicalEfficiency > 0,
                  (historicalEfficiency * 100).isFinite,
                  historicalConsumed > 0,
                  acceptedWindowCount > 0,
                  recentSamples.isEmpty == false else { throw Self.corruptedStateError(container) }
        } else {
            guard historicalConsumed == 0,
                  acceptedWindowCount == 0,
                  recentSamples.isEmpty else { throw Self.corruptedStateError(container) }
        }

        self.historicalEfficiencyMetersPerPercentagePoint = historicalEfficiency
        self.historicalConsumedPercentagePoints = historicalConsumed
        self.recentSamples = recentSamples
        self.acceptedWindowCount = acceptedWindowCount
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(historicalEfficiencyMetersPerPercentagePoint, forKey: .historicalEfficiencyMetersPerPercentagePoint)
        try container.encode(historicalConsumedPercentagePoints, forKey: .historicalConsumedPercentagePoints)
        try container.encode(recentSamples, forKey: .recentSamples)
        try container.encode(acceptedWindowCount, forKey: .acceptedWindowCount)
    }

    private static func corruptedStateError(
        _ container: KeyedDecodingContainer<CodingKeys>
    ) -> DecodingError {
        DecodingError.dataCorruptedError(
            forKey: .historicalConsumedPercentagePoints,
            in: container,
            debugDescription: "Persisted adaptive battery-range state is internally inconsistent."
        )
    }
}
