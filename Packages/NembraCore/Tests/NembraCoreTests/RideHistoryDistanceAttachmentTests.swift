import Foundation
import Testing

@testable import NembraCore

@Suite("Ride history distance attachment")
struct RideHistoryDistanceAttachmentTests {
    private let sessionID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

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

    private actor InMemoryDistanceStore: RideHistoryDistanceStore {
        private var checkpoints: [UUID: RideHistoryDistanceCheckpoint] = [:]
        private let suppressReads: Bool

        init(suppressReads: Bool = false) {
            self.suppressReads = suppressReads
        }

        func commit(
            _ checkpoint: RideHistoryDistanceCheckpoint
        ) async throws -> RideHistoryDistanceCommitResult {
            if let existing = checkpoints[checkpoint.sessionID] {
                guard existing == checkpoint else {
                    throw RideHistoryDistanceStoreError.sessionConflict(checkpoint.sessionID)
                }
                return .alreadyPresent
            }
            checkpoints[checkpoint.sessionID] = checkpoint
            return .inserted
        }

        func checkpoint(sessionID: UUID) async throws -> RideHistoryDistanceCheckpoint? {
            guard !suppressReads else { return nil }
            return checkpoints[sessionID]
        }
    }

    private func completedRide(
        sessionID: UUID? = nil,
        gpsDistanceMeters: Double = 995,
        continuity: RideSessionContinuity = .uninterruptedProcess
    ) throws -> CompletedRideEvidence {
        try CompletedRideEvidence(
            sessionID: sessionID ?? self.sessionID,
            beganAtDate: Date(timeIntervalSinceReferenceDate: 1_000),
            confirmedAtDate: Date(timeIntervalSinceReferenceDate: 1_010),
            endedAtDate: Date(timeIntervalSinceReferenceDate: 1_200),
            startingOdometerKilometers: 10,
            endingOdometerKilometers: 11,
            qualityScreenedGPSDistanceMeters: gpsDistanceMeters,
            continuity: continuity
        )
    }

    private func policy(
        sourcePriority: [RideDistanceSource] = [
            .gpsRoute,
            .scooterOdometer,
            .liveSpeedIntegration,
        ]
    ) throws -> RideDistanceReconciliationPolicy {
        try RideDistanceReconciliationPolicy(
            sourcePriority: sourcePriority,
            absoluteAgreementToleranceMeters: 10,
            relativeAgreementTolerance: 0.02,
            minimumRelativeComparisonDistanceMeters: 100,
            allowOdometerToRecoverKnownCoverageGaps: false
        )
    }

    private func attachment(
        history: RideHistoryRecord,
        odometerCoverage: RideDistanceCoverage = .complete,
        gpsCoverage: RideDistanceCoverage = .complete,
        liveDistanceCheckpoint: RideHistoryLiveDistanceCheckpoint? = nil
    ) throws -> RideHistoryDistanceRecord {
        try RideHistoryDistanceRecord(
            historyRecord: history,
            odometerCoverage: odometerCoverage,
            gpsRouteCoverage: gpsCoverage,
            liveDistanceCheckpoint: liveDistanceCheckpoint,
            transportGapOccurred: false,
            reconciliationPolicy: policy()
        )
    }

    private func liveSegment(
        rideSessionID: UUID,
        distanceMeters: Double = 900,
        coverage: RideDistanceCoverage = .complete
    ) throws -> RideLiveDistanceSegmentEvidence {
        let finalized = FinalizedLiveDistanceSegment(
            source: .scooterBluetooth,
            method: .trapezoidalBetweenMeasurements,
            segmentStartUptimeNanoseconds: 100,
            segmentEndUptimeNanoseconds: 200,
            firstAcceptedSampleUptimeNanoseconds: 100,
            lastAcceptedSampleUptimeNanoseconds: 200,
            distanceMeters: distanceMeters,
            coverage: coverage,
            acceptedSampleCount: 2,
            integratedIntervalCount: 1,
            knownCoverageGapCount: coverage == .complete ? 0 : 1
        )
        return try RideLiveDistanceSegmentEvidence(
            rideSessionID: rideSessionID,
            segmentID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            processSegmentSequence: 0,
            finalizedSegment: finalized
        )
    }

