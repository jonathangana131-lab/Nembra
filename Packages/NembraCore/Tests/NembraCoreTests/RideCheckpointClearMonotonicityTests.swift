import Foundation
import Testing
@testable import NembraCore

@Suite("Ride checkpoint clear monotonicity")
struct RideCheckpointClearMonotonicityTests {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nembra-ride-checkpoint-clear-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func checkpoint(
        id: UUID,
        latestOdometer: Double,
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
            latestOdometerKilometers: latestOdometer,
            accumulatedGPSDistanceMeters: gpsMeters
        )
    }

    private func completed(
        id: UUID,
        endingOdometer: Double,
        gpsMeters: Double
    ) throws -> CompletedRideEvidence {
        try CompletedRideEvidence(
            sessionID: id,
            beganAtDate: epoch,
            confirmedAtDate: epoch.addingTimeInterval(2),
            endedAtDate: epoch.addingTimeInterval(60),
            startingOdometerKilometers: 100,
            endingOdometerKilometers: endingOdometer,
            qualityScreenedGPSDistanceMeters: gpsMeters,
            continuity: .uninterruptedProcess
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
        let completion = try completed(
            id: sessionID,
            endingOdometer: 101,
            gpsMeters: 1_000
        )
        let fileManager = FailOnNthCheckpointRemovalFileManager(failOnRemoval: 2)
        let store = AtomicRideCheckpointStore(directoryURL: dir, fileManager: fileManager)

        try await store.save(
            .inProgress(
                try checkpoint(
                    id: sessionID,
                    latestOdometer: 100.4,
                    gpsMeters: 400
                )
            )
        )
        try await store.save(.completedPendingCommit(completion))

        await #expect(throws: FailOnNthCheckpointRemovalFileManager.InjectedFailure.removal(2)) {
            try await store.clear()
        }
        #expect(fileManager.removedFileNames == [AtomicRideCheckpointStore.slotAFileName])

        let freshStore = AtomicRideCheckpointStore(directoryURL: dir)
        #expect(try await freshStore.load() == .completedPendingCommit(completion))
        try await freshStore.clear()
        #expect(try await freshStore.load() == nil)
    }

    @Test("interrupted clear keeps newest completion when slot A is authoritative")
    func interruptedClearKeepsNewestSlotACompletion() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let sessionID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let completion = try completed(
            id: sessionID,
            endingOdometer: 101.4,
            gpsMeters: 1_400
        )
        let fileManager = FailOnNthCheckpointRemovalFileManager(failOnRemoval: 2)
        let store = AtomicRideCheckpointStore(directoryURL: dir, fileManager: fileManager)

        try await store.save(
            .inProgress(
                try checkpoint(
                    id: sessionID,
                    latestOdometer: 100.3,
                    gpsMeters: 300
                )
            )
        )
        try await store.save(
            .inProgress(
                try checkpoint(
                    id: sessionID,
                    latestOdometer: 100.8,
                    gpsMeters: 800
                )
            )
        )
        try await store.save(.completedPendingCommit(completion))

        await #expect(throws: FailOnNthCheckpointRemovalFileManager.InjectedFailure.removal(2)) {
            try await store.clear()
        }
        #expect(fileManager.removedFileNames == [AtomicRideCheckpointStore.slotBFileName])

        let freshStore = AtomicRideCheckpointStore(directoryURL: dir)
        #expect(try await freshStore.load() == .completedPendingCommit(completion))
        try await freshStore.clear()
        #expect(try await freshStore.load() == nil)
    }

    @Test("corrupt slot blocks clear and preserves forensic bytes")
    func corruptSlotFailsClosedBeforeDeletion() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let sessionID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let store = AtomicRideCheckpointStore(directoryURL: dir)

        try await store.save(
            .inProgress(
                try checkpoint(
                    id: sessionID,
                    latestOdometer: 100.6,
                    gpsMeters: 600
                )
            )
        )
        try await store.save(
            .completedPendingCommit(
                try completed(
                    id: sessionID,
                    endingOdometer: 101.2,
                    gpsMeters: 1_200
                )
            )
        )

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

    @Test("unsupported schema blocks clear before deleting valid evidence")
    func unsupportedSchemaFailsClosedBeforeDeletion() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let sessionID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let store = AtomicRideCheckpointStore(directoryURL: dir)

        try await store.save(
            .inProgress(
                try checkpoint(
                    id: sessionID,
                    latestOdometer: 100.2,
                    gpsMeters: 200
                )
            )
        )

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

    @Test("divergent same-generation evidence blocks clear atomically")
    func conflictingGenerationFailsClosedBeforeDeletion() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let sessionID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let slotA = slotURL(AtomicRideCheckpointStore.slotAFileName, in: dir)
        let slotB = slotURL(AtomicRideCheckpointStore.slotBFileName, in: dir)

        let bytesA = try encodedEnvelope(
            generation: 7,
            checkpoint: .inProgress(
                try checkpoint(
                    id: sessionID,
                    latestOdometer: 100.4,
                    gpsMeters: 400
                )
            )
        )
        let bytesB = try encodedEnvelope(
            generation: 7,
            checkpoint: .completedPendingCommit(
                try completed(
                    id: sessionID,
                    endingOdometer: 101,
                    gpsMeters: 1_000
                )
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

    @Test("empty and single-slot journals clear idempotently")
    func emptyAndSingleSlotClearIdempotently() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let sessionID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        let store = AtomicRideCheckpointStore(directoryURL: dir)

        try await store.clear()
        #expect(try await store.load() == nil)

        try await store.save(
            .inProgress(
                try checkpoint(
                    id: sessionID,
                    latestOdometer: 100.7,
                    gpsMeters: 700
                )
            )
        )
        try await store.clear()
        #expect(try await store.load() == nil)
        try await store.clear()
        #expect(try await store.load() == nil)
    }
}

private final class FailOnNthCheckpointRemovalFileManager: FileManager, @unchecked Sendable {
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
