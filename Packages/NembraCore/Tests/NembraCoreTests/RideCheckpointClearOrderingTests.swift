import Foundation
import Testing
@testable import NembraCore

@Suite("Checkpoint clear monotonicity")
struct RideCheckpointClearOrderingTests {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nembra-checkpoint-clear-order-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func checkpoint(
        id: UUID,
        latestODO: Double,
        gpsMeters: Double
    ) throws -> RideRecoveryCheckpoint {
        try RideRecoveryCheckpoint(
            sessionID: id,
            beganAtDate: epoch,
            confirmedAtDate: epoch.addingTimeInterval(2),
            persistedPhase: .active,
            phaseBeganAtDate: nil,
            lastObservedAtDate: epoch.addingTimeInterval(30),
            checkpointedAtDate: epoch.addingTimeInterval(31),
            startingOdometerKilometers: 100,
            latestOdometerKilometers: latestODO,
            accumulatedGPSDistanceMeters: gpsMeters,
            transportGapEvidence: .noneObserved
        )
    }

    private func completed(
        id: UUID,
        endingODO: Double,
        gpsMeters: Double
    ) throws -> CompletedRideEvidence {
        try CompletedRideEvidence(
            sessionID: id,
            beganAtDate: epoch,
            confirmedAtDate: epoch.addingTimeInterval(2),
            endedAtDate: epoch.addingTimeInterval(60),
            startingOdometerKilometers: 100,
            endingOdometerKilometers: endingODO,
            qualityScreenedGPSDistanceMeters: gpsMeters,
            continuity: .uninterruptedProcess,
            transportGapEvidence: .noneObserved
        )
    }

    private func slotURL(_ fileName: String, in directory: URL) -> URL {
        directory.appendingPathComponent(fileName)
    }

    private func encodedEnvelope(
        generation: UInt64,
        checkpoint: RideDurableCheckpoint
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(
            AtomicRideCheckpointStore.Envelope(
                schemaVersion: AtomicRideCheckpointStore.schemaVersion,
                generation: generation,
                checkpoint: checkpoint
            )
        )
    }

    @Test("interrupted clear keeps newest completion when slot B is authoritative")
    func interruptedClearKeepsNewestSlotBCompletion() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let sessionID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let completion = try completed(id: sessionID, endingODO: 101, gpsMeters: 1_000)
        let fileManager = FailOnNthRemovalFileManager(failOnRemoval: 2)
        let store = AtomicRideCheckpointStore(directoryURL: dir, fileManager: fileManager)

        try await store.save(.inProgress(try checkpoint(id: sessionID, latestODO: 100.4, gpsMeters: 400)))
        try await store.save(.completedPendingCommit(completion))

