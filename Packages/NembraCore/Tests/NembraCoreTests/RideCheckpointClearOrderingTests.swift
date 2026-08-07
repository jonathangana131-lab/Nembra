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

    @Test("corrupt fallback is removed before the sole valid authority")
    func corruptFallbackIsRemovedBeforeValidAuthority() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let sessionID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let checkpoint = try checkpoint(id: sessionID, latestODO: 100.6, gpsMeters: 600)
        let fileManager = FailOnNthRemovalFileManager(failOnRemoval: 2)
        let store = AtomicRideCheckpointStore(directoryURL: dir, fileManager: fileManager)

        try await store.save(.inProgress(checkpoint))
        let corruptB = dir.appendingPathComponent(AtomicRideCheckpointStore.slotBFileName)
        try Data("corrupt-fallback".utf8).write(to: corruptB)

        await #expect(throws: FailOnNthRemovalFileManager.InjectedFailure.removal(2)) {
            try await store.clear()
        }
        #expect(fileManager.removedFileNames == [AtomicRideCheckpointStore.slotBFileName])

        let fresh = AtomicRideCheckpointStore(directoryURL: dir)
        #expect(try await fresh.load() == .inProgress(checkpoint))
    }

    @Test("unsupported schema fails clear before deleting any evidence")
    func unsupportedSchemaFailsBeforeDeletion() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let slotA = dir.appendingPathComponent(AtomicRideCheckpointStore.slotAFileName)
        let bytes = Data("{\"schemaVersion\":999}".utf8)
        try bytes.write(to: slotA)
        let fileManager = FailOnNthRemovalFileManager(failOnRemoval: 99)
        let store = AtomicRideCheckpointStore(directoryURL: dir, fileManager: fileManager)

        await #expect(throws: RideCheckpointError.unsupportedSchema(999)) {
            try await store.clear()
        }
        #expect(fileManager.removedFileNames.isEmpty)
        #expect(try Data(contentsOf: slotA) == bytes)
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
