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

enum RideRouteRecorderError: Error, Equatable, Sendable {
    case invalidChunkSize
    case alreadyRecording(UUID)
    case noActiveSession
    case finalizedSession(UUID)
    case corruptDraft(UUID)
    case sequenceOverflow
}

/// App-lifetime route writer. Location producers hand it only already
/// quality-screened coordinates; it assigns durable order and writes immutable
/// chunks through the same store used by history presentation. A caller must
/// explicitly classify coverage rather than letting the recorder infer that a
/// visually continuous path proves whole-ride coverage.
actor RideRouteRecorder {
    private let store: any RideRouteStore
    private let chunkSize: Int

    private var sessionID: UUID?
    private var segmentIndex: UInt32 = 0
    private var chunkIndex: UInt32 = 0
    private var nextSequence: UInt64 = 0
    private var buffer: [RideRoutePoint] = []
    private var persistedPointCount = 0
    private var segmentCount = 0
    private var knownGapCount = 0
    private var forcedPartialCoverage = false
    private var pendingGap = false

    init(store: any RideRouteStore, chunkSize: Int = 8) throws {
        guard chunkSize > 0 else {
            throw RideRouteRecorderError.invalidChunkSize
        }
        self.store = store
        self.chunkSize = chunkSize
    }

    func begin(
        sessionID: UUID,
        startsAfterKnownGap: Bool = false,
        coverageAlreadyPartial: Bool = false
    ) async throws {
        if let active = self.sessionID {
            throw RideRouteRecorderError.alreadyRecording(active)
        }
        if try await store.manifest(sessionID: sessionID) != nil {
            throw RideRouteRecorderError.finalizedSession(sessionID)
        }

        let existing = try await store.chunks(sessionID: sessionID)
        let draft = try Self.validateDraft(existing, sessionID: sessionID)

        self.sessionID = sessionID
        persistedPointCount = draft.pointCount
        nextSequence = draft.nextSequence
        forcedPartialCoverage = coverageAlreadyPartial || startsAfterKnownGap || draft.pointCount > 0

        if let lastSegment = draft.lastSegmentIndex {
            segmentCount = Int(lastSegment) + 1
            knownGapCount = Int(lastSegment)
            segmentIndex = lastSegment
            chunkIndex = draft.nextChunkIndex
            // Existing unfinished chunks imply a prior recorder/process stopped.
            // The next accepted coordinate must start a new segment so recovery
            // never draws a plausible line across missing location coverage.
            pendingGap = draft.pointCount > 0
        } else {
            segmentIndex = 0
            chunkIndex = 0
            segmentCount = 0
            knownGapCount = 0
            pendingGap = false
        }
    }

    func append(
        latitude: Double,
        longitude: Double,
        capturedAtDate: Date,
        sourceMeasurementDate: Date? = nil,
        horizontalAccuracyMeters: Double? = nil
    ) async throws {
        guard let sessionID else {
            throw RideRouteRecorderError.noActiveSession
        }

        try materializePendingGap(sessionID: sessionID)

        let point = try RideRoutePoint(
            sequence: nextSequence,
            latitude: latitude,
            longitude: longitude,
            capturedAtDate: capturedAtDate,
            sourceMeasurementDate: sourceMeasurementDate,
            horizontalAccuracyMeters: horizontalAccuracyMeters
        )

        guard nextSequence < UInt64.max else {
            throw RideRouteRecorderError.sequenceOverflow
        }
        nextSequence += 1
        buffer.append(point)
        if segmentCount == 0 {
            segmentCount = 1
        }

        if buffer.count >= chunkSize {
            try await flush()
        }
    }

    func markKnownGap() async throws {
        guard sessionID != nil else {
            throw RideRouteRecorderError.noActiveSession
        }
        try await flush()
        forcedPartialCoverage = true

        // A gap boundary is materialized only when another coordinate arrives.
        // Repeated gap events collapse together and finishing after a gap cannot
        // create a manifest that claims an empty trailing segment.
        if persistedPointCount > 0 {
            pendingGap = true
        }
    }

    @discardableResult
    func finish(requestedCoverage: RideDistanceCoverage) async throws -> RideRouteManifest {
        guard let sessionID else {
            throw RideRouteRecorderError.noActiveSession
        }
        try await flush()

        let manifest: RideRouteManifest
        if persistedPointCount == 0 {
            manifest = try RideRouteManifest(
                sessionID: sessionID,
                coverage: .unknown,
                segmentCount: 0,
                pointCount: 0,
                knownGapCount: 0
            )
        } else {
            let coverage: RideDistanceCoverage
            if forcedPartialCoverage || pendingGap || knownGapCount > 0 {
                coverage = .partial
            } else {
                coverage = requestedCoverage
            }
            manifest = try RideRouteManifest(
                sessionID: sessionID,
                coverage: coverage,
                segmentCount: segmentCount,
                pointCount: persistedPointCount,
                knownGapCount: knownGapCount
            )
        }

        _ = try await store.commit(manifest)
        reset()
        return manifest
    }

    private func materializePendingGap(sessionID: UUID) throws {
        guard pendingGap, persistedPointCount > 0 else {
            pendingGap = false
            return
        }
        guard segmentIndex < UInt32.max else {
            throw RideRouteRecorderError.corruptDraft(sessionID)
        }
        segmentIndex += 1
        chunkIndex = 0
        segmentCount += 1
        knownGapCount += 1
        pendingGap = false
    }

    private func flush() async throws {
        guard let sessionID,
              !buffer.isEmpty else { return }

        let chunk = try RideRouteChunk(
            id: RideRouteChunkID(
                sessionID: sessionID,
                segmentIndex: segmentIndex,
                chunkIndex: chunkIndex
            ),
            points: buffer
        )
        _ = try await store.commit(chunk)
        persistedPointCount += buffer.count
        buffer.removeAll(keepingCapacity: true)
        guard chunkIndex < UInt32.max else {
            throw RideRouteRecorderError.corruptDraft(sessionID)
        }
        chunkIndex += 1
    }

    private func reset() {
        sessionID = nil
        segmentIndex = 0
        chunkIndex = 0
        nextSequence = 0
        buffer.removeAll(keepingCapacity: false)
        persistedPointCount = 0
        segmentCount = 0
        knownGapCount = 0
        forcedPartialCoverage = false
        pendingGap = false
    }

    private struct DraftState {
        let lastSegmentIndex: UInt32?
        let nextChunkIndex: UInt32
        let nextSequence: UInt64
        let pointCount: Int
    }

    private static func validateDraft(
        _ chunks: [RideRouteChunk],
        sessionID: UUID
    ) throws -> DraftState {
        guard !chunks.isEmpty else {
            return DraftState(
                lastSegmentIndex: nil,
                nextChunkIndex: 0,
                nextSequence: 0,
                pointCount: 0
            )
        }

        let ordered = chunks.sorted { lhs, rhs in
            if lhs.id.segmentIndex != rhs.id.segmentIndex {
                return lhs.id.segmentIndex < rhs.id.segmentIndex
            }
            return lhs.id.chunkIndex < rhs.id.chunkIndex
        }

        var expectedSegment: UInt32 = 0
        var expectedChunk: UInt32 = 0
        var currentSegment: UInt32?
        var previousSequence: UInt64?
        var pointCount = 0

        for chunk in ordered {
            guard chunk.id.sessionID == sessionID else {
                throw RideRouteRecorderError.corruptDraft(sessionID)
            }
            if currentSegment != chunk.id.segmentIndex {
                guard chunk.id.segmentIndex == expectedSegment else {
                    throw RideRouteRecorderError.corruptDraft(sessionID)
                }
                currentSegment = chunk.id.segmentIndex
                expectedChunk = 0
                guard expectedSegment < UInt32.max else {
                    throw RideRouteRecorderError.corruptDraft(sessionID)
                }
                expectedSegment += 1
            }
            guard chunk.id.chunkIndex == expectedChunk else {
                throw RideRouteRecorderError.corruptDraft(sessionID)
            }
            guard expectedChunk < UInt32.max else {
                throw RideRouteRecorderError.corruptDraft(sessionID)
            }
            expectedChunk += 1

            for point in chunk.points {
                if let previousSequence, point.sequence <= previousSequence {
                    throw RideRouteRecorderError.corruptDraft(sessionID)
                }
                previousSequence = point.sequence
                pointCount += 1
            }
        }

        guard let lastSegmentIndex = currentSegment,
              let lastSequence = previousSequence,
              lastSequence < UInt64.max else {
            throw RideRouteRecorderError.corruptDraft(sessionID)
        }
        return DraftState(
            lastSegmentIndex: lastSegmentIndex,
            nextChunkIndex: expectedChunk,
            nextSequence: lastSequence + 1,
            pointCount: pointCount
        )
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

enum RideRoutePresentationStatus: Equatable, Sendable {
    case idle
    case loading
    case ready
    case unavailable
    case failed
}

@MainActor
@Observable
final class RideRoutePresentationStore {
    private(set) var revision = 0

    @ObservationIgnored private let routeStore: SwiftDataRideRouteStore?
    @ObservationIgnored private let startupPersistenceError: String?
    @ObservationIgnored private var geometries: [UUID: RideRouteGeometry] = [:]
    @ObservationIgnored private var statuses: [UUID: RideRoutePresentationStatus] = [:]
    @ObservationIgnored private var errors: [UUID: String] = [:]

    init(
        routeStore: SwiftDataRideRouteStore?,
        startupPersistenceError: String? = nil
    ) {
        self.routeStore = routeStore
        self.startupPersistenceError = startupPersistenceError
    }

    func geometry(sessionID: UUID) -> RideRouteGeometry? {
        _ = revision
        return geometries[sessionID]
    }

    func status(sessionID: UUID) -> RideRoutePresentationStatus {
        _ = revision
        return statuses[sessionID] ?? .idle
    }

    func errorMessage(sessionID: UUID) -> String? {
        _ = revision
        return errors[sessionID]
    }

    func refresh(sessionID: UUID) async {
        guard let routeStore else {
            geometries.removeValue(forKey: sessionID)
            statuses[sessionID] = .unavailable
            errors[sessionID] = startupPersistenceError ?? "Local route storage is unavailable."
            revision &+= 1
            return
        }

        statuses[sessionID] = .loading
        revision &+= 1
        do {
            if let geometry = try await routeStore.geometry(sessionID: sessionID),
               geometry.hasRecordedGeometry {
                geometries[sessionID] = geometry
                statuses[sessionID] = .ready
                errors.removeValue(forKey: sessionID)
            } else {
                geometries.removeValue(forKey: sessionID)
                statuses[sessionID] = .unavailable
                errors.removeValue(forKey: sessionID)
            }
        } catch {
            geometries.removeValue(forKey: sessionID)
            statuses[sessionID] = .failed
            errors[sessionID] = "Stored route geometry could not be verified safely."
        }
        revision &+= 1
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
    let routeStore: SwiftDataRideRouteStore?
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

        // Route geometry is an additive evidence domain. A route-store startup
        // failure must not disable the already accepted recovery/history ledger.
        // Presentation can truthfully show route unavailable while ride history
        // remains readable and automatic ride recovery remains intact.
        let routeStore: SwiftDataRideRouteStore?
        do {
            let routesURL = scopeDirectory.appendingPathComponent("RideRoutes.store")
            let routesContainer = try makeRouteContainer(storeURL: routesURL)
            routeStore = SwiftDataRideRouteStore(modelContainer: routesContainer)
        } catch {
            routeStore = nil
        }

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
