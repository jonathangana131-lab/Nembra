import Foundation
import Testing
@testable import NembraCore

@Suite("Ride-history peak-power checkpoint attachment")
struct RideHistoryPeakPowerCheckpointAttachmentTests {
    private let sessionID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let otherSessionID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let epoch = Date(timeIntervalSinceReferenceDate: 10_000)

    private actor InMemoryHistoryStore: RideHistoryStore {
        private var records: [UUID: RideHistoryRecord]
        init(records: [RideHistoryRecord] = []) {
            self.records = Dictionary(uniqueKeysWithValues: records.map { ($0.sessionID, $0) })
        }
        func commit(_ record: RideHistoryRecord) async throws -> RideHistoryCommitResult {
            if let existing = records[record.sessionID] {
                guard existing == record else { throw RideHistoryStoreError.sessionConflict(record.sessionID) }
                return .alreadyPresent
            }
            records[record.sessionID] = record
            return .inserted
        }
        func record(sessionID: UUID) async throws -> RideHistoryRecord? { records[sessionID] }
    }

    private actor InMemoryPeakStore: RideHistoryPeakPowerCheckpointStore {
        private var records: [RideHistoryPeakPowerCheckpointRecordID: RideHistoryPeakPowerCheckpointRecord] = [:]
        private let suppressExactRead: Bool
        private let foreignListRecord: RideHistoryPeakPowerCheckpointRecord?
        private let duplicateListRecord: RideHistoryPeakPowerCheckpointRecord?

        init(
            suppressExactRead: Bool = false,
            foreignListRecord: RideHistoryPeakPowerCheckpointRecord? = nil,
            duplicateListRecord: RideHistoryPeakPowerCheckpointRecord? = nil
        ) {
            self.suppressExactRead = suppressExactRead
            self.foreignListRecord = foreignListRecord
            self.duplicateListRecord = duplicateListRecord
        }

        func commit(
            _ record: RideHistoryPeakPowerCheckpointRecord
        ) async throws -> RideHistoryPeakPowerCheckpointCommitResult {
            if let existing = records[record.recordID] {
                guard existing == record else {
                    throw RideHistoryPeakPowerCheckpointStoreError.recordConflict(record.recordID)
                }
                return .alreadyPresent
            }
            records[record.recordID] = record
            return .inserted
        }

        func record(
            id: RideHistoryPeakPowerCheckpointRecordID
        ) async throws -> RideHistoryPeakPowerCheckpointRecord? {
            guard !suppressExactRead else { return nil }
            return records[id]
        }

        func records(
            sessionID: UUID
        ) async throws -> [RideHistoryPeakPowerCheckpointRecord] {
            var result = records.values.filter { $0.sessionID == sessionID }
            if let foreignListRecord { result.append(foreignListRecord) }
            if let duplicateListRecord { result.append(duplicateListRecord) }
            return result
        }
    }

    private func completedRide(
        sessionID: UUID? = nil,
        continuity: RideSessionContinuity = .uninterruptedProcess
    ) throws -> CompletedRideEvidence {
        try CompletedRideEvidence(
            sessionID: sessionID ?? self.sessionID,
            beganAtDate: epoch,
            confirmedAtDate: epoch.addingTimeInterval(5),
            endedAtDate: epoch.addingTimeInterval(120),
            startingOdometerKilometers: nil,
            endingOdometerKilometers: nil,
            qualityScreenedGPSDistanceMeters: 0,
            continuity: continuity
        )
    }

    private func simulatorScope(
        vehicle: String = "sim-es80",
        mode: String? = "drive"
    ) throws -> ObservedPowerEnvelopeScope {
        try .simulatorQA(vehicleIdentityKey: vehicle, confirmedModeKey: mode)
    }

    private func physicalScope(
        vehicle: String = "physical-es80-opaque-id",
        mode: String? = "drive"
    ) throws -> ObservedPowerEnvelopeScope {
        try .verifiedVehicleIdentity(vehicleIdentityKey: vehicle, confirmedModeKey: mode)
    }

