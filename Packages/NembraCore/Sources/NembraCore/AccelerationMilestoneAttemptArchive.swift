import Foundation

public enum AccelerationMilestoneAttemptArchiveError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case invalidArchivedAt
    case requestedTargetsRequired
    case requestedTargetsMustBeStrictlyIncreasing(previous: Double, current: Double)
    case invalidPolicy
    case inconsistentSuitePolicy(targetMetersPerSecond: Double)
    case noQualifiedMilestones
    case qualifiedTargetNotRequested(Double)
    case qualifiedTargetsOutOfOrder(previous: Double, current: Double)
    case invalidQualifiedMilestone(targetMetersPerSecond: Double)
    case sourceMismatch(expected: SpeedTelemetrySource, actual: SpeedTelemetrySource)
    case timingEvidenceCountMismatch(targetMetersPerSecond: Double, result: Int, quality: Int)
    case timingDurationMismatch(targetMetersPerSecond: Double, resultSeconds: Double, qualitySeconds: Double)
}

/// Durable name for the only timing basis currently eligible for acceleration
/// result archival.
///
/// Persisting this basis is intentional: a later product must not reinterpret an
/// old receive-clock observation interval as exact physical launch/crossing time.
public enum AccelerationMilestoneArchiveTimingBasis: String, Codable, Equatable, Sendable {
    case receiveObservationUptime
}

/// Exact evidence thresholds that qualified the archived attempt.
///
/// These are historical policy facts, not newly verified ES80 characteristics.
/// Restoring this value never promotes it into a current telemetry policy.
public struct AccelerationMilestoneEvidencePolicyArchive: Codable, Equatable, Sendable {
    public let source: SpeedTelemetrySource
    public let stationaryMaximumMetersPerSecond: Double
    public let maximumSpeedAccuracyMetersPerSecond: Double?
    public let maximumSampleIntervalNanoseconds: UInt64
    public let minimumAcceptedSampleCount: Int
    public let maximumRejectedSampleFraction: Double
    public let maximumMeanIntervalMilliseconds: Double
    public let maximumObservedIntervalMilliseconds: Double
    public let maximumJitterStandardDeviationMilliseconds: Double
    public let minimumDeliveryLatencySampleFraction: Double?
    public let maximumMeanDeliveryLatencyMilliseconds: Double?
    public let maximumEmpiricalSpeedStepKilometersPerHour: Double

    fileprivate init(policy: AccelerationEvidenceSessionPolicy) throws {
        guard let maximumSampleIntervalNanoseconds = policy.run.maximumSampleIntervalNanoseconds,
              let maximumRejectedSampleFraction = policy.telemetry.maximumRejectedSampleFraction,
              let maximumMeanIntervalMilliseconds = policy.telemetry.maximumMeanIntervalMilliseconds,
              let maximumObservedIntervalMilliseconds = policy.telemetry.maximumObservedIntervalMilliseconds,
              let maximumJitterStandardDeviationMilliseconds = policy.telemetry.maximumJitterStandardDeviationMilliseconds,
              let maximumEmpiricalSpeedStepKilometersPerHour = policy.telemetry.maximumEmpiricalSpeedStepKilometersPerHour else {
            throw AccelerationMilestoneAttemptArchiveError.invalidPolicy
        }

        source = policy.source
        stationaryMaximumMetersPerSecond = policy.run.stationaryMaximumMetersPerSecond
        maximumSpeedAccuracyMetersPerSecond = policy.run.maximumSpeedAccuracyMetersPerSecond
        self.maximumSampleIntervalNanoseconds = maximumSampleIntervalNanoseconds
        minimumAcceptedSampleCount = policy.telemetry.minimumAcceptedSampleCount
        self.maximumRejectedSampleFraction = maximumRejectedSampleFraction
        self.maximumMeanIntervalMilliseconds = maximumMeanIntervalMilliseconds
        self.maximumObservedIntervalMilliseconds = maximumObservedIntervalMilliseconds
        self.maximumJitterStandardDeviationMilliseconds = maximumJitterStandardDeviationMilliseconds
        minimumDeliveryLatencySampleFraction = policy.telemetry.minimumDeliveryLatencySampleFraction
        maximumMeanDeliveryLatencyMilliseconds = policy.telemetry.maximumMeanDeliveryLatencyMilliseconds
        self.maximumEmpiricalSpeedStepKilometersPerHour = maximumEmpiricalSpeedStepKilometersPerHour
    }

