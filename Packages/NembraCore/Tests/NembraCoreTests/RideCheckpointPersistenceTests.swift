import Foundation
import Testing
@testable import NembraCore

@Suite("Crash-recovery ride checkpoints")
struct RideCheckpointPersistenceTests {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nembra-ride-checkpoint-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func checkpoint(
        id: UUID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
        phase: RideCheckpointPhase = .active,
        phaseBeganAtDate: Date? = nil,
        lastObservedOffset: TimeInterval = 30,
        checkpointedOffset: TimeInterval = 31,
        startODO: Double? = 100,
        latestODO: Double? = 100.5,
        gpsMeters: Double = 800
    ) throws -> RideRecoveryCheckpoint {
        let phaseDate: Date?
        switch phase {
        case .active:
            phaseDate = phaseBeganAtDate
        case .temporarilyDisconnected, .endingCandidate:
            phaseDate = phaseBeganAtDate ?? epoch.addingTimeInterval(25)
        }

        return try RideRecoveryCheckpoint(
            sessionID: id,
            beganAtDate: epoch,
            confirmedAtDate: epoch.addingTimeInterval(2),
            persistedPhase: phase,
            phaseBeganAtDate: phaseDate,
            lastObservedAtDate: epoch.addingTimeInterval(lastObservedOffset),
            checkpointedAtDate: epoch.addingTimeInterval(checkpointedOffset),
            startingOdometerKilometers: startODO,
            latestOdometerKilometers: latestODO,
            accumulatedGPSDistanceMeters: gpsMeters
        )
    }

    private func policy() throws -> RideDetectionPolicy {
        try RideDetectionPolicy(
            candidateSpeedKilometersPerHour: 1,
            confirmationSpeedKilometersPerHour: 4,
            confirmationDurationNanoseconds: 2_000,
            confirmationOdometerDeltaKilometers: 0.05,
            confirmationGPSDistanceMeters: 8,
            endingDurationNanoseconds: 5_000,
            maximumSpeedSampleAgeNanoseconds: 1_000
        )
    }

    private func speed(_ kph: Double, at t: UInt64) throws -> SpeedTelemetrySample {
        try SpeedTelemetrySample(
            source: .scooterBluetooth,
            provenance: .absoluteMeasurement,
            metersPerSecond: kph / 3.6,
            receivedAtUptimeNanoseconds: t,
            receivedAtDate: epoch.addingTimeInterval(Double(t) / 1_000_000_000)
        )
    }

    private func observation(
        _ t: UInt64,
        connection: VehicleConnectionState = .connected,
        speedKPH: Double? = nil,
        odometer: Double? = nil,
        gpsDelta: Double? = nil
    ) throws -> RideObservation {
        try RideObservation(
            receivedAtUptimeNanoseconds: t,
            receivedAtDate: epoch.addingTimeInterval(Double(t) / 1_000_000_000),
            connection: connection,
            speedSample: try speedKPH.map { try speed($0, at: t) },
            odometerKilometers: odometer,
            qualityScreenedGPSDistanceDeltaMeters: gpsDelta
        )
    }

    @Test("two-slot journal round-trips and selects the newest generation")
    func roundTripNewestGeneration() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = AtomicRideCheckpointStore(directoryURL: dir)
        let first = try checkpoint(latestODO: 100.2, gpsMeters: 200)
        let second = try checkpoint(latestODO: 100.8, gpsMeters: 900)

        try await store.save(.inProgress(first))
        try await store.save(.inProgress(second))