    private func completedPeak(
        completedRide: CompletedRideEvidence? = nil,
        scope: ObservedPowerEnvelopeScope? = nil,
        watts: Double = 500,
        beginsAfterGap: Bool = false
    ) throws -> CompletedRidePeakPowerEvidence {
        let ride = try completedRide ?? self.completedRide()
        let selectedScope = try scope ?? simulatorScope()
        var accumulator = try RidePeakPowerEvidenceAccumulator(
            sessionID: ride.sessionID,
            scope: selectedScope,
            beginsAfterKnownObservationGap: beginsAfterGap
        )
        switch selectedScope.identityAuthority {
        case .simulatorQA:
            _ = accumulator.record(.simulatorQA(
                scope: selectedScope,
                powerWatts: watts,
                receiptSequenceNumber: 1,
                observedAtUptimeNanoseconds: 100,
                learningEligibility: .measurementOnly
            ))
        case .verifiedVehicleIdentity:
            _ = accumulator.record(.verifiedVehicleMeasurement(
                scope: selectedScope,
                powerWatts: watts,
                receiptSequenceNumber: 1,
                observedAtUptimeNanoseconds: 100,
                learningEligibility: .measurementOnly
            ))
        }
        return try CompletedRidePeakPowerEvidence(
            completedRide: ride,
            ridePeak: #require(accumulator.evidence)
        )
    }

    private func checkpoint(
        from evidence: CompletedRidePeakPowerEvidence
    ) throws -> CompletedRidePeakPowerCheckpoint {
        switch (evidence.identityAuthority, evidence.evidenceAuthority) {
        case (.simulatorQA, .simulatorQA):
            return try .simulatorQA(from: evidence)
        case (.verifiedVehicleIdentity, .verifiedVehicleMeasurement):
            return try .verifiedVehicleMeasurements(from: evidence)
        default:
            throw CompletedRidePeakPowerEvidenceError.authorityMismatch
        }
    }

    private func record(
        evidence: CompletedRidePeakPowerEvidence
    ) throws -> RideHistoryPeakPowerCheckpointRecord {
        RideHistoryPeakPowerCheckpointRecord(checkpoint: try checkpoint(from: evidence))
    }

    @Test("record identity includes mode so one ride retains multiple scoped peaks")
    func exactModeIdentityPreventsOverwrite() throws {
        let ride = try completedRide()
        let drive = try record(evidence: completedPeak(
            completedRide: ride,
            scope: simulatorScope(mode: "drive"),
            watts: 400
        ))
        let sport = try record(evidence: completedPeak(
            completedRide: ride,
            scope: simulatorScope(mode: "sport"),
            watts: 600
        ))
        #expect(drive.recordID != sport.recordID)
        #expect(drive.sessionID == sport.sessionID)
        #expect(drive.recordID.confirmedModeKey == "drive")
        #expect(sport.recordID.confirmedModeKey == "sport")
    }

    @Test("unknown mode remains a distinct scope")
    func unknownModeDistinct() throws {
        let ride = try completedRide()
        let unknown = try record(evidence: completedPeak(
            completedRide: ride,
            scope: simulatorScope(mode: nil)
        ))
        let drive = try record(evidence: completedPeak(
            completedRide: ride,
            scope: simulatorScope(mode: "drive")
        ))
        #expect(unknown.recordID != drive.recordID)
    }

    @Test("simulator and verified authority domains cannot overwrite each other")
    func authorityDomainsDistinct() throws {
        let ride = try completedRide()
        let sim = try record(evidence: completedPeak(
            completedRide: ride,
            scope: simulatorScope(vehicle: "same-opaque")
        ))
        let physical = try record(evidence: completedPeak(
            completedRide: ride,
            scope: physicalScope(vehicle: "same-opaque")
        ))
        #expect(sim.recordID != physical.recordID)
    }