    fileprivate func isValid(for requestedTargets: [Double]) -> Bool {
        guard source != .motionAssist,
              stationaryMaximumMetersPerSecond.isFinite,
              stationaryMaximumMetersPerSecond >= 0,
              requestedTargets.allSatisfy({ stationaryMaximumMetersPerSecond < $0 }),
              maximumSampleIntervalNanoseconds > 0,
              minimumAcceptedSampleCount >= 3,
              maximumRejectedSampleFraction.isFinite,
              (0...1).contains(maximumRejectedSampleFraction),
              maximumMeanIntervalMilliseconds.isFinite,
              maximumMeanIntervalMilliseconds >= 0,
              maximumObservedIntervalMilliseconds.isFinite,
              maximumObservedIntervalMilliseconds >= 0,
              maximumJitterStandardDeviationMilliseconds.isFinite,
              maximumJitterStandardDeviationMilliseconds >= 0,
              maximumEmpiricalSpeedStepKilometersPerHour.isFinite,
              maximumEmpiricalSpeedStepKilometersPerHour >= 0 else {
            return false
        }

        if let maximumSpeedAccuracyMetersPerSecond {
            guard maximumSpeedAccuracyMetersPerSecond.isFinite,
                  maximumSpeedAccuracyMetersPerSecond >= 0 else {
                return false
            }
        }
        if let minimumDeliveryLatencySampleFraction {
            guard minimumDeliveryLatencySampleFraction.isFinite,
                  (0...1).contains(minimumDeliveryLatencySampleFraction) else {
                return false
            }
        }
        if let maximumMeanDeliveryLatencyMilliseconds {
            guard maximumMeanDeliveryLatencyMilliseconds.isFinite,
                  maximumMeanDeliveryLatencyMilliseconds >= 0 else {
                return false
            }
        }

        if source == .gps {
            guard maximumSpeedAccuracyMetersPerSecond != nil,
                  let minimumDeliveryLatencySampleFraction,
                  minimumDeliveryLatencySampleFraction > 0,
                  maximumMeanDeliveryLatencyMilliseconds != nil else {
                return false
            }
        }

        return true
    }

    fileprivate func matches(_ policy: AccelerationEvidenceSessionPolicy) -> Bool {
        guard let candidate = try? AccelerationMilestoneEvidencePolicyArchive(policy: policy) else {
            return false
        }
        return candidate == self
    }
}

/// Archived quality diagnostics for the exact retained timing trace used by one
/// qualified milestone. No raw packet timestamps or display frames are stored.
public struct AccelerationMilestoneQualityArchive: Codable, Equatable, Sendable {
    public let acceptedSampleCount: Int
    public let rejectedSampleCount: Int
    public let observationSegmentCount: Int
    public let knownObservationInterruptionCount: Int
    public let intervalCount: Int
    public let observedDurationSeconds: Double
    public let effectiveSampleRateHertz: Double?
    public let meanIntervalMilliseconds: Double?
    public let minimumIntervalMilliseconds: Double?
    public let maximumIntervalMilliseconds: Double?
    public let intervalJitterStandardDeviationMilliseconds: Double?
    public let duplicateSpeedValueCount: Int
    public let empiricalMinimumNonzeroSpeedStepKilometersPerHour: Double?
    public let deliveryLatencySampleCount: Int
    public let meanDeliveryLatencyMilliseconds: Double?
    public let minimumDeliveryLatencyMilliseconds: Double?
    public let maximumDeliveryLatencyMilliseconds: Double?
    public let deliveryLatencyStandardDeviationMilliseconds: Double?