    @Test("distance attachment commits checkpoint idempotently only after immutable base history exists")
    func commitAndJoin() async throws {
        let history = RideHistoryRecord(evidence: try completedRide())
        let record = try attachment(history: history)
        let distanceStore = InMemoryDistanceStore()
        let coordinator = RideHistoryDistanceCommitCoordinator(
            historyStore: InMemoryHistoryStore(records: [history]),
            distanceStore: distanceStore
        )

        #expect(try await coordinator.commit(record) == .inserted)
        #expect(try await coordinator.commit(record) == .alreadyPresent)
        #expect(try await distanceStore.checkpoint(sessionID: sessionID) == record.checkpoint)

        let joined = try await coordinator.joinedRecord(sessionID: sessionID)
        #expect(joined?.historyRecord == history)
        #expect(joined?.distanceRecord == record)
        #expect(joined?.reconciledDistance.finalDistanceMeters == 995)
        #expect(joined?.reconciledDistance.status == .complete)
    }

    @Test("selected partial source remains incomplete after durable join and statistics bridge")
    func selectedPartialSourceRemainsIncomplete() throws {
        let history = RideHistoryRecord(evidence: try completedRide())
        let record = try attachment(
            history: history,
            odometerCoverage: .complete,
            gpsCoverage: .partial
        )
        let joined = try RideHistoryDistanceJoinedRecord(
            historyRecord: history,
            distanceRecord: record
        )

        #expect(joined.reconciledDistance.finalSource == .gpsRoute)
        #expect(joined.reconciledDistance.finalDistanceMeters == 995)
        #expect(joined.reconciledDistance.confidence == .corroborated)
        #expect(joined.reconciledDistance.status == .coverageIncomplete)

        let statisticsRide = try RideStatisticsRide(
            historyDistanceRecord: joined,
            calendarAttribution: .rideEnded
        )
        #expect(statisticsRide.sessionID == sessionID)
        #expect(statisticsRide.distanceMeters == 995)
        #expect(statisticsRide.distanceDisposition == .excludedIncompleteCoverage)
        #expect(statisticsRide.attributedDate == history.evidence.endedAtDate)
    }

    @Test("complete selected-source evidence crosses the canonical sealed statistics bridge")
    func completeDistanceIsIncluded() throws {
        let history = RideHistoryRecord(evidence: try completedRide())
        let joined = try RideHistoryDistanceJoinedRecord(
            historyRecord: history,
            distanceRecord: attachment(history: history)
        )

        let statisticsRide = try RideStatisticsRide(
            historyDistanceRecord: joined,
            calendarAttribution: .rideBegan
        )

        #expect(statisticsRide.distanceDisposition == .included)
        #expect(statisticsRide.distanceMeters == 995)
        #expect(statisticsRide.attributedDate == history.evidence.beganAtDate)
    }

    @Test("only checkpoint inputs are Codable; trusted record is restored through exact base history")
    func checkpointRoundTripRequiresSealedRestore() throws {
        let history = RideHistoryRecord(evidence: try completedRide())
        let original = try attachment(
            history: history,
            odometerCoverage: .complete,
            gpsCoverage: .partial
        )

        let data = try JSONEncoder().encode(original.checkpoint)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("finalDistanceMeters"))
        #expect(!json.contains("reconciledDistance"))
        #expect(!json.contains("confidence"))
        #expect(!json.contains("status"))

        let decoded = try JSONDecoder().decode(RideHistoryDistanceCheckpoint.self, from: data)
        #expect(decoded == original.checkpoint)

        let restored = try RideHistoryDistanceRecord(
            checkpoint: decoded,
            historyRecord: history
        )
        #expect(restored == original)