    @Test("commit stores inert checkpoints idempotently only after base ride exists")
    func commitAndJoinMultipleScopes() async throws {
        let ride = try completedRide()
        let drive = try completedPeak(
            completedRide: ride,
            scope: simulatorScope(mode: "drive"),
            watts: 400
        )
        let sport = try completedPeak(
            completedRide: ride,
            scope: simulatorScope(mode: "sport"),
            watts: 600
        )
        let store = InMemoryPeakStore()
        let coordinator = RideHistoryPeakPowerCheckpointCommitCoordinator(
            historyStore: InMemoryHistoryStore(records: [RideHistoryRecord(evidence: ride)]),
            peakPowerStore: store
        )
        #expect(try await coordinator.commit(drive) == .inserted)
        #expect(try await coordinator.commit(drive) == .alreadyPresent)
        #expect(try await coordinator.commit(sport) == .inserted)

        let joined = try await coordinator.joinedCheckpoints(sessionID: sessionID)
        #expect(joined.count == 2)
        #expect(Set(joined.map(\.recordID)).count == 2)
        #expect(Set(joined.map { $0.peakPowerRecord.checkpoint.powerWatts }) == Set([400, 600]))
    }

    @Test("verified commit persists a checkpoint but join does not restore trusted evidence")
    func verifiedCommitRemainsCheckpointOnly() async throws {
        let ride = try completedRide()
        let physical = try completedPeak(
            completedRide: ride,
            scope: physicalScope(mode: "sport"),
            watts: 575
        )
        let coordinator = RideHistoryPeakPowerCheckpointCommitCoordinator(
            historyStore: InMemoryHistoryStore(records: [RideHistoryRecord(evidence: ride)]),
            peakPowerStore: InMemoryPeakStore()
        )
        _ = try await coordinator.commit(physical)
        let joined = try #require(try await coordinator.joinedCheckpoints(sessionID: sessionID).first)
        #expect(joined.peakPowerRecord.checkpoint.identityAuthority == .verifiedVehicleIdentity)
        #expect(joined.peakPowerRecord.checkpoint.evidenceAuthority == .verifiedVehicleMeasurement)
        #expect(joined.peakPowerRecord.checkpoint.powerWatts == 575)
    }

