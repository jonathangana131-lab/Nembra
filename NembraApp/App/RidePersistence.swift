import Foundation
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

enum RideHistoryPersistenceError: Error, Equatable, Sendable {
    case corruptRecord(UUID)
    case durableVerificationFailed(UUID)
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
        let container = try makeHistoryContainer(storeURL: historyURL)
        let historyStore = SwiftDataRideHistoryStore(modelContainer: container)

        return RidePersistenceStack(
            checkpointStore: checkpointStore,
            historyStore: historyStore
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
