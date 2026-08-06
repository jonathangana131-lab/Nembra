import Foundation

/// File-backed permanent completed-ride history.
///
/// Each ride is stored in its own UUID-named JSON file. Writes use Foundation's
/// atomic replacement semantics, then immediately read back and compare the exact
/// record before reporting success. The actor serializes commit/read operations so
/// two callers cannot race a first insert into a conflicting overwrite.
///
/// This store deliberately owns only completed durable evidence. Route geometry,
/// derived statistics, cloud sync and reconciliation metadata remain separate
/// layers and must never be invented merely to fill this record.
public actor AtomicRideHistoryStore: RideHistoryStore {
    private let directoryURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directoryURL: URL, fileManager: FileManager = .default) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    public func commit(_ record: RideHistoryRecord) async throws -> RideHistoryCommitResult {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let url = recordURL(sessionID: record.sessionID)
        if fileManager.fileExists(atPath: url.path) {
            let existing = try decodeRecord(at: url, sessionID: record.sessionID)
            guard existing == record else {
                throw RideHistoryStoreError.sessionConflict(record.sessionID)
            }
            return .alreadyPresent
        }

        let data = try encoder.encode(record)
        try data.write(to: url, options: .atomic)

        guard try decodeRecord(at: url, sessionID: record.sessionID) == record else {
            throw RideHistoryStoreError.corruptedRecord(record.sessionID)
        }
        return .inserted
    }

    public func record(sessionID: UUID) async throws -> RideHistoryRecord? {
        let url = recordURL(sessionID: sessionID)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        return try decodeRecord(at: url, sessionID: sessionID)
    }

    private func recordURL(sessionID: UUID) -> URL {
        directoryURL.appendingPathComponent(
            sessionID.uuidString.lowercased() + ".json",
            isDirectory: false
        )
    }

    private func decodeRecord(at url: URL, sessionID: UUID) throws -> RideHistoryRecord {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw RideHistoryStoreError.corruptedRecord(sessionID)
        }

        let record: RideHistoryRecord
        do {
            record = try decoder.decode(RideHistoryRecord.self, from: data)
        } catch {
            throw RideHistoryStoreError.corruptedRecord(sessionID)
        }

        guard record.sessionID == sessionID else {
            throw RideHistoryStoreError.corruptedRecord(sessionID)
        }
        return record
    }
}
