import Foundation
import Testing

@testable import NembraCore

@Suite("Observed peak history evidence")
struct RideObservedPeakHistoryEvidenceTests {
    private let sessionID = UUID(uuidString: "12345678-1234-5678-9ABC-123456789ABC")!
    private let epoch = Date(timeIntervalSinceReferenceDate: 40_000)

    private struct Fixture {
        let ride: CompletedRideEvidence
        let readiness: RideObservedPeakReadiness
        let completedPeak: CompletedRidePeakSpeedEvidence?
        let evidence: RideObservedPeakHistoryEvidence
    }

    private actor InMemoryHistoryStore: RideHistoryStore {
        private var records: [UUID: RideHistoryRecord]

        init(records: [RideHistoryRecord] = []) {
            self.records = Dictionary(uniqueKeysWithValues: records.map { ($0.sessionID, $0) })
        }

        func commit(_ record: RideHistoryRecord) async throws -> RideHistoryCommitResult {
            if let existing = records[record.sessionID] {
                guard existing == record else {
                    throw RideHistoryStoreError.sessionConflict(record.sessionID)
                }
                return .alreadyPresent
            }
            records[record.sessionID] = record
            return .inserted
        }

        func record(sessionID: UUID) async throws -> RideHistoryRecord? {
            records[sessionID]
        }
    }

    private actor InMemoryObservedPeakStore: RideHistoryObservedPeakStore {
        private var records: [UUID: RideHistoryObservedPeakRecord] = [:]
        private let suppressReads: Bool

        init(suppressReads: Bool = false) {
            self.suppressReads = suppressReads
        }

        func commit(
            _ record: RideHistoryObservedPeakRecord
        ) async throws -> RideHistoryObservedPeakCommitResult {
            if let existing = records[record.sessionID] {
                guard existing == record else {
                    throw RideHistoryObservedPeakStoreError.sessionConflict(record.sessionID)
                }
                return .alreadyPresent
            }
            records[record.sessionID] = record
            return .inserted
        }

        func record(sessionID: UUID) async throws -> RideHistoryObservedPeakRecord? {
            guard !suppressReads else { return nil }
            return records[sessionID]
        }
    }

    private func completedRide(
        sessionID: UUID? = nil,
        continuity: RideSessionContinuity = .uninterruptedProcess
    ) throws -> CompletedRideEvidence {
        try CompletedRideEvidence(
            sessionID: sessionID ?? self.sessionID,
            beganAtDate: epoch,
            confirmedAtDate: epoch.addingTimeInterval(2),
            endedAtDate: epoch.addingTimeInterval(120),
            startingOdometerKilometers: nil,
            endingOdometerKilometers: nil,
            qualityScreenedGPSDistanceMeters: 0,
            continuity: continuity
        )
    }

    private func sample(
        source: SpeedTelemetrySource = .scooterBluetooth,
        metersPerSecond: Double,
        uptime: UInt64,
        speedAccuracy: Double? = nil
    ) throws -> SpeedTelemetrySample {
        let receivedAt = epoch.addingTimeInterval(Double(uptime) / 1_000_000_000)
        return try SpeedTelemetrySample(
            source: source,
            provenance: source == .motionAssist ? .shortHorizonEstimate : .absoluteMeasurement,
            metersPerSecond: metersPerSecond,
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: receivedAt,
            measurementDate: source == .gps ? receivedAt.addingTimeInterval(-0.05) : nil,
            speedAccuracyMetersPerSecond: speedAccuracy
        )
    }

    private func bluetoothPolicy(
        maximumRejectedFraction: Double = 0
    ) throws -> RideObservedPeakQualityPolicy {
        try RideObservedPeakQualityPolicy(
            telemetry: SpeedTelemetryQualityPolicy(
                requiredSource: .scooterBluetooth,
                minimumAcceptedSampleCount: 3,
                maximumRejectedSampleFraction: maximumRejectedFraction,
                maximumMeanIntervalMilliseconds: 150,
                maximumObservedIntervalMilliseconds: 200,
                maximumJitterStandardDeviationMilliseconds: 50,
                maximumEmpiricalSpeedStepKilometersPerHour: 100
            )
        )
    }

