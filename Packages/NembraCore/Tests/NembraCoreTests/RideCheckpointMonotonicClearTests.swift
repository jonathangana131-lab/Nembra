import Foundation
import Testing
@testable import NembraCore

@Suite("Monotonic ride checkpoint acknowledgement")
struct RideCheckpointMonotonicClearTests {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("interruption after removing slot A preserves newer completion in slot B")
    func interruptedClearPreservesCompletionInSlotB() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileManager = FailOnSecondRemovalFileManager()
        let store = AtomicRideCheckpointStore(directoryURL: directory, fileManager: fileManager)
        let sessionID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let completion = try completedRide(sessionID: sessionID)

        // Generation 1 -> A (older in-progress), generation 2 -> B (newest completion).
        try await store.save(.inProgress(try inProgress(sessionID: sessionID, latestODO: 100.2)))
        try await store.save(.completedPendingCommit(completion))

        await #expect(throws: SimulatedClearInterruption.self) {
            try await store.clear()
        }

        // Model a fresh process after the interrupted acknowledgement. The newest
        // completion handoff must still win; the older in-progress ride is gone.
        let recovered = AtomicRideCheckpointStore(directoryURL: directory)
        #expect(try await recovered.load() == .completedPendingCommit(completion))
    }

    @Test("interruption after removing slot B preserves newer completion in slot A")
    func interruptedClearPreservesCompletionInSlotA() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileManager = FailOnSecondRemovalFileManager()
        let store = AtomicRideCheckpointStore(directoryURL: directory, fileManager: fileManager)
        let sessionID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let completion = try completedRide(sessionID: sessionID)

        // Generation 1 -> A, generation 2 -> B, generation 3 -> A. A fixed A-then-B
        // deletion order is unsafe here; generation ordering must remove B first.
        try await store.save(.inProgress(try inProgress(sessionID: sessionID, latestODO: 100.2)))
        try await store.save(.inProgress(try inProgress(sessionID: sessionID, latestODO: 100.4)))
        try await store.save(.completedPendingCommit(completion))

        await #expect(throws: SimulatedClearInterruption.self) {
            try await store.clear()
        }

        let recovered = AtomicRideCheckpointStore(directoryURL: directory)
        #expect(try await recovered.load() == .completedPendingCommit(completion))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nembra-monotonic-clear-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func inProgress(sessionID: UUID, latestODO: Double) throws -> RideRecoveryCheckpoint {
        try RideRecoveryCheckpoint(
            sessionID: sessionID,
            beganAtDate: epoch,
            confirmedAtDate: epoch.addingTimeInterval(2),
            persistedPhase: .active,
            phaseBeganAtDate: nil,
            lastObservedAtDate: epoch.addingTimeInterval(30),
            checkpointedAtDate: epoch.addingTimeInterval(31),
            startingOdometerKilometers: 100,
            latestOdometerKilometers: latestODO,
            accumulatedGPSDistanceMeters: 500,
            transportGapEvidence: .noneObserved
        )
    }

    private func completedRide(sessionID: UUID) throws -> CompletedRideEvidence {
        try CompletedRideEvidence(
            sessionID: sessionID,
            beganAtDate: epoch,
            confirmedAtDate: epoch.addingTimeInterval(2),
            endedAtDate: epoch.addingTimeInterval(60),
            startingOdometerKilometers: 100,
            endingOdometerKilometers: 101,
            qualityScreenedGPSDistanceMeters: 1_400,
            continuity: .uninterruptedProcess,
            transportGapEvidence: .noneObserved
        )
    }
}

private struct SimulatedClearInterruption: Error {}

private final class FailOnSecondRemovalFileManager: FileManager, @unchecked Sendable {
    private var successfulRemovalCount = 0

    override func removeItem(at URL: URL) throws {
        guard successfulRemovalCount == 0 else {
            throw SimulatedClearInterruption()
        }
        try super.removeItem(at: URL)
        successfulRemovalCount += 1
    }
}
