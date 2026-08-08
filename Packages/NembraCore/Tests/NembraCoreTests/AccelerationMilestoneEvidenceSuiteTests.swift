import Foundation
import Testing
@testable import NembraCore

@Suite("Acceleration milestone evidence suite")
struct AccelerationMilestoneEvidenceSuiteTests {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func telemetryPolicy(
        source: SpeedTelemetrySource = .scooterBluetooth
    ) throws -> SpeedTelemetryQualityPolicy {
        try SpeedTelemetryQualityPolicy(
            requiredSource: source,
            minimumAcceptedSampleCount: 3,
            maximumRejectedSampleFraction: 0,
            maximumMeanIntervalMilliseconds: 300,
            maximumObservedIntervalMilliseconds: 300,
            maximumJitterStandardDeviationMilliseconds: 300,
            maximumEmpiricalSpeedStepKilometersPerHour: 4
        )
    }

    private func policy(
        targets: [Double] = [2, 4, 6],
        telemetrySource: SpeedTelemetrySource = .scooterBluetooth
    ) throws -> AccelerationMilestoneEvidenceSuitePolicy {
        try AccelerationMilestoneEvidenceSuitePolicy(
            targetsMetersPerSecond: targets,
            stationaryMaximumMetersPerSecond: 0.25,
            source: .scooterBluetooth,
            maximumSampleIntervalNanoseconds: 300_000_000,
            telemetry: telemetryPolicy(source: telemetrySource)
        )
    }

    private func sample(
        metersPerSecond: Double,
        uptimeNanoseconds: UInt64
    ) throws -> SpeedTelemetrySample {
        try SpeedTelemetrySample(
            source: .scooterBluetooth,
            provenance: .absoluteMeasurement,
            metersPerSecond: metersPerSecond,
            receivedAtUptimeNanoseconds: uptimeNanoseconds,
            receivedAtDate: epoch.addingTimeInterval(
                Double(uptimeNanoseconds) / 1_000_000_000
            )
        )
    }

    @Test("policy requires an intentional strictly increasing target set")
    func targetShapeIsFailClosed() throws {
        #expect(throws: AccelerationMilestoneEvidenceSuitePolicyError.targetListRequired) {
            _ = try policy(targets: [])
        }

        #expect(throws: AccelerationMilestoneEvidenceSuitePolicyError
            .targetsMustBeStrictlyIncreasing(previous: 2, current: 2)) {
            _ = try policy(targets: [2, 2, 4])
        }

        #expect(throws: AccelerationMilestoneEvidenceSuitePolicyError
            .targetsMustBeStrictlyIncreasing(previous: 4, current: 3)) {
            _ = try policy(targets: [2, 4, 3])
        }
    }

    @Test("every milestone inherits the same source and telemetry policy")
    func commonEvidencePolicyIsEnforced() throws {
        let suitePolicy = try policy()
        #expect(suitePolicy.sessionPolicies.count == 3)
        #expect(suitePolicy.sessionPolicies.allSatisfy { $0.source == .scooterBluetooth })
        #expect(suitePolicy.sessionPolicies.allSatisfy { $0.telemetry == suitePolicy.sessionPolicies[0].telemetry })

        #expect(throws: AccelerationMilestoneEvidenceSuitePolicyError.evidencePolicy(
            .sourceMismatch(run: .scooterBluetooth, telemetry: .gps)
        )) {
            _ = try policy(telemetrySource: .gps)
        }
    }

    @Test("one accepted stream can qualify multiple observed milestones")
    func sharedStreamProducesMilestones() throws {
        var suite = AccelerationMilestoneEvidenceSuite(policy: try policy())
        for evidence in try [
            sample(metersPerSecond: 0, uptimeNanoseconds: 1_000_000_000),
            sample(metersPerSecond: 1, uptimeNanoseconds: 1_100_000_000),
            sample(metersPerSecond: 2, uptimeNanoseconds: 1_200_000_000),
            sample(metersPerSecond: 3, uptimeNanoseconds: 1_300_000_000),
            sample(metersPerSecond: 4, uptimeNanoseconds: 1_400_000_000),
            sample(metersPerSecond: 5, uptimeNanoseconds: 1_500_000_000),
            sample(metersPerSecond: 6, uptimeNanoseconds: 1_600_000_000)
        ] {
            suite.record(evidence)
        }

        let snapshot = suite.snapshot
        #expect(snapshot.milestones.map(\.targetMetersPerSecond) == [2, 4, 6])
        #expect(snapshot.allMilestonesReady)
        #expect(snapshot.highestReadyTargetMetersPerSecond == 6)

        let elapsed = try snapshot.milestones.map { milestone in
            try #require(milestone.readiness.result)
                .stationaryToTargetObservationElapsedSeconds
        }
        #expect(elapsed.count == 3)
        #expect(abs(elapsed[0] - 0.2) < 0.000_001)
        #expect(abs(elapsed[1] - 0.4) < 0.000_001)
        #expect(abs(elapsed[2] - 0.6) < 0.000_001)
    }

    @Test("a later measurement gap cannot erase an already sealed lower milestone")
    func laterGapInvalidatesOnlyUnfinishedMilestones() throws {
        var suite = AccelerationMilestoneEvidenceSuite(policy: try policy())
        for evidence in try [
            sample(metersPerSecond: 0, uptimeNanoseconds: 1_000_000_000),
            sample(metersPerSecond: 1, uptimeNanoseconds: 1_100_000_000),
            sample(metersPerSecond: 2, uptimeNanoseconds: 1_200_000_000),
            sample(metersPerSecond: 3, uptimeNanoseconds: 1_700_000_000)
        ] {
            suite.record(evidence)
        }

        let milestones = suite.snapshot.milestones
        #expect(milestones[0].readiness.isReady)
        #expect(milestones[1].session.runState == .invalidated(.measurementGapExceeded))
        #expect(milestones[2].session.runState == .invalidated(.measurementGapExceeded))
        #expect(suite.snapshot.highestReadyTargetMetersPerSecond == 2)
        #expect(!suite.snapshot.allMilestonesReady)
    }

    @Test("a continuity interruption preserves completed evidence and blocks later targets")
    func interruptionPreservesOnlyCompletedMilestones() throws {
        var suite = AccelerationMilestoneEvidenceSuite(policy: try policy())
        for evidence in try [
            sample(metersPerSecond: 0, uptimeNanoseconds: 1_000_000_000),
            sample(metersPerSecond: 1, uptimeNanoseconds: 1_100_000_000),
            sample(metersPerSecond: 2, uptimeNanoseconds: 1_200_000_000)
        ] {
            suite.record(evidence)
        }

        suite.interrupt(.vehicleConnectionLost)

        let milestones = suite.snapshot.milestones
        #expect(milestones[0].readiness.isReady)
        #expect(milestones[1].session.runState == .invalidated(
            .interruption(.vehicleConnectionLost)
        ))
        #expect(milestones[2].session.runState == .invalidated(
            .interruption(.vehicleConnectionLost)
        ))
        #expect(milestones[1].readiness.failures.contains(.knownObservationInterruption(count: 1)))
        #expect(milestones[2].readiness.failures.contains(.knownObservationInterruption(count: 1)))
    }
}