        #expect(try await store.load() == .inProgress(second))
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent(AtomicRideCheckpointStore.slotAFileName).path))
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent(AtomicRideCheckpointStore.slotBFileName).path))
    }

    @Test("a corrupt newest slot falls back to the older known-good checkpoint")
    func corruptNewestFallsBack() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = AtomicRideCheckpointStore(directoryURL: dir)
        let older = try checkpoint(latestODO: 100.2)
        let newer = try checkpoint(latestODO: 100.9)
        try await store.save(.inProgress(older))
        try await store.save(.inProgress(newer))

        let slotB = dir.appendingPathComponent(AtomicRideCheckpointStore.slotBFileName)
        try Data("truncated".utf8).write(to: slotB)

        #expect(try await store.load() == .inProgress(older))
    }

    @Test("one corrupt slot plus one unused slot recovers without erasing forensic evidence")
    func corruptPlusMissingRecoversIntoUnusedSlot() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let slotA = dir.appendingPathComponent(AtomicRideCheckpointStore.slotAFileName)
        let slotB = dir.appendingPathComponent(AtomicRideCheckpointStore.slotBFileName)
        let forensic = Data("broken-old-checkpoint".utf8)
        try forensic.write(to: slotA)

        let store = AtomicRideCheckpointStore(directoryURL: dir)
        let recovered = try checkpoint(latestODO: 101.1)
        try await store.save(.inProgress(recovered))

        #expect(try Data(contentsOf: slotA) == forensic)
        #expect(FileManager.default.fileExists(atPath: slotB.path))
        #expect(try await store.load() == .inProgress(recovered))
    }

    @Test("two corrupt slots require explicit recovery instead of silent overwrite")
    func bothCorruptRequireExplicitRecovery() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("bad-a".utf8).write(to: dir.appendingPathComponent(AtomicRideCheckpointStore.slotAFileName))
        try Data("bad-b".utf8).write(to: dir.appendingPathComponent(AtomicRideCheckpointStore.slotBFileName))
        let store = AtomicRideCheckpointStore(directoryURL: dir)

        await #expect(throws: RideCheckpointError.corruptedCheckpoint) {
            _ = try await store.load()
        }
        await #expect(throws: RideCheckpointError.corruptedCheckpoint) {
            try await store.save(.inProgress(try checkpoint()))
        }
    }

    @Test("unsupported checkpoint schema is never silently overwritten")
    func unsupportedSchemaIsPreserved() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let slotA = dir.appendingPathComponent(AtomicRideCheckpointStore.slotAFileName)
        try Data("{\"schemaVersion\":999}".utf8).write(to: slotA)
        let store = AtomicRideCheckpointStore(directoryURL: dir)

        await #expect(throws: RideCheckpointError.unsupportedSchema(999)) {
            _ = try await store.load()
        }
        await #expect(throws: RideCheckpointError.unsupportedSchema(999)) {
            try await store.save(.inProgress(try checkpoint()))
        }
    }

    @Test("same generation with divergent valid payloads is treated as journal conflict")
    func sameGenerationConflictIsRejected() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cpA = try checkpoint(latestODO: 100.1)
        let cpB = try checkpoint(latestODO: 100.9)
        let envelopeA = AtomicRideCheckpointStore.Envelope(
            schemaVersion: AtomicRideCheckpointStore.schemaVersion,
            generation: 7,
            checkpoint: .inProgress(cpA)
        )
        let envelopeB = AtomicRideCheckpointStore.Envelope(
            schemaVersion: AtomicRideCheckpointStore.schemaVersion,
            generation: 7,
            checkpoint: .inProgress(cpB)
        )
        let encoder = JSONEncoder()
        try encoder.encode(envelopeA).write(
            to: dir.appendingPathComponent(AtomicRideCheckpointStore.slotAFileName)
        )
        try encoder.encode(envelopeB).write(
            to: dir.appendingPathComponent(AtomicRideCheckpointStore.slotBFileName)
        )
        let store = AtomicRideCheckpointStore(directoryURL: dir)

        await #expect(throws: RideCheckpointError.conflictingGenerations) {
            _ = try await store.load()
        }
        await #expect(throws: RideCheckpointError.conflictingGenerations) {
            try await store.save(.inProgress(try checkpoint()))
        }
    }

    @Test("generation overflow fails without overwriting the existing checkpoint")
    func generationOverflowIsRejected() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let original = try checkpoint(latestODO: 100.1)
        let envelope = AtomicRideCheckpointStore.Envelope(
            schemaVersion: AtomicRideCheckpointStore.schemaVersion,
            generation: UInt64.max,
            checkpoint: .inProgress(original)
        )
        let slotA = dir.appendingPathComponent(AtomicRideCheckpointStore.slotAFileName)
        try JSONEncoder().encode(envelope).write(to: slotA)
        let originalData = try Data(contentsOf: slotA)
        let store = AtomicRideCheckpointStore(directoryURL: dir)

        await #expect(throws: RideCheckpointError.generationOverflow) {
            try await store.save(.inProgress(try checkpoint(latestODO: 200)))
        }
        #expect(try Data(contentsOf: slotA) == originalData)
    }

    @Test("logically invalid completed evidence is rejected when loading the journal")
    func invalidCompletedEvidenceDecodeIsCorrupt() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let evidence = try CompletedRideEvidence(
            sessionID: UUID(),
            beganAtDate: epoch,
            confirmedAtDate: epoch,
            endedAtDate: epoch,
            startingOdometerKilometers: 100,
            endingOdometerKilometers: 101,
            qualityScreenedGPSDistanceMeters: 50,
            continuity: .uninterruptedProcess
        )
        let envelope = AtomicRideCheckpointStore.Envelope(
            schemaVersion: AtomicRideCheckpointStore.schemaVersion,
            generation: 1,
            checkpoint: .completedPendingCommit(evidence)
        )
        let encoder = JSONEncoder()
        var object = try #require(
            JSONSerialization.jsonObject(with: encoder.encode(envelope)) as? [String: Any]
        )
        var checkpointObject = try #require(object["checkpoint"] as? [String: Any])
        var completed = try #require(checkpointObject["completedPendingCommit"] as? [String: Any])
        completed["endingOdometerKilometers"] = 99.0
        checkpointObject["completedPendingCommit"] = completed
        object["checkpoint"] = checkpointObject

        let slotA = dir.appendingPathComponent(AtomicRideCheckpointStore.slotAFileName)
        try JSONSerialization.data(withJSONObject: object).write(to: slotA)
        let store = AtomicRideCheckpointStore(directoryURL: dir)

        await #expect(throws: RideCheckpointError.corruptedCheckpoint) {
            _ = try await store.load()
        }
    }

    @Test("clear removes both journal slots")
    func clearRemovesSlots() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = AtomicRideCheckpointStore(directoryURL: dir)
        try await store.save(.inProgress(try checkpoint()))
        try await store.save(.inProgress(try checkpoint(latestODO: 101)))

        try await store.clear()
        #expect(try await store.load() == nil)
    }

    @Test("checkpoint invariants reject impossible phase and odometer shapes")
    func invalidCheckpointShapesAreRejected() throws {
        #expect(throws: RideCheckpointError.invalidCheckpoint) {
            _ = try checkpoint(phase: .active, phaseBeganAtDate: epoch)
        }
        #expect(throws: RideCheckpointError.invalidCheckpoint) {
            _ = try RideRecoveryCheckpoint(
                sessionID: UUID(),
                beganAtDate: epoch,
                confirmedAtDate: epoch.addingTimeInterval(1),
                persistedPhase: .endingCandidate,
                phaseBeganAtDate: nil,
                lastObservedAtDate: epoch.addingTimeInterval(2),
                checkpointedAtDate: epoch.addingTimeInterval(3),
                startingOdometerKilometers: 100,
                latestOdometerKilometers: 100,
                accumulatedGPSDistanceMeters: 0
            )
        }
        #expect(throws: RideCheckpointError.invalidCheckpoint) {
            _ = try checkpoint(startODO: nil, latestODO: 100)
        }
        #expect(throws: RideCheckpointError.invalidCheckpoint) {
            _ = try checkpoint(startODO: 101, latestODO: 100)
        }
        #expect(throws: RideCheckpointError.invalidCheckpoint) {
            _ = try checkpoint(gpsMeters: .infinity)
        }
    }

    @Test("completed ride evidence rejects impossible durable numeric shapes")
    func invalidCompletedEvidenceIsRejected() throws {
        #expect(throws: CompletedRideEvidenceError.invalidEvidence) {
            _ = try CompletedRideEvidence(
                sessionID: UUID(),
                beganAtDate: epoch,
                confirmedAtDate: epoch,
                endedAtDate: epoch,
                startingOdometerKilometers: nil,
                endingOdometerKilometers: 100,
                qualityScreenedGPSDistanceMeters: 1,
                continuity: .uninterruptedProcess
            )
        }
        #expect(throws: CompletedRideEvidenceError.invalidEvidence) {
            _ = try CompletedRideEvidence(
                sessionID: UUID(),
                beganAtDate: epoch,
                confirmedAtDate: epoch,
                endedAtDate: epoch,
                startingOdometerKilometers: 101,
                endingOdometerKilometers: 100,
                qualityScreenedGPSDistanceMeters: 1,
                continuity: .uninterruptedProcess
            )
        }
        #expect(throws: CompletedRideEvidenceError.invalidEvidence) {
            _ = try CompletedRideEvidence(
                sessionID: UUID(),
                beganAtDate: epoch,
                confirmedAtDate: epoch,
                endedAtDate: epoch,
                startingOdometerKilometers: nil,
                endingOdometerKilometers: nil,
                qualityScreenedGPSDistanceMeters: .infinity,
                continuity: .uninterruptedProcess
            )
        }
    }

    @Test("engine checkpoints only confirmed ride phases with honest phase metadata")
    func engineCheckpointPhaseMapping() throws {
        let sessionID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        var engine = RideEngine(policy: try policy(), makeSessionID: { sessionID })
        #expect(try engine.recoveryCheckpoint(checkpointedAtDate: epoch) == nil)

        _ = try engine.ingest(observation(1_000, speedKPH: 2))
        #expect(try engine.recoveryCheckpoint(checkpointedAtDate: epoch) == nil)
        _ = try engine.ingest(observation(3_000, speedKPH: 6, odometer: 100, gpsDelta: 2))

        let activeOptional = try engine.recoveryCheckpoint(checkpointedAtDate: epoch.addingTimeInterval(10))
        let active = try #require(activeOptional)
        #expect(active.sessionID == sessionID)
        #expect(active.persistedPhase == .active)
        #expect(active.phaseBeganAtDate == nil)
        #expect(active.latestOdometerKilometers == 100)
        #expect(active.accumulatedGPSDistanceMeters == 2)

        _ = try engine.ingest(observation(4_000, connection: .disconnected, odometer: 100.1))
        let disconnectedOptional = try engine.recoveryCheckpoint(checkpointedAtDate: epoch.addingTimeInterval(11))
        let disconnected = try #require(disconnectedOptional)
        #expect(disconnected.persistedPhase == .temporarilyDisconnected)
        #expect(disconnected.phaseBeganAtDate == epoch.addingTimeInterval(Double(4_000) / 1_000_000_000))

        _ = try engine.ingest(observation(5_000, speedKPH: 0, odometer: 100.1))
        let endingOptional = try engine.recoveryCheckpoint(checkpointedAtDate: epoch.addingTimeInterval(12))
        let ending = try #require(endingOptional)
        #expect(ending.persistedPhase == .endingCandidate)
        #expect(ending.phaseBeganAtDate == epoch.addingTimeInterval(Double(5_000) / 1_000_000_000))
    }

    @Test("checkpoint recovery keeps durable evidence but never invents historical uptime")
    func recoveryUsesNewMonotonicEpoch() throws {
        let cp = try checkpoint(
            phase: .endingCandidate,
            lastObservedOffset: 30,
            checkpointedOffset: 31,
            latestODO: 103.5,
            gpsMeters: 2_400
        )
        let recoveryDate = epoch.addingTimeInterval(100)
        let engine = try RideEngine.restoring(
            from: cp,
            policy: try policy(),
            recoveredAtUptimeNanoseconds: 50_000,
            recoveredAtDate: recoveryDate
        )

        guard case let .temporarilyDisconnected(recovered) = engine.phase else {
            Issue.record("recovery must reacquire live evidence before declaring active")
            return
        }
        #expect(recovered.session.id == cp.sessionID)
        #expect(recovered.session.beganAtDate == cp.beganAtDate)
        #expect(recovered.session.confirmedAtDate == cp.confirmedAtDate)
        #expect(recovered.session.beganAtUptimeNanoseconds == nil)
        #expect(recovered.session.confirmedAtUptimeNanoseconds == nil)
        #expect(recovered.session.continuity == .recoveredCheckpoint)
        #expect(recovered.session.latestOdometerKilometers == 103.5)
        #expect(recovered.session.accumulatedGPSDistanceMeters == 2_400)
        #expect(recovered.disconnectedAtUptimeNanoseconds == 50_000)
        #expect(recovered.disconnectedAtDate == recoveryDate)

        // Creating another checkpoint before new vehicle data arrives must keep
        // the old last-observed evidence timestamp, not label recovery as a read.
        let recheckpointOptional = try engine.recoveryCheckpoint(
            checkpointedAtDate: recoveryDate.addingTimeInterval(1)
        )
        let recheckpoint = try #require(recheckpointOptional)
        #expect(recheckpoint.lastObservedAtDate == cp.lastObservedAtDate)
        #expect(recheckpoint.persistedPhase == .temporarilyDisconnected)
    }

    @Test("recovered ride resumes only after fresh post-recovery movement")
    func recoveredRideRequiresFreshMovement() throws {
        let cp = try checkpoint(latestODO: 100.5)
        var engine = try RideEngine.restoring(
            from: cp,
            policy: try policy(),
            recoveredAtUptimeNanoseconds: 10_000,
            recoveredAtDate: epoch.addingTimeInterval(100)
        )

        let stationary = try engine.ingest(observation(11_000, speedKPH: 0, odometer: 100.5))
        guard case .endingCandidate = stationary.phase else {
            Issue.record("stationary recovery should begin a new stop window")
            return
        }
        #expect(stationary.events == [.endingCandidateStarted(cp.sessionID)])

        let resumed = try engine.ingest(observation(12_000, odometer: 100.51))
        guard case let .active(session) = resumed.phase else {
            Issue.record("fresh ODO movement should resume the recovered session")
            return
        }
        #expect(session.id == cp.sessionID)
        #expect(session.continuity == .recoveredCheckpoint)
        #expect(resumed.events == [.rideResumed(cp.sessionID)])
    }

    @Test("recovery rejects invalid runtime wall-clock metadata")
    func invalidRecoveryDateIsRejected() throws {
        #expect(throws: RideEngineError.invalidRecovery) {
            _ = try RideEngine.restoring(
                from: try checkpoint(),
                policy: try policy(),
                recoveredAtUptimeNanoseconds: 10,
                recoveredAtDate: Date(timeIntervalSinceReferenceDate: .infinity)
            )
        }
    }
}