        await #expect(throws: FailOnNthRemovalFileManager.InjectedFailure.removal(2)) {
            try await store.clear()
        }
        #expect(fileManager.removedFileNames == [AtomicRideCheckpointStore.slotAFileName])

        let fresh = AtomicRideCheckpointStore(directoryURL: dir)
        #expect(try await fresh.load() == .completedPendingCommit(completion))
        try await fresh.clear()
        #expect(try await fresh.load() == nil)
    }

    @Test("interrupted clear keeps newest completion when slot A is authoritative")
    func interruptedClearKeepsNewestSlotACompletion() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let sessionID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let completion = try completed(id: sessionID, endingODO: 101.4, gpsMeters: 1_400)
        let fileManager = FailOnNthRemovalFileManager(failOnRemoval: 2)
        let store = AtomicRideCheckpointStore(directoryURL: dir, fileManager: fileManager)

        try await store.save(.inProgress(try checkpoint(id: sessionID, latestODO: 100.3, gpsMeters: 300)))
        try await store.save(.inProgress(try checkpoint(id: sessionID, latestODO: 100.8, gpsMeters: 800)))
        try await store.save(.completedPendingCommit(completion))

        await #expect(throws: FailOnNthRemovalFileManager.InjectedFailure.removal(2)) {
            try await store.clear()
        }
        #expect(fileManager.removedFileNames == [AtomicRideCheckpointStore.slotBFileName])

        let fresh = AtomicRideCheckpointStore(directoryURL: dir)
        #expect(try await fresh.load() == .completedPendingCommit(completion))
        try await fresh.clear()
        #expect(try await fresh.load() == nil)
    }

    @Test("corrupt newest plus older readable ride fails clear without deleting either file")
    func corruptNewestPreservesOlderReadableRideAndForensicBytes() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let sessionID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let store = AtomicRideCheckpointStore(directoryURL: dir)

        try await store.save(.inProgress(try checkpoint(id: sessionID, latestODO: 100.6, gpsMeters: 600)))
        try await store.save(.completedPendingCommit(
            try completed(id: sessionID, endingODO: 101.2, gpsMeters: 1_200)
        ))

        let slotA = slotURL(AtomicRideCheckpointStore.slotAFileName, in: dir)
        let slotB = slotURL(AtomicRideCheckpointStore.slotBFileName, in: dir)
        let originalA = try Data(contentsOf: slotA)
        let corruptNewest = Data("corrupt-newest-completion".utf8)
        try corruptNewest.write(to: slotB)

        await #expect(throws: RideCheckpointError.corruptedCheckpoint) {
            try await store.clear()
        }
        #expect(try Data(contentsOf: slotA) == originalA)
        #expect(try Data(contentsOf: slotB) == corruptNewest)
    }

    @Test("corrupt plus missing fails clear without deleting forensic bytes")
    func corruptPlusMissingFailsClosed() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let slotA = slotURL(AtomicRideCheckpointStore.slotAFileName, in: dir)
        let bytes = Data("corrupt-only-copy".utf8)
        try bytes.write(to: slotA)
        let store = AtomicRideCheckpointStore(directoryURL: dir)

        await #expect(throws: RideCheckpointError.corruptedCheckpoint) {
            try await store.clear()
        }
        #expect(try Data(contentsOf: slotA) == bytes)
        #expect(!FileManager.default.fileExists(
            atPath: slotURL(AtomicRideCheckpointStore.slotBFileName, in: dir).path
        ))
    }

    @Test("two corrupt slots fail clear without deleting forensic bytes")
    func bothCorruptFailClosed() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let slotA = slotURL(AtomicRideCheckpointStore.slotAFileName, in: dir)
        let slotB = slotURL(AtomicRideCheckpointStore.slotBFileName, in: dir)
        let bytesA = Data("corrupt-a".utf8)
        let bytesB = Data("corrupt-b".utf8)
        try bytesA.write(to: slotA)
        try bytesB.write(to: slotB)
        let store = AtomicRideCheckpointStore(directoryURL: dir)

        await #expect(throws: RideCheckpointError.corruptedCheckpoint) {
            try await store.clear()
        }
        #expect(try Data(contentsOf: slotA) == bytesA)
        #expect(try Data(contentsOf: slotB) == bytesB)
    }

    @Test("unsupported schema plus valid slot fails clear before deleting either file")
    func unsupportedSchemaFailsBeforeDeletion() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let sessionID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let store = AtomicRideCheckpointStore(directoryURL: dir)
        try await store.save(.inProgress(try checkpoint(id: sessionID, latestODO: 100.2, gpsMeters: 200)))

        let slotA = slotURL(AtomicRideCheckpointStore.slotAFileName, in: dir)
        let slotB = slotURL(AtomicRideCheckpointStore.slotBFileName, in: dir)
        let originalA = try Data(contentsOf: slotA)
        let unsupported = Data("{\"schemaVersion\":999}".utf8)
        try unsupported.write(to: slotB)

        await #expect(throws: RideCheckpointError.unsupportedSchema(999)) {
            try await store.clear()
        }
        #expect(try Data(contentsOf: slotA) == originalA)
        #expect(try Data(contentsOf: slotB) == unsupported)
    }

    @Test("divergent valid evidence at the same generation fails clear before deletion")
    func conflictingSameGenerationFailsBeforeDeletion() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let sessionID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let slotA = slotURL(AtomicRideCheckpointStore.slotAFileName, in: dir)
        let slotB = slotURL(AtomicRideCheckpointStore.slotBFileName, in: dir)
        let bytesA = try encodedEnvelope(
            generation: 7,
            checkpoint: .inProgress(try checkpoint(id: sessionID, latestODO: 100.4, gpsMeters: 400))
        )
        let bytesB = try encodedEnvelope(
            generation: 7,
            checkpoint: .completedPendingCommit(
                try completed(id: sessionID, endingODO: 101, gpsMeters: 1_000)
            )
        )
        try bytesA.write(to: slotA)
        try bytesB.write(to: slotB)
        let store = AtomicRideCheckpointStore(directoryURL: dir)

        await #expect(throws: RideCheckpointError.conflictingGenerations) {
            try await store.clear()
        }
        #expect(try Data(contentsOf: slotA) == bytesA)
        #expect(try Data(contentsOf: slotB) == bytesB)
    }

    @Test("one valid slot clears and both missing is an idempotent no-op")
    func oneValidAndBothMissingClearSuccessfully() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let sessionID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        let store = AtomicRideCheckpointStore(directoryURL: dir)

        try await store.clear()
        #expect(try await store.load() == nil)

        try await store.save(.inProgress(try checkpoint(id: sessionID, latestODO: 100.7, gpsMeters: 700)))
        try await store.clear()
        #expect(try await store.load() == nil)
        try await store.clear()
        #expect(try await store.load() == nil)
    }
}

private final class FailOnNthRemovalFileManager: FileManager, @unchecked Sendable {
    enum InjectedFailure: Error, Equatable {
        case removal(Int)
    }

    private let failOnRemoval: Int
    private var removalCount = 0
    private(set) var removedFileNames: [String] = []

    init(failOnRemoval: Int) {
        self.failOnRemoval = failOnRemoval
        super.init()
    }

    override func removeItem(at URL: URL) throws {
        removalCount += 1
        guard removalCount != failOnRemoval else {
            throw InjectedFailure.removal(removalCount)
        }
        try super.removeItem(at: URL)
        removedFileNames.append(URL.lastPathComponent)
    }
}
