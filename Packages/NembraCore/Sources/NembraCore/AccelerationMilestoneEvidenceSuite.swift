import Foundation

public enum AccelerationMilestoneEvidenceSuitePolicyError: Error, Equatable, Sendable {
    case targetListRequired
    case targetsMustBeStrictlyIncreasing(previous: Double, current: Double)
    case runPolicy(AccelerationRunPolicyError)
    case evidencePolicy(AccelerationEvidenceSessionPolicyError)
}

/// One policy for a family of acceleration milestones observed from the same
/// authoritative speed stream.
///
/// Every milestone inherits the exact same source, stationary threshold,
/// cadence/accuracy requirements, and telemetry-quality policy. Only the target
/// speed changes. This prevents product code from accidentally comparing
/// 0→target results assembled under different evidence rules.
public struct AccelerationMilestoneEvidenceSuitePolicy: Equatable, Sendable {
    public let targetsMetersPerSecond: [Double]
    public let sessionPolicies: [AccelerationEvidenceSessionPolicy]

    public init(
        targetsMetersPerSecond: [Double],
        stationaryMaximumMetersPerSecond: Double,
        source: SpeedTelemetrySource,
        maximumSpeedAccuracyMetersPerSecond: Double? = nil,
        maximumSampleIntervalNanoseconds: UInt64,
        telemetry: SpeedTelemetryQualityPolicy
    ) throws {
        guard !targetsMetersPerSecond.isEmpty else {
            throw AccelerationMilestoneEvidenceSuitePolicyError.targetListRequired
        }

        var previousTarget: Double?
        var policies: [AccelerationEvidenceSessionPolicy] = []
        policies.reserveCapacity(targetsMetersPerSecond.count)

        for target in targetsMetersPerSecond {
            if let previousTarget, target <= previousTarget {
                throw AccelerationMilestoneEvidenceSuitePolicyError
                    .targetsMustBeStrictlyIncreasing(previous: previousTarget, current: target)
            }

            let run: AccelerationRunPolicy
            do {
                run = try AccelerationRunPolicy(
                    targetMetersPerSecond: target,
                    stationaryMaximumMetersPerSecond: stationaryMaximumMetersPerSecond,
                    requiredSource: source,
                    maximumSpeedAccuracyMetersPerSecond: maximumSpeedAccuracyMetersPerSecond,
                    maximumSampleIntervalNanoseconds: maximumSampleIntervalNanoseconds
                )
            } catch let error as AccelerationRunPolicyError {
                throw AccelerationMilestoneEvidenceSuitePolicyError.runPolicy(error)
            }

            do {
                policies.append(try AccelerationEvidenceSessionPolicy(
                    run: run,
                    telemetry: telemetry
                ))
            } catch let error as AccelerationEvidenceSessionPolicyError {
                throw AccelerationMilestoneEvidenceSuitePolicyError.evidencePolicy(error)
            }

            previousTarget = target
        }

        self.targetsMetersPerSecond = targetsMetersPerSecond
        self.sessionPolicies = policies
    }
}

public struct AccelerationMilestoneEvidence: Equatable, Sendable {
    public let targetMetersPerSecond: Double
    public let session: AccelerationEvidenceSessionSnapshot

    public var readiness: AccelerationEvidenceReadiness {
        session.readiness()
    }

    fileprivate init(
        targetMetersPerSecond: Double,
        session: AccelerationEvidenceSessionSnapshot
    ) {
        self.targetMetersPerSecond = targetMetersPerSecond
        self.session = session
    }
}

public struct AccelerationMilestoneEvidenceSuiteSnapshot: Equatable, Sendable {
    public let milestones: [AccelerationMilestoneEvidence]

    public var allMilestonesReady: Bool {
        !milestones.isEmpty && milestones.allSatisfy { $0.readiness.isReady }
    }

    public var highestReadyTargetMetersPerSecond: Double? {
        milestones.last(where: { $0.readiness.isReady })?.targetMetersPerSecond
    }

    fileprivate init(milestones: [AccelerationMilestoneEvidence]) {
        self.milestones = milestones
    }
}

/// Evaluates several acceleration milestones from one shared measurement stream.
///
/// The suite deliberately delegates each target to `AccelerationEvidenceSession`
/// instead of introducing a second timing model. All sessions receive the exact
/// same callbacks and interruptions in the exact same order. A lower milestone
/// that has already completed remains immutable if a later gap/interruption makes
/// higher targets unreportable; missing evidence is never stitched across the
/// break to complete those later milestones.
public struct AccelerationMilestoneEvidenceSuite: Sendable {
    public let policy: AccelerationMilestoneEvidenceSuitePolicy

    private var sessions: [AccelerationEvidenceSession]

    public init(policy: AccelerationMilestoneEvidenceSuitePolicy) {
        self.policy = policy
        self.sessions = policy.sessionPolicies.map { sessionPolicy in
            AccelerationEvidenceSession(policy: sessionPolicy)
        }
    }

    public mutating func record(_ sample: SpeedTelemetrySample) {
        for index in sessions.indices {
            _ = sessions[index].record(sample)
        }
    }

    public mutating func interrupt(_ interruption: AccelerationRunInterruption) {
        for index in sessions.indices {
            sessions[index].interrupt(interruption)
        }
    }

    public var snapshot: AccelerationMilestoneEvidenceSuiteSnapshot {
        let milestones = zip(policy.targetsMetersPerSecond, sessions).map { target, session in
            AccelerationMilestoneEvidence(
                targetMetersPerSecond: target,
                session: session.snapshot
            )
        }
        return AccelerationMilestoneEvidenceSuiteSnapshot(milestones: milestones)
    }
}