    fileprivate init(summary: TelemetryBenchmarkSummary) {
        acceptedSampleCount = summary.acceptedSampleCount
        rejectedSampleCount = summary.rejectedSampleCount
        observationSegmentCount = summary.observationSegmentCount
        knownObservationInterruptionCount = summary.knownObservationInterruptionCount
        intervalCount = summary.intervalCount
        observedDurationSeconds = summary.observedDurationSeconds
        effectiveSampleRateHertz = summary.effectiveSampleRateHertz
        meanIntervalMilliseconds = summary.meanIntervalMilliseconds
        minimumIntervalMilliseconds = summary.minimumIntervalMilliseconds
        maximumIntervalMilliseconds = summary.maximumIntervalMilliseconds
        intervalJitterStandardDeviationMilliseconds = summary.intervalJitterStandardDeviationMilliseconds
        duplicateSpeedValueCount = summary.duplicateSpeedValueCount
        empiricalMinimumNonzeroSpeedStepKilometersPerHour = summary.empiricalMinimumNonzeroSpeedStepKilometersPerHour
        deliveryLatencySampleCount = summary.deliveryLatencySampleCount
        meanDeliveryLatencyMilliseconds = summary.meanDeliveryLatencyMilliseconds
        minimumDeliveryLatencyMilliseconds = summary.minimumDeliveryLatencyMilliseconds
        maximumDeliveryLatencyMilliseconds = summary.maximumDeliveryLatencyMilliseconds
        deliveryLatencyStandardDeviationMilliseconds = summary.deliveryLatencyStandardDeviationMilliseconds
    }

    fileprivate var isValidQualifiedTrace: Bool {
        guard acceptedSampleCount >= 3,
              rejectedSampleCount == 0,
              observationSegmentCount == 1,
              knownObservationInterruptionCount == 0,
              intervalCount == acceptedSampleCount - observationSegmentCount,
              observedDurationSeconds.isFinite,
              observedDurationSeconds > 0,
              duplicateSpeedValueCount >= 0,
              duplicateSpeedValueCount <= intervalCount,
              deliveryLatencySampleCount >= 0,
              deliveryLatencySampleCount <= acceptedSampleCount else {
            return false
        }

        guard optionalNonnegativeFinite(effectiveSampleRateHertz),
              optionalNonnegativeFinite(meanIntervalMilliseconds),
              optionalNonnegativeFinite(minimumIntervalMilliseconds),
              optionalNonnegativeFinite(maximumIntervalMilliseconds),
              optionalNonnegativeFinite(intervalJitterStandardDeviationMilliseconds),
              optionalNonnegativeFinite(empiricalMinimumNonzeroSpeedStepKilometersPerHour),
              optionalNonnegativeFinite(meanDeliveryLatencyMilliseconds),
              optionalNonnegativeFinite(minimumDeliveryLatencyMilliseconds),
              optionalNonnegativeFinite(maximumDeliveryLatencyMilliseconds),
              optionalNonnegativeFinite(deliveryLatencyStandardDeviationMilliseconds) else {
            return false
        }

        if intervalCount > 0 {
            guard let effectiveSampleRateHertz, effectiveSampleRateHertz > 0,
                  let meanIntervalMilliseconds,
                  let minimumIntervalMilliseconds,
                  let maximumIntervalMilliseconds,
                  let intervalJitterStandardDeviationMilliseconds,
                  minimumIntervalMilliseconds <= meanIntervalMilliseconds,
                  meanIntervalMilliseconds <= maximumIntervalMilliseconds,
                  intervalJitterStandardDeviationMilliseconds >= 0 else {
                return false
            }
        }

        if intervalCount > duplicateSpeedValueCount {
            guard empiricalMinimumNonzeroSpeedStepKilometersPerHour != nil else {
                return false
            }
        } else if empiricalMinimumNonzeroSpeedStepKilometersPerHour != nil {
            return false
        }

        if deliveryLatencySampleCount > 0 {
            guard let meanDeliveryLatencyMilliseconds,
                  let minimumDeliveryLatencyMilliseconds,
                  let maximumDeliveryLatencyMilliseconds,
                  let deliveryLatencyStandardDeviationMilliseconds,
                  minimumDeliveryLatencyMilliseconds <= meanDeliveryLatencyMilliseconds,
                  meanDeliveryLatencyMilliseconds <= maximumDeliveryLatencyMilliseconds,
                  deliveryLatencyStandardDeviationMilliseconds >= 0 else {
                return false
            }
        } else if meanDeliveryLatencyMilliseconds != nil ||
                    minimumDeliveryLatencyMilliseconds != nil ||
                    maximumDeliveryLatencyMilliseconds != nil ||
                    deliveryLatencyStandardDeviationMilliseconds != nil {
            return false
        }

        return true
    }

