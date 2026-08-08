import Foundation
import Testing
@testable import NembraCore

@Suite("Acceleration milestone attempt archive")
struct AccelerationMilestoneAttemptArchiveTests {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)
    private let attemptID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    private func policy(
        targets: [Double] = [2, 4, 6]
    ) throws -> AccelerationMilestoneEvidenceSuitePolicy {
        let telemetry = try SpeedTelemetryQualityPolicy(
            requiredSource: .scooterBluetooth,
            minimumAcceptedSampleCount: 3,
            maximumRejectedSampleFraction: 0,
            maximumMeanIntervalMilliseconds: 300,
            maximumObservedIntervalMilliseconds: 300,
            maximumJitterStandardDeviationMilliseconds: 300,
            maximumEmpiricalSpeedStepKilometersPerHour: 4
        )
        return try AccelerationMilestoneEvidenceSuitePolicy(
            targetsMetersPerSecond: targets,
            stationaryMaximumMetersPerSecond: 0.25,
            source: .scooterBluetooth,
            maximumSampleIntervalNanoseconds: 300_000_000,
            telemetry: telemetry
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

    private func completeSuite() throws -> AccelerationMilestoneEvidenceSuite {
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
        return suite
    }

    private func completeArchiveData() throws -> Data {
        try JSONEncoder().encode(
            AccelerationMilestoneAttemptArchive(
                snapshot: completeSuite().snapshot,
                attemptID: attemptID,
                archivedAt: epoch
            )
        )
    }

    @Test("qualified milestones round-trip with their exact qualification policy")
    func qualifiedRoundTrip() throws {
        let suite = try completeSuite()
        let archive = try AccelerationMilestoneAttemptArchive(
            snapshot: suite.snapshot,
            attemptID: attemptID,
            archivedAt: epoch
        )

        #expect(archive.schemaVersion == 1)
        #expect(archive.attemptID == attemptID)
        #expect(archive.archivedAt == epoch)
        #expect(archive.requestedTargetsMetersPerSecond == [2, 4, 6])
        #expect(archive.qualifiedMilestones.map(\.targetMetersPerSecond) == [2, 4, 6])
        #expect(archive.isComplete)
        #expect(archive.highestQualifiedTargetMetersPerSecond == 6)
        #expect(archive.evidencePolicy.source == .scooterBluetooth)
        #expect(archive.evidencePolicy.minimumAcceptedSampleCount == 3)
        #expect(archive.evidencePolicy.maximumSampleIntervalNanoseconds == 300_000_000)

        let first = try #require(archive.qualifiedMilestones.first)
        #expect(first.timingBasis == .receiveObservationUptime)
        #expect(first.timingEvidenceSampleCount == 3)
        #expect(first.quality.acceptedSampleCount == 3)
        #expect(abs(first.stationaryToTargetObservationElapsedSeconds - 0.2) < 0.000_001)
        #expect(abs(first.quality.observedDurationSeconds - 0.2) < 0.000_001)

        let data = try JSONEncoder().encode(archive)
        let decoded = try JSONDecoder().decode(
            AccelerationMilestoneAttemptArchive.self,
            from: data
        )
        #expect(decoded == archive)
    }

    @Test("partial attempts preserve requested coverage without inventing failed milestones")
    func partialAttemptArchivesOnlyQualifiedEvidence() throws {
        var suite = AccelerationMilestoneEvidenceSuite(policy: try policy())
        for evidence in try [
            sample(metersPerSecond: 0, uptimeNanoseconds: 1_000_000_000),
            sample(metersPerSecond: 1, uptimeNanoseconds: 1_100_000_000),
            sample(metersPerSecond: 2, uptimeNanoseconds: 1_200_000_000),
            sample(metersPerSecond: 3, uptimeNanoseconds: 1_700_000_000)
        ] {
            suite.record(evidence)
        }

        let archive = try AccelerationMilestoneAttemptArchive(
            snapshot: suite.snapshot,
            attemptID: attemptID,
            archivedAt: epoch
        )

        #expect(archive.requestedTargetsMetersPerSecond == [2, 4, 6])
        #expect(archive.qualifiedMilestones.map(\.targetMetersPerSecond) == [2])
        #expect(!archive.isComplete)
        #expect(archive.highestQualifiedTargetMetersPerSecond == 2)
    }

    @Test("an attempt with no reportable milestone cannot become history")
    func noQualifiedEvidenceIsRejected() throws {
        var suite = AccelerationMilestoneEvidenceSuite(policy: try policy())
        suite.record(try sample(
            metersPerSecond: 1,
            uptimeNanoseconds: 1_000_000_000
        ))

        #expect(throws: AccelerationMilestoneAttemptArchiveError.noQualifiedMilestones) {
            _ = try AccelerationMilestoneAttemptArchive(
                snapshot: suite.snapshot,
                attemptID: attemptID,
                archivedAt: epoch
            )
        }
    }

    @Test("archive encoding contains no raw uptime anchors that could be resumed")
    func encodedArchiveDoesNotPersistProcessUptimeAnchors() throws {
        let data = try completeArchiveData()
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(!json.contains("earliestUptimeNanoseconds"))
        #expect(!json.contains("latestUptimeNanoseconds"))
        #expect(!json.contains("receivedAtUptimeNanoseconds"))
        #expect(json.contains("launchObservationWindowWidthSeconds"))
        #expect(json.contains("targetTransitionObservationWindowWidthSeconds"))
    }

    @Test("decoder rejects a forged qualified target outside the requested attempt")
    func decodeRejectsUnrequestedQualifiedTarget() throws {
        let data = try completeArchiveData()
        var object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        var milestones = try #require(
            object["qualifiedMilestones"] as? [[String: Any]]
        )
        milestones[1]["targetMetersPerSecond"] = 3.0
        object["qualifiedMilestones"] = milestones
        let forged = try JSONSerialization.data(withJSONObject: object)

        #expect(throws: AccelerationMilestoneAttemptArchiveError.qualifiedTargetNotRequested(3)) {
            _ = try JSONDecoder().decode(
                AccelerationMilestoneAttemptArchive.self,
                from: forged
            )
        }
    }

    @Test("decoder reapplies archived quality thresholds instead of trusting the qualified label")
    func decodeRejectsQualityThatNoLongerMeetsArchivedPolicy() throws {
        let data = try completeArchiveData()
        var object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        var milestones = try #require(
            object["qualifiedMilestones"] as? [[String: Any]]
        )
        var quality = try #require(milestones[0]["quality"] as? [String: Any])
        quality["intervalJitterStandardDeviationMilliseconds"] = 400.0
        milestones[0]["quality"] = quality
        object["qualifiedMilestones"] = milestones
        let forged = try JSONSerialization.data(withJSONObject: object)

        #expect(throws: AccelerationMilestoneAttemptArchiveError
            .archivedQualityNotQualified(targetMetersPerSecond: 2)) {
            _ = try JSONDecoder().decode(
                AccelerationMilestoneAttemptArchive.self,
                from: forged
            )
        }
    }

    @Test("decoder rejects impossible motion-assist authority")
    func decodeRejectsMotionAssistAuthority() throws {
        let data = try completeArchiveData()
        var object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        var evidencePolicy = try #require(
            object["evidencePolicy"] as? [String: Any]
        )
        evidencePolicy["source"] = "motionAssist"
        object["evidencePolicy"] = evidencePolicy
        let forged = try JSONSerialization.data(withJSONObject: object)

        #expect(throws: AccelerationMilestoneAttemptArchiveError.invalidPolicy) {
            _ = try JSONDecoder().decode(
                AccelerationMilestoneAttemptArchive.self,
                from: forged
            )
        }
    }

    @Test("decoder rejects negative elapsed evidence and unknown schema")
    func decodeRejectsCorruptEvidenceAndSchema() throws {
        let data = try completeArchiveData()

        var corruptObject = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        var milestones = try #require(
            corruptObject["qualifiedMilestones"] as? [[String: Any]]
        )
        milestones[0]["stationaryToTargetObservationElapsedSeconds"] = -0.2
        corruptObject["qualifiedMilestones"] = milestones
        let corruptData = try JSONSerialization.data(withJSONObject: corruptObject)

        #expect(throws: AccelerationMilestoneAttemptArchiveError
            .invalidQualifiedMilestone(targetMetersPerSecond: 2)) {
            _ = try JSONDecoder().decode(
                AccelerationMilestoneAttemptArchive.self,
                from: corruptData
            )
        }

        var futureObject = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        futureObject["schemaVersion"] = 99
        let futureData = try JSONSerialization.data(withJSONObject: futureObject)

        #expect(throws: AccelerationMilestoneAttemptArchiveError.unsupportedSchemaVersion(99)) {
            _ = try JSONDecoder().decode(
                AccelerationMilestoneAttemptArchive.self,
                from: futureData
            )
        }
    }
}
