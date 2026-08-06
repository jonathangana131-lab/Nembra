import Foundation
import Observation
import SwiftData

@Model
final class StoredRideHistoryRecord {
    @Attribute(.unique) var sessionID: UUID
    var payload: Data

    init(sessionID: UUID, payload: Data) {
        self.sessionID = sessionID
        self.payload = payload
    }
}

@Model
final class StoredRideRouteChunk {
    @Attribute(.unique) var storageID: String
    var sessionID: UUID
    var segmentIndex: Int
    var chunkIndex: Int
    var payload: Data

    init(
        storageID: String,
        sessionID: UUID,
        segmentIndex: Int,
        chunkIndex: Int,
        payload: Data
    ) {
        self.storageID = storageID
        self.sessionID = sessionID
        self.segmentIndex = segmentIndex
        self.chunkIndex = chunkIndex
        self.payload = payload
    }
}

@Model
final class StoredRideRouteManifest {
    @Attribute(.unique) var sessionID: UUID
    var payload: Data

    init(sessionID: UUID, payload: Data) {
        self.sessionID = sessionID
        self.payload = payload
    }
}

enum RideHistoryPersistenceError: Error, Equatable, Sendable {
    case corruptRecord(UUID)
    case corruptRouteChunk(String)
    case corruptRouteManifest(UUID)
    case durableVerificationFailed(UUID)
    case durableRouteVerificationFailed(String)
    case applicationSupportUnavailable
}

/// Concrete local completed-ride history. The stored payload remains the exact
/// validated core record so reconciliation can evolve without changing ride
/// identity or silently rewriting old evidence.
@ModelActor
actor SwiftDataRideHistoryStore: RideHistoryStore {
    func commit(_ record: RideHistoryRecord) async throws -> RideHistoryCommitResult {
        if let existing = try storedRecord(sessionID: record.sessionID) {
            let decoded = try decode(existing, sessionID: record.sessionID)
            guard decoded == record else {
                throw RideHistoryStoreError.sessionConflict(record.sessionID)
            }
            return .alreadyPresent
        }

        let payload = try JSONEncoder().encode(record)
        modelContext.insert(
            StoredRideHistoryRecord(
                sessionID: record.sessionID,
                payload: payload
            )
        )

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }

        guard let verified = try storedRecord(sessionID: record.sessionID),
              try decode(verified, sessionID: record.sessionID) == record else {
            throw RideHistoryPersistenceError.durableVerificationFailed(record.sessionID)
        }

        return .inserted
    }

    func record(sessionID: UUID) async throws -> RideHistoryRecord? {
        guard let stored = try storedRecord(sessionID: sessionID) else { return nil }
        return try decode(stored, sessionID: sessionID)
    }

    /// Returns validated durable records newest-first. Listing decodes every
    /// payload through the same identity checks as point lookup; corrupted rows
    /// fail closed rather than disappearing from the user's history silently.
    func records() throws -> [RideHistoryRecord] {
        let storedRecords = try modelContext.fetch(FetchDescriptor<StoredRideHistoryRecord>())
        let decoded = try storedRecords.map { stored in
            try decode(stored, sessionID: stored.sessionID)
        }
        return decoded.sorted { lhs, rhs in
            if lhs.evidence.endedAtDate != rhs.evidence.endedAtDate {
                return lhs.evidence.endedAtDate > rhs.evidence.endedAtDate
            }
            return lhs.sessionID.uuidString < rhs.sessionID.uuidString
        }
    }

    private func storedRecord(sessionID: UUID) throws -> StoredRideHistoryRecord? {
        let key = sessionID
        var descriptor = FetchDescriptor<StoredRideHistoryRecord>(
            predicate: #Predicate { stored in
                stored.sessionID == key
            }
        )
        descriptor.fetchLimit = 2

        let matches = try modelContext.fetch(descriptor)
        guard matches.count <= 1 else {
            throw RideHistoryPersistenceError.corruptRecord(sessionID)
        }
        return matches.first
    }

    private func decode(
        _ stored: StoredRideHistoryRecord,
        sessionID: UUID
    ) throws -> RideHistoryRecord {
        do {
            let decoded = try JSONDecoder().decode(RideHistoryRecord.self, from: stored.payload)
            guard stored.sessionID == sessionID,
                  decoded.sessionID == sessionID else {
                throw RideHistoryPersistenceError.corruptRecord(sessionID)
            }
            return decoded
        } catch let error as RideHistoryPersistenceError {
            throw error
        } catch {
            throw RideHistoryPersistenceError.corruptRecord(sessionID)
        }
    }
}