    private func optionalNonnegativeFinite(_ value: Double?) -> Bool {
        guard let value else { return true }
        return value.isFinite && value >= 0
    }
}

/// One product-reportable milestone captured as historical evidence.
///
/// Window widths are retained for auditability, but absolute process-uptime
/// timestamps are deliberately absent. A decoded record can never be used to
/// continue or recreate the original live timing session.
public struct AccelerationMilestoneQualifiedArchive: Codable, Equatable, Sendable {
    public let targetMetersPerSecond: Double
    public let source: SpeedTelemetrySource
    public let timingBasis: AccelerationMilestoneArchiveTimingBasis
    public let stationaryToTargetObservationElapsedSeconds: Double
    public let launchObservationWindowWidthSeconds: Double
    public let targetTransitionObservationWindowWidthSeconds: Double
    public let timingEvidenceSampleCount: Int
    public let quality: AccelerationMilestoneQualityArchive

    fileprivate init(
        result: AccelerationRunResult,
        benchmark: TelemetryBenchmarkSummary
    ) {
        targetMetersPerSecond = result.targetMetersPerSecond
        source = result.source
        switch result.timingBasis {
        case .receiveObservationUptime:
            timingBasis = .receiveObservationUptime
        }
        stationaryToTargetObservationElapsedSeconds = result.stationaryToTargetObservationElapsedSeconds
        launchObservationWindowWidthSeconds = result.launchObservationWindow.widthSeconds
        targetTransitionObservationWindowWidthSeconds = result.targetTransitionObservationWindow.widthSeconds
        timingEvidenceSampleCount = result.timingEvidenceSampleCount
        quality = AccelerationMilestoneQualityArchive(summary: benchmark)
    }

    fileprivate var hasValidShape: Bool {
        targetMetersPerSecond.isFinite &&
        targetMetersPerSecond > 0 &&
        source != .motionAssist &&
        stationaryToTargetObservationElapsedSeconds.isFinite &&
        stationaryToTargetObservationElapsedSeconds > 0 &&
        launchObservationWindowWidthSeconds.isFinite &&
        launchObservationWindowWidthSeconds > 0 &&
        targetTransitionObservationWindowWidthSeconds.isFinite &&
        targetTransitionObservationWindowWidthSeconds > 0 &&
        launchObservationWindowWidthSeconds <= stationaryToTargetObservationElapsedSeconds &&
        targetTransitionObservationWindowWidthSeconds <= stationaryToTargetObservationElapsedSeconds &&
        timingEvidenceSampleCount >= 3 &&
        quality.isValidQualifiedTrace
    }
}

