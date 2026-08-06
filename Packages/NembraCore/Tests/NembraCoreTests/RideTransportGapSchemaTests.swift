import Foundation
import Testing
@testable import NembraCore

@Suite("Ride transport-gap checkpoint schema")
struct RideTransportGapSchemaTests {
    private let epoch = Date(timeIntervalSince1970: 1_700_100_000)

    private func checkpoint(
        gapEvidence: RideTransportGapEvidence
    ) throws -> RideRecoveryCheckpoint {
        try RideRecoveryCheckpoint(
            sessionID: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
            beganAtDate: epoch,
            confirmedAtDate: epoch.addingTimeInterval(1),
            persistedPhase: .active,
            phaseBeganAtDate: nil,
            lastObservedAtDate: epoch.addingTimeInterval(2),
            checkpointedAtDate: epoch.addingTimeInterval(3),
            startingOdometerKilometers: 10,
            latestOdometerKilometers: 10.2,
            accumulatedGPSDistanceMeters: 200,
            transportGapEvidence: gapEvidence
        )
    }

    private func completed(
        gapEvidence: RideTransportGapEvidence,
        continuity: RideSessionContinuity = .uninterruptedProcess
    ) throws -> CompletedRideEvidence {
        try CompletedRideEvidence(
            sessionID: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
            beganAtDate: epoch,
            confirmedAtDate: epoch.addingTimeInterval(1),
            endedAtDate: epoch.addingTimeInterval(30),
            startingOdometerKilometers: 10,
            endingOdometerKilometers: 10.5,
            qualityScreenedGPSDistanceMeters: 500,
            continuity: continuity,
            transportGapEvidence: gapEvidence
        )
    }

    private func envelopeData(
        schemaVersion: Int,
        checkpoint: RideDurableCheckpoint,
        generation: UInt64 = 1,
        removingTransportKeyAt path: [String]
    ) throws -> Data {
        let envelope = AtomicRideCheckpointStore.Envelope(
            schemaVersion: schemaVersion,
            generation: generation,
            checkpoint: checkpoint
        )
        let encoded = try JSONEncoder().encode(envelope)
        var root = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        var durable = try #require(root["checkpoint"] as? [String: Any])
        var payload = try #require(durable[path[0]] as? [String: Any])
        payload.removeValue(forKey: "transportGapEvidence")
        durable[path[0]] = payload
        root["checkpoint"] = durable
        return try JSONSerialization.data(withJSONObject: root)
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nembra-gap-schema-hardening-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("recovered completed evidence cannot claim none-observed transport")
    func recoveredCompletionRejectsNoneObserved() throws {
        #expect(throws: CompletedRideEvidenceError.invalidEvidence) {
            _ = try completed(
                gapEvidence: .noneObserved,
                continuity: .recoveredCheckpoint
            )
        }

        let unknown = try completed(
            gapEvidence: .unknown,
            continuity: .recoveredCheckpoint
        )
        #expect(unknown.transportGapEvidence == .unknown)

        let observed = try completed(
            gapEvidence: .observed,
            continuity: .recoveredCheckpoint
        )
        #expect(observed.transportGapEvidence == .observed)
    }

    @Test("current v2 in-progress journal missing provenance is corrupt")
    func currentInProgressMissingFieldIsCorrupt() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let data = try envelopeData(
            schemaVersion: AtomicRideCheckpointStore.schemaVersion,
            checkpoint: .inProgress(try checkpoint(gapEvidence: .observed)),
            removingTransportKeyAt: ["inProgress"]
        )
        try data.write(
            to: dir.appendingPathComponent(AtomicRideCheckpointStore.slotAFileName)
        )

        let store = AtomicRideCheckpointStore(directoryURL: dir)
        await #expect(throws: RideCheckpointError.corruptedCheckpoint) {
            _ = try await store.load()
        }
    }

    @Test("current v2 completion journal missing provenance is corrupt")
    func currentCompletionMissingFieldIsCorrupt() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let data = try envelopeData(
            schemaVersion: AtomicRideCheckpointStore.schemaVersion,
            checkpoint: .completedPendingCommit(try completed(gapEvidence: .observed)),
            removingTransportKeyAt: ["completedPendingCommit"]
        )
        try data.write(
            to: dir.appendingPathComponent(AtomicRideCheckpointStore.slotAFileName)
        )

        let store = AtomicRideCheckpointStore(directoryURL: dir)
        await #expect(throws: RideCheckpointError.corruptedCheckpoint) {
            _ = try await store.load()
        }
    }

    @Test("legacy v1 completion without provenance remains recoverable as unknown")
    func legacyCompletionMissingFieldMigratesUnknown() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let data = try envelopeData(
            schemaVersion: AtomicRideCheckpointStore.legacySchemaVersion,
            checkpoint: .completedPendingCommit(try completed(gapEvidence: .observed)),
            removingTransportKeyAt: ["completedPendingCommit"]
        )
        try data.write(
            to: dir.appendingPathComponent(AtomicRideCheckpointStore.slotAFileName)
        )

        let store = AtomicRideCheckpointStore(directoryURL: dir)
        guard case let .completedPendingCommit(loaded)? = try await store.load() else {
            Issue.record("expected migrated legacy completion handoff")
            return
        }
        #expect(loaded.transportGapEvidence == .unknown)
    }
}