/// Separate route-geometry durability domain. Immutable chunks and the final
/// manifest are exact JSON payloads with indexed identity duplicated only so
/// corruption can be detected before geometry reaches presentation.
@ModelActor
actor SwiftDataRideRouteStore: RideRouteStore {
    func commit(_ chunk: RideRouteChunk) async throws -> RideRouteStoreCommitResult {
        let storageID = Self.storageID(for: chunk.id)
        if let existing = try storedChunk(storageID: storageID) {
            let decoded = try decode(existing, expectedID: chunk.id)
            guard decoded == chunk else {
                throw RideRouteStoreError.chunkConflict(chunk.id)
            }
            return .alreadyPresent
        }

        let payload = try JSONEncoder().encode(chunk)
        modelContext.insert(
            StoredRideRouteChunk(
                storageID: storageID,
                sessionID: chunk.id.sessionID,
                segmentIndex: Int(chunk.id.segmentIndex),
                chunkIndex: Int(chunk.id.chunkIndex),
                payload: payload
            )
        )

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }

        guard let verified = try storedChunk(storageID: storageID),
              try decode(verified, expectedID: chunk.id) == chunk else {
            throw RideHistoryPersistenceError.durableRouteVerificationFailed(storageID)
        }
        return .inserted
    }

    func chunk(id: RideRouteChunkID) async throws -> RideRouteChunk? {
        let storageID = Self.storageID(for: id)
        guard let stored = try storedChunk(storageID: storageID) else { return nil }
        return try decode(stored, expectedID: id)
    }

    func chunks(sessionID: UUID) async throws -> [RideRouteChunk] {
        let key = sessionID
        let descriptor = FetchDescriptor<StoredRideRouteChunk>(
            predicate: #Predicate { stored in
                stored.sessionID == key
            }
        )
        let stored = try modelContext.fetch(descriptor)
        let decoded = try stored.map { row in
            let id = RideRouteChunkID(
                sessionID: row.sessionID,
                segmentIndex: try checkedUInt32(row.segmentIndex, storageID: row.storageID),
                chunkIndex: try checkedUInt32(row.chunkIndex, storageID: row.storageID)
            )
            return try decode(row, expectedID: id)
        }
        return decoded.sorted { lhs, rhs in
            if lhs.id.segmentIndex != rhs.id.segmentIndex {
                return lhs.id.segmentIndex < rhs.id.segmentIndex
            }
            return lhs.id.chunkIndex < rhs.id.chunkIndex
        }
    }

    func commit(_ manifest: RideRouteManifest) async throws -> RideRouteStoreCommitResult {
        if let existing = try storedManifest(sessionID: manifest.sessionID) {
            let decoded = try decode(existing, sessionID: manifest.sessionID)
            guard decoded == manifest else {
                throw RideRouteStoreError.manifestConflict(manifest.sessionID)
            }
            return .alreadyPresent
        }

        let payload = try JSONEncoder().encode(manifest)
        modelContext.insert(
            StoredRideRouteManifest(
                sessionID: manifest.sessionID,
                payload: payload
            )
        )

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }

        guard let verified = try storedManifest(sessionID: manifest.sessionID),
              try decode(verified, sessionID: manifest.sessionID) == manifest else {
            throw RideHistoryPersistenceError.durableRouteVerificationFailed(manifest.sessionID.uuidString)
        }
        return .inserted
    }

    func manifest(sessionID: UUID) async throws -> RideRouteManifest? {
        guard let stored = try storedManifest(sessionID: sessionID) else { return nil }
        return try decode(stored, sessionID: sessionID)
    }

    func geometry(sessionID: UUID) async throws -> RideRouteGeometry? {
        guard let manifest = try await manifest(sessionID: sessionID) else { return nil }
        return try RideRouteGeometry(
            manifest: manifest,
            chunks: try await chunks(sessionID: sessionID)
        )
    }

    private static func storageID(for id: RideRouteChunkID) -> String {
        "\(id.sessionID.uuidString)|\(id.segmentIndex)|\(id.chunkIndex)"
    }

    private func storedChunk(storageID: String) throws -> StoredRideRouteChunk? {
        let key = storageID
        var descriptor = FetchDescriptor<StoredRideRouteChunk>(
            predicate: #Predicate { stored in
                stored.storageID == key
            }
        )
        descriptor.fetchLimit = 2
        let matches = try modelContext.fetch(descriptor)
        guard matches.count <= 1 else {
            throw RideHistoryPersistenceError.corruptRouteChunk(storageID)
        }
        return matches.first
    }

    private func storedManifest(sessionID: UUID) throws -> StoredRideRouteManifest? {
        let key = sessionID
        var descriptor = FetchDescriptor<StoredRideRouteManifest>(
            predicate: #Predicate { stored in
                stored.sessionID == key
            }
        )
        descriptor.fetchLimit = 2
        let matches = try modelContext.fetch(descriptor)
        guard matches.count <= 1 else {
            throw RideHistoryPersistenceError.corruptRouteManifest(sessionID)
        }
        return matches.first
    }

    private func decode(
        _ stored: StoredRideRouteChunk,
        expectedID: RideRouteChunkID
    ) throws -> RideRouteChunk {
        do {
            let decoded = try JSONDecoder().decode(RideRouteChunk.self, from: stored.payload)
            let storageID = Self.storageID(for: expectedID)
            guard stored.storageID == storageID,
                  stored.sessionID == expectedID.sessionID,
                  stored.segmentIndex == Int(expectedID.segmentIndex),
                  stored.chunkIndex == Int(expectedID.chunkIndex),
                  decoded.id == expectedID else {
                throw RideHistoryPersistenceError.corruptRouteChunk(stored.storageID)
            }
            return decoded
        } catch let error as RideHistoryPersistenceError {
            throw error
        } catch {
            throw RideHistoryPersistenceError.corruptRouteChunk(stored.storageID)
        }
    }

    private func decode(
        _ stored: StoredRideRouteManifest,
        sessionID: UUID
    ) throws -> RideRouteManifest {
        do {
            let decoded = try JSONDecoder().decode(RideRouteManifest.self, from: stored.payload)
            guard stored.sessionID == sessionID,
                  decoded.sessionID == sessionID else {
                throw RideHistoryPersistenceError.corruptRouteManifest(sessionID)
            }
            return decoded
        } catch let error as RideHistoryPersistenceError {
            throw error
        } catch {
            throw RideHistoryPersistenceError.corruptRouteManifest(sessionID)
        }
    }

    private func checkedUInt32(_ value: Int, storageID: String) throws -> UInt32 {
        guard value >= 0,
              value <= Int(UInt32.max) else {
            throw RideHistoryPersistenceError.corruptRouteChunk(storageID)
        }
        return UInt32(value)
    }
}