    private func gpsPolicy() throws -> RideObservedPeakQualityPolicy {
        try RideObservedPeakQualityPolicy(
            telemetry: SpeedTelemetryQualityPolicy(
                requiredSource: .gps,
                minimumAcceptedSampleCount: 3,
                maximumRejectedSampleFraction: 0,
                maximumMeanIntervalMilliseconds: 150,
                maximumObservedIntervalMilliseconds: 200,
                maximumJitterStandardDeviationMilliseconds: 50,
                minimumDeliveryLatencySampleFraction: 1,
                maximumMeanDeliveryLatencyMilliseconds: 100,
                maximumEmpiricalSpeedStepKilometersPerHour: 100
            )
        )
    }

    private func cleanFixture(
        sessionID: UUID? = nil,
        speeds: [Double] = [3, 6, 5]
    ) throws -> Fixture {
        let id = sessionID ?? self.sessionID
        let ride = try completedRide(sessionID: id)
        var session = RideSpeedEvidenceSessionAccumulator(
            sessionID: id,
            peakPolicy: try PeakSpeedPolicy(source: .scooterBluetooth)
        )
        for (index, speed) in speeds.enumerated() {
            _ = session.record(try sample(
                metersPerSecond: speed,
                uptime: UInt64(index + 1) * 100_000_000
            ))
        }
        let snapshot = session.snapshot
        let readiness = snapshot.observedPeakReadiness(using: try bluetoothPolicy())
        let livePeak = try #require(snapshot.peakEvidence)
        let completedPeak = try CompletedRidePeakSpeedEvidence(
            completedRide: ride,
            ridePeak: livePeak
        )
        let evidence = try RideObservedPeakHistoryEvidence(
            completedRide: ride,
            completedPeak: completedPeak,
            readiness: readiness
        )
        return Fixture(
            ride: ride,
            readiness: readiness,
            completedPeak: completedPeak,
            evidence: evidence
        )
    }

    private func interruptedFixture() throws -> Fixture {
        let ride = try completedRide()
        var session = RideSpeedEvidenceSessionAccumulator(
            sessionID: sessionID,
            peakPolicy: try PeakSpeedPolicy(source: .scooterBluetooth)
        )
        for (index, speed) in [3.0, 5.0, 4.0].enumerated() {
            _ = session.record(try sample(
                metersPerSecond: speed,
                uptime: UInt64(index + 1) * 100_000_000
            ))
        }
        session.recordInterruption(.selectedSourceUnavailable)
        for (index, speed) in [8.0, 12.0, 10.0].enumerated() {
            _ = session.record(try sample(
                metersPerSecond: speed,
                uptime: 1_000_000_000 + UInt64(index + 1) * 100_000_000
            ))
        }
        let snapshot = session.snapshot
        let readiness = snapshot.observedPeakReadiness(using: try bluetoothPolicy())
        let livePeak = try #require(snapshot.peakEvidence)
        let completedPeak = try CompletedRidePeakSpeedEvidence(
            completedRide: ride,
            ridePeak: livePeak
        )
        let evidence = try RideObservedPeakHistoryEvidence(
            completedRide: ride,
            completedPeak: completedPeak,
            readiness: readiness
        )
        return Fixture(
            ride: ride,
            readiness: readiness,
            completedPeak: completedPeak,
            evidence: evidence
        )
    }

