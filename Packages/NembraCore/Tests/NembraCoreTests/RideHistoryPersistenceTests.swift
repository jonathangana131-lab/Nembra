import Foundation
import Testing
@testable import NembraCore

@Suite("Durable completed ride history")
struct RideHistoryPersistenceTests {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)
    private let sessionID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nembra-history-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func record(endingODO: Double = 12.4) throws -> RideHistoryRecord {
        RideHistoryRecord(
            evidence: try CompletedRideEvidence(
                sessionID: sessionID,
                beganAtDate: epoch,
                confirmedAtDate: epoch.addingTimeInterval(2),
                endedAtDate: epoch.addingTimeInterval(180),
                startingOdometerKilometers: 12.0,
                endingOdometerKilometers: endingODO,
                qualityScreenedGPSDistanceMeters: 380,
                continuity: .uninterruptedProcess
            )
        )
    }

    @Test("new completed ride is atomically persisted and readable")
    func insertAndReadBack() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AtomicRideHistoryStore(directoryURL: directory)
        let expected = try record()

        #expect(try await store.commit(expected) == .inserted)
        #expect(try await store.record(sessionID: sessionID) == expected)
    }

    @Test("recommitting identical durable evidence is idempotent")
    func equivalentRecordIsAlreadyPresent() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AtomicRideHistoryStore(directoryURL: directory)
        let expected = try record()

        #expect(try await store.commit(expected) == .inserted)
        #expect(try await store.commit(expected) == .alreadyPresent)
        #expect(try await store.record(sessionID: sessionID) == expected)
    }

    @Test("same session UUID with different evidence is never overwritten")
    func conflictDoesNotOverwrite() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AtomicRideHistoryStore(directoryURL: directory)
        let original = try record(endingODO: 12.4)
        let conflicting = try record(endingODO: 12.8)
        _ = try await store.commit(original)

        await #expect(throws: RideHistoryStoreError.sessionConflict(sessionID)) {
            try await store.commit(conflicting)
        }
        #expect(try await store.record(sessionID: sessionID) == original)
    }

    @Test("corrupt existing history is surfaced and preserved")
    func corruptRecordIsNotReplaced() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent(sessionID.uuidString.lowercased() + ".json")
        try Data("not-json".utf8).write(to: url)
        let store = AtomicRideHistoryStore(directoryURL: directory)

        await #expect(throws: RideHistoryStoreError.corruptedRecord(sessionID)) {
            _ = try await store.record(sessionID: sessionID)
        }
        await #expect(throws: RideHistoryStoreError.corruptedRecord(sessionID)) {
            _ = try await store.commit(try record())
        }
        #expect(try Data(contentsOf: url) == Data("not-json".utf8))
    }

    @Test("missing session returns nil without creating a file")
    func missingRecordIsNil() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AtomicRideHistoryStore(directoryURL: directory)

        #expect(try await store.record(sessionID: sessionID) == nil)
        #expect((try FileManager.default.contentsOfDirectory(atPath: directory.path)).isEmpty)
    }
}