    @Test("missing base ride fails closed on commit")
    func missingBaseRideRejected() async throws {
        let peak = try completedPeak()
        let coordinator = RideHistoryPeakPowerCheckpointCommitCoordinator(
            historyStore: InMemoryHistoryStore(),
            peakPowerStore: InMemoryPeakStore()
        )
        await #expect(throws: RideHistoryPeakPowerCheckpointCommitCoordinatorError.missingCompletedRide(sessionID)) {
            _ = try await coordinator.commit(peak)
        }
    }

    @Test("same session with conflicting ride continuity cannot attach")
    func continuityMismatchRejected() async throws {
        let uninterrupted = try completedRide(continuity: .uninterruptedProcess)
        let recovered = try completedRide(continuity: .recoveredCheckpoint)
        let peak = try completedPeak(completedRide: recovered, beginsAfterGap: true)
        let id = try record(evidence: peak).recordID
        let coordinator = RideHistoryPeakPowerCheckpointCommitCoordinator(
            historyStore: InMemoryHistoryStore(records: [RideHistoryRecord(evidence: uninterrupted)]),
            peakPowerStore: InMemoryPeakStore()
        )
        await #expect(throws: RideHistoryPeakPowerCheckpointCommitCoordinatorError.completedRideMismatch(id)) {
            _ = try await coordinator.commit(peak)
        }
    }

    @Test("same exact scope cannot silently replace immutable checkpoint")
    func conflictingReplacementRejected() async throws {
        let ride = try completedRide()
        let scope = try simulatorScope(mode: "drive")
        let first = try completedPeak(completedRide: ride, scope: scope, watts: 400)
        let changed = try completedPeak(completedRide: ride, scope: scope, watts: 500)
        let id = try record(evidence: first).recordID
        let coordinator = RideHistoryPeakPowerCheckpointCommitCoordinator(
            historyStore: InMemoryHistoryStore(records: [RideHistoryRecord(evidence: ride)]),
            peakPowerStore: InMemoryPeakStore()
        )
        _ = try await coordinator.commit(first)
        await #expect(throws: RideHistoryPeakPowerCheckpointStoreError.recordConflict(id)) {
            _ = try await coordinator.commit(changed)
        }
    }

    @Test("commit requires exact durable read-back")
    func exactReadbackRequired() async throws {
        let ride = try completedRide()
        let peak = try completedPeak(completedRide: ride)
        let id = try record(evidence: peak).recordID
        let coordinator = RideHistoryPeakPowerCheckpointCommitCoordinator(
            historyStore: InMemoryHistoryStore(records: [RideHistoryRecord(evidence: ride)]),
            peakPowerStore: InMemoryPeakStore(suppressExactRead: true)
        )
        await #expect(throws: RideHistoryPeakPowerCheckpointCommitCoordinatorError.durableVerificationFailed(id)) {
            _ = try await coordinator.commit(peak)
        }
    }

    @Test("no base history and no attachments is ordinary absence")
    func totalAbsenceIsEmpty() async throws {
        let coordinator = RideHistoryPeakPowerCheckpointCommitCoordinator(
            historyStore: InMemoryHistoryStore(),
            peakPowerStore: InMemoryPeakStore()
        )
        #expect(try await coordinator.joinedCheckpoints(sessionID: sessionID).isEmpty)
    }

    @Test("orphaned checkpoint without base ride fails closed")
    func orphanedCheckpointRejected() async throws {
        let record = try record(evidence: completedPeak())
        let store = InMemoryPeakStore()
        _ = try await store.commit(record)
        let coordinator = RideHistoryPeakPowerCheckpointCommitCoordinator(
            historyStore: InMemoryHistoryStore(),
            peakPowerStore: store
        )
        await #expect(throws: RideHistoryPeakPowerCheckpointCommitCoordinatorError.missingCompletedRide(sessionID)) {
            _ = try await coordinator.joinedCheckpoints(sessionID: sessionID)
        }
    }

    @Test("store returning a foreign session fails closed")
    func foreignSessionRejected() async throws {
        let ride = try completedRide()
        let foreignRide = try completedRide(sessionID: otherSessionID)
        let foreign = try record(evidence: completedPeak(completedRide: foreignRide))
        let coordinator = RideHistoryPeakPowerCheckpointCommitCoordinator(
            historyStore: InMemoryHistoryStore(records: [RideHistoryRecord(evidence: ride)]),
            peakPowerStore: InMemoryPeakStore(foreignListRecord: foreign)
        )
        await #expect(throws: RideHistoryPeakPowerCheckpointCommitCoordinatorError.storeReturnedForeignSession(
            expected: sessionID,
            actual: foreign.recordID
        )) {
            _ = try await coordinator.joinedCheckpoints(sessionID: sessionID)
        }
    }

    @Test("duplicate exact identity returned by store fails closed")
    func duplicateIdentityRejected() async throws {
        let ride = try completedRide()
        let record = try record(evidence: completedPeak(completedRide: ride))
        let store = InMemoryPeakStore(duplicateListRecord: record)
        _ = try await store.commit(record)
        let coordinator = RideHistoryPeakPowerCheckpointCommitCoordinator(
            historyStore: InMemoryHistoryStore(records: [RideHistoryRecord(evidence: ride)]),
            peakPowerStore: store
        )
        await #expect(throws: RideHistoryPeakPowerCheckpointCommitCoordinatorError.duplicateRecordIdentity(record.recordID)) {
            _ = try await coordinator.joinedCheckpoints(sessionID: sessionID)
        }
    }

    @Test("record ID decoder rejects forged authority pair")
    func forgedRecordIDRejected() throws {
        let original = try record(evidence: completedPeak()).recordID
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any]
        )
        object["evidenceAuthority"] = ObservedPowerEnvelopeEvidenceAuthority.verifiedVehicleMeasurement.rawValue
        let forged = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(RideHistoryPeakPowerCheckpointRecordID.self, from: forged)
        }
    }

    @Test("record JSON round-trip remains an inert checkpoint")
    func recordRoundTrip() throws {
        let original = try record(evidence: completedPeak(
            scope: physicalScope(mode: "sport"),
            watts: 575
        ))
        let decoded = try JSONDecoder().decode(
            RideHistoryPeakPowerCheckpointRecord.self,
            from: JSONEncoder().encode(original)
        )
        #expect(decoded == original)
        #expect(decoded.recordID == original.recordID)
        #expect(decoded.checkpoint.identityAuthority == .verifiedVehicleIdentity)
    }
}