    private func foreignSourceFixture() throws -> Fixture {
        let ride = try completedRide()
        var session = RideSpeedEvidenceSessionAccumulator(
            sessionID: sessionID,
            peakPolicy: try PeakSpeedPolicy(source: .scooterBluetooth)
        )
        for (index, speed) in [3.0, 6.0, 5.0].enumerated() {
            _ = session.record(try sample(
                metersPerSecond: speed,
                uptime: UInt64(index + 1) * 100_000_000
            ))
        }
        _ = session.record(try sample(
            source: .motionAssist,
            metersPerSecond: 7,
            uptime: 400_000_000
        ))
        let snapshot = session.snapshot
        let readiness = snapshot.observedPeakReadiness(
            using: try bluetoothPolicy(maximumRejectedFraction: 1)
        )
        let livePeak = try #require(snapshot.peakEvidence)
        let completedPeak = try CompletedRidePeakSpeedEvidence(
            completedRide: ride,
            ridePeak: livePeak
        )
        let evidence = try RideObservedPeakHistoryEvidence(
            completedRide: ride,
            completedPeak: completedPeak,
            readiness: readiness
        )
        return Fixture(
            ride: ride,
            readiness: readiness,
            completedPeak: completedPeak,
            evidence: evidence
        )
    }

    private func noPeakFixture() throws -> Fixture {
        let ride = try completedRide()
        var session = RideSpeedEvidenceSessionAccumulator(
            sessionID: sessionID,
            peakPolicy: try PeakSpeedPolicy(
                source: .gps,
                maximumSpeedAccuracyMetersPerSecond: 0.5
            )
        )
        for index in 1...3 {
            _ = session.record(try sample(
                source: .gps,
                metersPerSecond: Double(index),
                uptime: UInt64(index) * 100_000_000,
                speedAccuracy: 0.8
            ))
        }
        let snapshot = session.snapshot
        let readiness = snapshot.observedPeakReadiness(using: try gpsPolicy())
        #expect(snapshot.peakEvidence == nil)
        let evidence = try RideObservedPeakHistoryEvidence(
            completedRide: ride,
            completedPeak: nil,
            readiness: readiness
        )
        return Fixture(
            ride: ride,
            readiness: readiness,
            completedPeak: nil,
            evidence: evidence
        )
    }

    @Test("qualified evidence round-trips and revalidates instead of persisting a verdict")
    func qualifiedRoundTrip() throws {
        let fixture = try cleanFixture()
        let record = RideHistoryObservedPeakRecord(evidence: fixture.evidence)
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(RideHistoryObservedPeakRecord.self, from: data)
        let assessment = try decoded.evidence.assessment()

        #expect(decoded == record)
        #expect(assessment.telemetryQuality == fixture.readiness.telemetryQuality)
        #expect(assessment.failures == fixture.readiness.failures)
        #expect(assessment.isReadinessReady)
        #expect(assessment.isObservedMaximumEligible)

        let encodedText = String(decoding: data, as: UTF8.self)
        #expect(!encodedText.contains("isReady"))
        #expect(!encodedText.contains("qualified"))
        #expect(!encodedText.contains("isObservedMaximumEligible"))
    }

    @Test("interrupted faster peak stays unqualified after relaunch")
    func interruptionSurvivesRoundTrip() throws {
        let fixture = try interruptedFixture()
        let data = try JSONEncoder().encode(fixture.evidence)
        let decoded = try JSONDecoder().decode(RideObservedPeakHistoryEvidence.self, from: data)
        let assessment = try decoded.assessment()

        #expect(decoded == fixture.evidence)
        #expect(!assessment.isReadinessReady)
        #expect(!assessment.isObservedMaximumEligible)
        #expect(assessment.failures.contains(.partialPeakObservation))
        #expect(decoded.knownSelectedSourceInterruptionCount == 1)
    }

    @Test("foreign-source provenance remains disqualifying and preserves all peak rejections")
    func foreignSourceSurvivesRoundTrip() throws {
        let fixture = try foreignSourceFixture()
        let decoded = try JSONDecoder().decode(
            RideObservedPeakHistoryEvidence.self,
            from: JSONEncoder().encode(fixture.evidence)
        )
        let assessment = try decoded.assessment()

        #expect(decoded.foreignSourceCallbackCount == 1)
        #expect(decoded.peakRejections.nonAuthoritativeSampleCount == 1)
        #expect(decoded.completedPeak?.qualityRejectedSampleCount == decoded.peakRejections.totalRejectedSampleCount)
        #expect(!assessment.isObservedMaximumEligible)
        #expect(assessment.failures.contains(.foreignSourceTraffic(callbackCount: 1)))
    }