enum RideHistoryPresentationStatus: Equatable, Sendable {
    case idle
    case loading
    case ready
    case unavailable
    case failed
}

/// Root-owned read model for the Rides surface. SwiftUI never reaches directly
/// into SwiftData, and completed records remain immutable core evidence rather
/// than being rewritten into prettier but less truthful summaries.
@MainActor
@Observable
final class RideHistoryPresentationStore {
    private(set) var records: [RideHistoryRecord] = []
    private(set) var status: RideHistoryPresentationStatus
    private(set) var lastErrorMessage: String?

    @ObservationIgnored private let historyStore: SwiftDataRideHistoryStore?
    @ObservationIgnored private let startupPersistenceError: String?

    init(
        historyStore: SwiftDataRideHistoryStore?,
        startupPersistenceError: String? = nil
    ) {
        self.historyStore = historyStore
        self.startupPersistenceError = startupPersistenceError
        self.lastErrorMessage = startupPersistenceError
        self.status = historyStore == nil ? .unavailable : .idle
    }

    func refresh() async {
        guard let historyStore else {
            if lastErrorMessage == nil {
                lastErrorMessage = startupPersistenceError ?? "Local ride history storage is unavailable."
            }
            setStatus(.unavailable)
            return
        }

        if records.isEmpty {
            setStatus(.loading)
        }

        do {
            let loaded = try await historyStore.records()
            if records != loaded {
                records = loaded
            }
            if lastErrorMessage != nil {
                lastErrorMessage = nil
            }
            setStatus(.ready)
        } catch {
            let message = "Local ride history could not be read safely."
            if lastErrorMessage != message {
                lastErrorMessage = message
            }
            setStatus(.failed)
        }
    }