        let joined = try RideHistoryDistanceJoinedRecord(
            historyRecord: history,
            distanceRecord: restored
        )
        #expect(joined.reconciledDistance.status == .coverageIncomplete)
        #expect(joined.reconciledDistance.finalDistanceMeters == 995)
    }

    @Test("decoded checkpoint cannot be restored against a different immutable base with the same UUID")
    func decodedCheckpointStillRequiresExactBaseEvidence() throws {
        let originalHistory = RideHistoryRecord(evidence: try completedRide(gpsDistanceMeters: 995))
        let original = try attachment(history: originalHistory)
        let data = try JSONEncoder().encode(original.checkpoint)
        let decoded = try JSONDecoder().decode(RideHistoryDistanceCheckpoint.self, from: data)
        let conflictingHistory = RideHistoryRecord(evidence: try completedRide(gpsDistanceMeters: 800))

        #expect(
            throws: RideHistoryDistanceAttachmentError.completedRideMismatch(sessionID)
        ) {
            _ = try RideHistoryDistanceRecord(
                checkpoint: decoded,
                historyRecord: conflictingHistory
            )
        }
    }

    @Test("durable store returns checkpoint only; coordinator remints trusted record on each read")
    func durableReadRequiresHistoryBackedRestore() async throws {
        let history = RideHistoryRecord(evidence: try completedRide())
        let record = try attachment(history: history)
        let checkpointData = try JSONEncoder().encode(record.checkpoint)
        let decodedCheckpoint = try JSONDecoder().decode(
            RideHistoryDistanceCheckpoint.self,
            from: checkpointData
        )
        let distanceStore = InMemoryDistanceStore()
        _ = try await distanceStore.commit(decodedCheckpoint)
        let coordinator = RideHistoryDistanceCommitCoordinator(
            historyStore: InMemoryHistoryStore(records: [history]),
            distanceStore: distanceStore
        )

        let first = try #require(await coordinator.joinedRecord(sessionID: sessionID))
        let second = try #require(await coordinator.joinedRecord(sessionID: sessionID))
        #expect(first.distanceRecord == record)
        #expect(second.distanceRecord == record)
        #expect(first.reconciledDistance == second.reconciledDistance)
    }

    @Test("live-distance aggregate is rebuilt from durable segment checkpoint evidence")
    func durableLiveSegmentsAreReaggregated() throws {
        let history = RideHistoryRecord(evidence: try completedRide(gpsDistanceMeters: 0))
        let live = try RideHistoryLiveDistanceCheckpoint(
            source: .scooterBluetooth,
            method: .trapezoidalBetweenMeasurements,
            segmentRecords: [try liveSegment(rideSessionID: sessionID, distanceMeters: 900)]
        )
        let liveFirstPolicy = try policy(
            sourcePriority: [.liveSpeedIntegration, .scooterOdometer, .gpsRoute]
        )
        let record = try RideHistoryDistanceRecord(
            historyRecord: history,
            odometerCoverage: .complete,
            gpsRouteCoverage: .unknown,
            liveDistanceCheckpoint: live,
            transportGapOccurred: false,
            reconciliationPolicy: liveFirstPolicy
        )
        let joined = try RideHistoryDistanceJoinedRecord(
            historyRecord: history,
            distanceRecord: record
        )

        #expect(joined.reconciledDistance.finalSource == .liveSpeedIntegration)
        #expect(joined.reconciledDistance.finalDistanceMeters == 900)
        #expect(joined.reconciledDistance.finalSourceCoverage == .complete)
    }

    @Test("foreign live-distance session cannot enter a trusted history attachment")
    func foreignLiveSessionRejected() throws {
        let history = RideHistoryRecord(evidence: try completedRide())
        let foreignSessionID = UUID(uuidString: "99999999-8888-7777-6666-555555555555")!
        let live = try RideHistoryLiveDistanceCheckpoint(
            source: .scooterBluetooth,
            method: .trapezoidalBetweenMeasurements,
            segmentRecords: [try liveSegment(rideSessionID: foreignSessionID)]
        )

        #expect(throws: RideHistoryDistanceAttachmentError.invalidLiveDistanceEvidence) {
            _ = try RideHistoryDistanceRecord(
                historyRecord: history,
                odometerCoverage: .complete,
                gpsRouteCoverage: .complete,
                liveDistanceCheckpoint: live,
                transportGapOccurred: false,
                reconciliationPolicy: policy()
            )
        }
    }

    @Test("empty live checkpoint cannot masquerade as a zero-distance aggregate")
    func emptyLiveEvidenceRejected() throws {
        #expect(throws: RideHistoryDistanceAttachmentError.invalidLiveDistanceEvidence) {
            _ = try RideHistoryLiveDistanceCheckpoint(
                source: .scooterBluetooth,
                method: .trapezoidalBetweenMeasurements,
                segmentRecords: []
            )
        }
    }

    @Test("orphaned checkpoint without base history fails closed")
    func orphanedAttachmentRejected() async throws {
        let history = RideHistoryRecord(evidence: try completedRide())
        let distanceStore = InMemoryDistanceStore()
        _ = try await distanceStore.commit(attachment(history: history).checkpoint)
        let coordinator = RideHistoryDistanceCommitCoordinator(
            historyStore: InMemoryHistoryStore(),
            distanceStore: distanceStore
        )

        await #expect(
            throws: RideHistoryDistanceAttachmentError.missingCompletedRide(sessionID)
        ) {
            _ = try await coordinator.joinedRecord(sessionID: sessionID)
        }
    }

    @Test("base history without a distance checkpoint remains ordinary unavailability")
    func missingAttachmentIsUnavailable() async throws {
        let history = RideHistoryRecord(evidence: try completedRide())
        let coordinator = RideHistoryDistanceCommitCoordinator(
            historyStore: InMemoryHistoryStore(records: [history]),
            distanceStore: InMemoryDistanceStore()
        )

        #expect(try await coordinator.joinedRecord(sessionID: sessionID) == nil)
    }

    @Test("commit requires exact durable checkpoint read-back")
    func missingReadBackFails() async throws {
        let history = RideHistoryRecord(evidence: try completedRide())
        let coordinator = RideHistoryDistanceCommitCoordinator(
            historyStore: InMemoryHistoryStore(records: [history]),
            distanceStore: InMemoryDistanceStore(suppressReads: true)
        )

        await #expect(
            throws: RideHistoryDistanceAttachmentError.durableVerificationFailed(sessionID)
        ) {
            _ = try await coordinator.commit(attachment(history: history))
        }
    }

    @Test("distance checkpoint store is immutable per session")
    func conflictingCheckpointCannotReplaceExistingSession() async throws {
        let history = RideHistoryRecord(evidence: try completedRide())
        let distanceStore = InMemoryDistanceStore()
        let first = try attachment(history: history, gpsCoverage: .complete)
        let conflicting = try attachment(history: history, gpsCoverage: .partial)

        #expect(try await distanceStore.commit(first.checkpoint) == .inserted)
        await #expect(
            throws: RideHistoryDistanceStoreError.sessionConflict(sessionID)
        ) {
            _ = try await distanceStore.commit(conflicting.checkpoint)
        }
        #expect(try await distanceStore.checkpoint(sessionID: sessionID) == first.checkpoint)
    }

    @Test("decoded invalid reconciliation policy fails at checkpoint boundary")
    func invalidPolicyDecodeRejected() throws {
        let json = """
        {
          "sourcePriority": ["gpsRoute", "gpsRoute", "liveSpeedIntegration"],
          "absoluteAgreementToleranceMeters": 10,
          "relativeAgreementTolerance": 0.02,
          "minimumRelativeComparisonDistanceMeters": 100,
          "allowOdometerToRecoverKnownCoverageGaps": false
        }
        """

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                RideHistoryDistancePolicySnapshot.self,
                from: Data(json.utf8)
            )
        }
    }

    @Test("unsupported checkpoint schema fails before any trusted record can exist")
    func unsupportedSchemaRejected() throws {
        let history = RideHistoryRecord(evidence: try completedRide())
        let checkpoint = try attachment(history: history).checkpoint
        let data = try JSONEncoder().encode(checkpoint)
        var object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object["schemaVersion"] = 2
        let unsupported = try JSONSerialization.data(withJSONObject: object)

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                RideHistoryDistanceCheckpoint.self,
                from: unsupported
            )
        }
    }
}