    @Test("missing peak remains unavailable rather than becoming observed zero")
    func unavailablePeakSurvivesRoundTrip() throws {
        let fixture = try noPeakFixture()
        let decoded = try JSONDecoder().decode(
            RideObservedPeakHistoryEvidence.self,
            from: JSONEncoder().encode(fixture.evidence)
        )
        let assessment = try decoded.assessment()

        #expect(decoded.completedPeak == nil)
        #expect(assessment.failures.contains(.peakUnavailable))
        #expect(!assessment.isObservedMaximumEligible)
    }

    @Test("corrupt negative rejection count fails decoding")
    func corruptRejectionCountRejected() throws {
        let data = try mutatedJSON(try cleanFixture().evidence) { root in
            var rejections = root["peakRejections"] as! [String: Any]
            rejections["nonFiniteDerivedSpeedCount"] = -1
            root["peakRejections"] = rejections
        }
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(RideObservedPeakHistoryEvidence.self, from: data)
        }
    }

    @Test("corrupt benchmark topology fails decoding")
    func corruptBenchmarkTopologyRejected() throws {
        let data = try mutatedJSON(try cleanFixture().evidence) { root in
            var benchmark = root["telemetryBenchmark"] as! [String: Any]
            benchmark["intervalCount"] = 99
            root["telemetryBenchmark"] = benchmark
        }
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(RideObservedPeakHistoryEvidence.self, from: data)
        }
    }

    @Test("corrupt feature policy fails decoding")
    func corruptPolicyRejected() throws {
        let data = try mutatedJSON(try cleanFixture().evidence) { root in
            var policy = root["policy"] as! [String: Any]
            policy["minimumAcceptedSampleCount"] = 2
            root["policy"] = policy
        }
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(RideObservedPeakHistoryEvidence.self, from: data)
        }
    }

    @Test("same session cannot pair a different durable peak with the live readiness audit")
    func mismatchedPeakRejected() throws {
        let fixture = try cleanFixture(speeds: [2, 5, 4])
        var otherAccumulator = RidePeakSpeedEvidenceAccumulator(
            sessionID: sessionID,
            policy: try PeakSpeedPolicy(source: .scooterBluetooth)
        )
        _ = otherAccumulator.record(try sample(
            metersPerSecond: 9,
            uptime: 100_000_000
        ))
        let otherPeak = try #require(otherAccumulator.evidence)
        let otherDurable = try CompletedRidePeakSpeedEvidence(
            completedRide: fixture.ride,
            ridePeak: otherPeak
        )

        #expect(throws: RideObservedPeakHistoryEvidenceError.evidenceMismatch) {
            try RideObservedPeakHistoryEvidence(
                completedRide: fixture.ride,
                completedPeak: otherDurable,
                readiness: fixture.readiness
            )
        }
    }

    @Test("history attachment commits idempotently only after base history exists")
    func commitAndJoin() async throws {
        let fixture = try cleanFixture()
        let historyRecord = RideHistoryRecord(evidence: fixture.ride)
        let coordinator = RideHistoryObservedPeakCommitCoordinator(
            historyStore: InMemoryHistoryStore(records: [historyRecord]),
            observedPeakStore: InMemoryObservedPeakStore()
        )

        #expect(try await coordinator.commit(fixture.evidence) == .inserted)
        #expect(try await coordinator.commit(fixture.evidence) == .alreadyPresent)
        let joined = try await coordinator.joinedRecord(sessionID: sessionID)
        #expect(joined?.historyRecord == historyRecord)
        #expect(joined?.observedPeakRecord.evidence == fixture.evidence)
        #expect(try joined?.assessment().isObservedMaximumEligible == true)
    }

    @Test("missing base history fails closed while missing attachment is ordinary unavailability")
    func baseHistoryRequirements() async throws {
        let fixture = try cleanFixture()
        let emptyCoordinator = RideHistoryObservedPeakCommitCoordinator(
            historyStore: InMemoryHistoryStore(),
            observedPeakStore: InMemoryObservedPeakStore()
        )
        await #expect(
            throws: RideHistoryObservedPeakCommitCoordinatorError.missingCompletedRide(sessionID)
        ) {
            _ = try await emptyCoordinator.commit(fixture.evidence)
        }

        let historyOnly = RideHistoryObservedPeakCommitCoordinator(
            historyStore: InMemoryHistoryStore(records: [RideHistoryRecord(evidence: fixture.ride)]),
            observedPeakStore: InMemoryObservedPeakStore()
        )
        #expect(try await historyOnly.joinedRecord(sessionID: sessionID) == nil)
    }

    @Test("orphaned attachment and wrong continuity fail closed")
    func orphanAndContinuityMismatchRejected() async throws {
        let fixture = try cleanFixture()
        let observedStore = InMemoryObservedPeakStore()
        _ = try await observedStore.commit(RideHistoryObservedPeakRecord(evidence: fixture.evidence))
        let orphanCoordinator = RideHistoryObservedPeakCommitCoordinator(
            historyStore: InMemoryHistoryStore(),
            observedPeakStore: observedStore
        )
        await #expect(
            throws: RideHistoryObservedPeakCommitCoordinatorError.missingCompletedRide(sessionID)
        ) {
            _ = try await orphanCoordinator.joinedRecord(sessionID: sessionID)
        }

        let recoveredRide = try completedRide(continuity: .recoveredCheckpoint)
        let mismatched = RideHistoryObservedPeakCommitCoordinator(
            historyStore: InMemoryHistoryStore(records: [RideHistoryRecord(evidence: recoveredRide)]),
            observedPeakStore: InMemoryObservedPeakStore()
        )
        await #expect(
            throws: RideHistoryObservedPeakCommitCoordinatorError.completedRideMismatch(sessionID)
        ) {
            _ = try await mismatched.commit(fixture.evidence)
        }
    }

    @Test("immutable attachment rejects conflicting replacement and requires exact read-back")
    func conflictAndReadBack() async throws {
        let first = try cleanFixture(speeds: [2, 5, 4])
        let second = try cleanFixture(speeds: [2, 7, 4])
        let store = InMemoryObservedPeakStore()
        let coordinator = RideHistoryObservedPeakCommitCoordinator(
            historyStore: InMemoryHistoryStore(records: [RideHistoryRecord(evidence: first.ride)]),
            observedPeakStore: store
        )
        _ = try await coordinator.commit(first.evidence)
        await #expect(throws: RideHistoryObservedPeakStoreError.sessionConflict(sessionID)) {
            _ = try await coordinator.commit(second.evidence)
        }

        let unreadableCoordinator = RideHistoryObservedPeakCommitCoordinator(
            historyStore: InMemoryHistoryStore(records: [RideHistoryRecord(evidence: first.ride)]),
            observedPeakStore: InMemoryObservedPeakStore(suppressReads: true)
        )
        await #expect(
            throws: RideHistoryObservedPeakCommitCoordinatorError.durableVerificationFailed(sessionID)
        ) {
            _ = try await unreadableCoordinator.commit(first.evidence)
        }
    }

    private func mutatedJSON(
        _ evidence: RideObservedPeakHistoryEvidence,
        mutate: (inout [String: Any]) -> Void
    ) throws -> Data {
        let data = try JSONEncoder().encode(evidence)
        var root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        mutate(&root)
        return try JSONSerialization.data(withJSONObject: root)
    }
}