    private func setStatus(_ newStatus: RideHistoryPresentationStatus) {
        if status != newStatus {
            status = newStatus
        }
    }
}

enum RidePersistenceScope: Equatable, Sendable {
    case production
    case simulation(scenario: ScooterSimulationScenario, namespace: String?)

    fileprivate var pathComponents: [String] {
        switch self {
        case .production:
            return ["production"]
        case .simulation(let scenario, let namespace):
            var components = ["simulation", scenario.rawValue]
            if let namespace, !namespace.isEmpty {
                components.append(Self.safePathComponent(namespace))
            }
            return components
        }
    }

    private static func safePathComponent(_ rawValue: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let mapped = rawValue.map { character -> Character in
            character.unicodeScalars.allSatisfy { allowed.contains($0) } ? character : "_"
        }
        let result = String(mapped.prefix(80))
        return result.isEmpty ? "default" : result
    }
}

struct RidePersistenceStack: Sendable {
    let checkpointStore: AtomicRideCheckpointStore
    let historyStore: SwiftDataRideHistoryStore
    let routeStore: SwiftDataRideRouteStore
}

enum RidePersistenceFactory {
    static func make(
        scope: RidePersistenceScope,
        baseDirectoryURL: URL? = nil
    ) throws -> RidePersistenceStack {
        let rootDirectory: URL
        if let baseDirectoryURL {
            rootDirectory = baseDirectoryURL
        } else {
            rootDirectory = try defaultRootDirectory()
        }

        var scopeDirectory = rootDirectory
        for component in scope.pathComponents {
            scopeDirectory.appendPathComponent(component, isDirectory: true)
        }

        try FileManager.default.createDirectory(
            at: scopeDirectory,
            withIntermediateDirectories: true
        )

        let recoveryDirectory = scopeDirectory.appendingPathComponent(
            "Recovery",
            isDirectory: true
        )
        let checkpointStore = AtomicRideCheckpointStore(directoryURL: recoveryDirectory)

        let historyURL = scopeDirectory.appendingPathComponent("RideHistory.store")
        let historyContainer = try makeHistoryContainer(storeURL: historyURL)
        let historyStore = SwiftDataRideHistoryStore(modelContainer: historyContainer)

        let routesURL = scopeDirectory.appendingPathComponent("RideRoutes.store")
        let routesContainer = try makeRouteContainer(storeURL: routesURL)
        let routeStore = SwiftDataRideRouteStore(modelContainer: routesContainer)

        return RidePersistenceStack(
            checkpointStore: checkpointStore,
            historyStore: historyStore,
            routeStore: routeStore
        )
    }

    static func makeHistoryContainer(storeURL: URL) throws -> ModelContainer {
        let parent = storeURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true
        )

        let schema = Schema([StoredRideHistoryRecord.self])
        let configuration = ModelConfiguration(
            "NembraRideHistory",
            schema: schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: nil,
            configurations: [configuration]
        )
    }

    static func makeRouteContainer(storeURL: URL) throws -> ModelContainer {
        let parent = storeURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true
        )

        let schema = Schema([
            StoredRideRouteChunk.self,
            StoredRideRouteManifest.self
        ])
        let configuration = ModelConfiguration(
            "NembraRideRoutes",
            schema: schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: nil,
            configurations: [configuration]
        )
    }

    private static func defaultRootDirectory() throws -> URL {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw RideHistoryPersistenceError.applicationSupportUnavailable
        }
        return applicationSupport
            .appendingPathComponent("Nembra", isDirectory: true)
            .appendingPathComponent("Rides", isDirectory: true)
    }
}