/// Immutable archival record for one acceleration milestone attempt.
///
/// This record contains only milestones that were product-reportable under the
/// exact policy captured beside them. `requestedTargetsMetersPerSecond` preserves
/// the attempted target set, so a partial archive remains distinguishable from a
/// complete run. Decoding revalidates the entire record rather than trusting
/// synthesized Codable assignment.
public struct AccelerationMilestoneAttemptArchive: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let attemptID: UUID
    public let archivedAt: Date
    public let requestedTargetsMetersPerSecond: [Double]
    public let evidencePolicy: AccelerationMilestoneEvidencePolicyArchive
    public let qualifiedMilestones: [AccelerationMilestoneQualifiedArchive]

    public var isComplete: Bool {
        qualifiedMilestones.count == requestedTargetsMetersPerSecond.count
    }

    public var highestQualifiedTargetMetersPerSecond: Double? {
        qualifiedMilestones.last?.targetMetersPerSecond
    }

    public init(
        snapshot: AccelerationMilestoneEvidenceSuiteSnapshot,
        attemptID: UUID = UUID(),
        archivedAt: Date = Date()
    ) throws {
        let requestedTargets = snapshot.milestones.map(\.targetMetersPerSecond)
        guard let firstMilestone = snapshot.milestones.first else {
            throw AccelerationMilestoneAttemptArchiveError.requestedTargetsRequired
        }
        let policy = try AccelerationMilestoneEvidencePolicyArchive(
            policy: firstMilestone.sessionSnapshot.policy
        )

        for milestone in snapshot.milestones {
            guard milestone.sessionSnapshot.policy.run.targetMetersPerSecond == milestone.targetMetersPerSecond,
                  policy.matches(milestone.sessionSnapshot.policy) else {
                throw AccelerationMilestoneAttemptArchiveError.inconsistentSuitePolicy(
                    targetMetersPerSecond: milestone.targetMetersPerSecond
                )
            }
        }

        var qualified: [AccelerationMilestoneQualifiedArchive] = []
        qualified.reserveCapacity(snapshot.milestones.count)
        for milestone in snapshot.milestones {
            let readiness = milestone.readiness
            guard readiness.isReady,
                  let result = readiness.result,
                  let benchmark = milestone.sessionSnapshot.timingTraceBenchmark else {
                continue
            }
            qualified.append(AccelerationMilestoneQualifiedArchive(
                result: result,
                benchmark: benchmark
            ))
        }

        try self.init(
            schemaVersion: Self.currentSchemaVersion,
            attemptID: attemptID,
            archivedAt: archivedAt,
            requestedTargetsMetersPerSecond: requestedTargets,
            evidencePolicy: policy,
            qualifiedMilestones: qualified
        )
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case attemptID
        case archivedAt
        case requestedTargetsMetersPerSecond
        case evidencePolicy
        case qualifiedMilestones
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            schemaVersion: container.decode(Int.self, forKey: .schemaVersion),
            attemptID: container.decode(UUID.self, forKey: .attemptID),
            archivedAt: container.decode(Date.self, forKey: .archivedAt),
            requestedTargetsMetersPerSecond: container.decode([Double].self, forKey: .requestedTargetsMetersPerSecond),
            evidencePolicy: container.decode(AccelerationMilestoneEvidencePolicyArchive.self, forKey: .evidencePolicy),
            qualifiedMilestones: container.decode([AccelerationMilestoneQualifiedArchive].self, forKey: .qualifiedMilestones)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(attemptID, forKey: .attemptID)
        try container.encode(archivedAt, forKey: .archivedAt)
        try container.encode(requestedTargetsMetersPerSecond, forKey: .requestedTargetsMetersPerSecond)
        try container.encode(evidencePolicy, forKey: .evidencePolicy)
        try container.encode(qualifiedMilestones, forKey: .qualifiedMilestones)
    }

    private init(
        schemaVersion: Int,
        attemptID: UUID,
        archivedAt: Date,
        requestedTargetsMetersPerSecond: [Double],
        evidencePolicy: AccelerationMilestoneEvidencePolicyArchive,
        qualifiedMilestones: [AccelerationMilestoneQualifiedArchive]
    ) throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw AccelerationMilestoneAttemptArchiveError.unsupportedSchemaVersion(schemaVersion)
        }
        guard archivedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw AccelerationMilestoneAttemptArchiveError.invalidArchivedAt
        }
        guard !requestedTargetsMetersPerSecond.isEmpty else {
            throw AccelerationMilestoneAttemptArchiveError.requestedTargetsRequired
        }

        var previousRequested: Double?
        for target in requestedTargetsMetersPerSecond {
            guard target.isFinite, target > 0 else {
                throw AccelerationMilestoneAttemptArchiveError.invalidQualifiedMilestone(
                    targetMetersPerSecond: target
                )
            }
            if let previousRequested, target <= previousRequested {
                throw AccelerationMilestoneAttemptArchiveError
                    .requestedTargetsMustBeStrictlyIncreasing(
                        previous: previousRequested,
                        current: target
                    )
            }
            previousRequested = target
        }

        guard evidencePolicy.isValid(for: requestedTargetsMetersPerSecond) else {
            throw AccelerationMilestoneAttemptArchiveError.invalidPolicy
        }
        guard !qualifiedMilestones.isEmpty else {
            throw AccelerationMilestoneAttemptArchiveError.noQualifiedMilestones
        }

        var previousQualified: Double?
        for milestone in qualifiedMilestones {
            guard milestone.hasValidShape else {
                throw AccelerationMilestoneAttemptArchiveError.invalidQualifiedMilestone(
                    targetMetersPerSecond: milestone.targetMetersPerSecond
                )
            }
            guard milestone.source == evidencePolicy.source else {
                throw AccelerationMilestoneAttemptArchiveError.sourceMismatch(
                    expected: evidencePolicy.source,
                    actual: milestone.source
                )
            }
            guard requestedTargetsMetersPerSecond.contains(milestone.targetMetersPerSecond) else {
                throw AccelerationMilestoneAttemptArchiveError.qualifiedTargetNotRequested(
                    milestone.targetMetersPerSecond
                )
            }
            if let previousQualified, milestone.targetMetersPerSecond <= previousQualified {
                throw AccelerationMilestoneAttemptArchiveError.qualifiedTargetsOutOfOrder(
                    previous: previousQualified,
                    current: milestone.targetMetersPerSecond
                )
            }
            previousQualified = milestone.targetMetersPerSecond

            guard milestone.timingEvidenceSampleCount == milestone.quality.acceptedSampleCount else {
                throw AccelerationMilestoneAttemptArchiveError.timingEvidenceCountMismatch(
                    targetMetersPerSecond: milestone.targetMetersPerSecond,
                    result: milestone.timingEvidenceSampleCount,
                    quality: milestone.quality.acceptedSampleCount
                )
            }
            guard approximatelyEqual(
                milestone.stationaryToTargetObservationElapsedSeconds,
                milestone.quality.observedDurationSeconds
            ) else {
                throw AccelerationMilestoneAttemptArchiveError.timingDurationMismatch(
                    targetMetersPerSecond: milestone.targetMetersPerSecond,
                    resultSeconds: milestone.stationaryToTargetObservationElapsedSeconds,
                    qualitySeconds: milestone.quality.observedDurationSeconds
                )
            }
        }

        self.schemaVersion = schemaVersion
        self.attemptID = attemptID
        self.archivedAt = archivedAt
        self.requestedTargetsMetersPerSecond = requestedTargetsMetersPerSecond
        self.evidencePolicy = evidencePolicy
        self.qualifiedMilestones = qualifiedMilestones
    }

    private func approximatelyEqual(_ lhs: Double, _ rhs: Double) -> Bool {
        let scale = max(1, abs(lhs), abs(rhs))
        return abs(lhs - rhs) <= scale * 1e-9
    }
}
