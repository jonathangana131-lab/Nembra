import Foundation

public enum RideCheckpointError: Error, Equatable, Sendable {
    case invalidCheckpoint
    case corruptedCheckpoint
    case conflictingGenerations
    case unsupportedSchema(Int)
    case generationOverflow
}

public enum RideCheckpointPhase: String, Codable, Equatable, Sendable {
    case active
    case temporarilyDisconnected
    case endingCandidate
}

/// Durable, compact evidence needed to recover one confirmed ride after process
/// termination. Monotonic uptime is intentionally absent: uptime belongs to one
/// process/boot epoch and must never be treated as durable wall-clock history.
public struct RideRecoveryCheckpoint: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let beganAtDate: Date
    public let confirmedAtDate: Date
    public let persistedPhase: RideCheckpointPhase
    public let phaseBeganAtDate: Date?
    public let lastObservedAtDate: Date
    public let checkpointedAtDate: Date
    public let startingOdometerKilometers: Double?
    public let latestOdometerKilometers: Double?
    public let accumulatedGPSDistanceMeters: Double

    public init(
        sessionID: UUID,
        beganAtDate: Date,
        confirmedAtDate: Date,
        persistedPhase: RideCheckpointPhase,
        phaseBeganAtDate: Date?,
        lastObservedAtDate: Date,
        checkpointedAtDate: Date,
        startingOdometerKilometers: Double?,
        latestOdometerKilometers: Double?,
        accumulatedGPSDistanceMeters: Double
    ) throws {
        guard beganAtDate.timeIntervalSinceReferenceDate.isFinite,
              confirmedAtDate.timeIntervalSinceReferenceDate.isFinite,
              lastObservedAtDate.timeIntervalSinceReferenceDate.isFinite,
              checkpointedAtDate.timeIntervalSinceReferenceDate.isFinite,
              phaseBeganAtDate?.timeIntervalSinceReferenceDate.isFinite ?? true,
              accumulatedGPSDistanceMeters.isFinite,
              accumulatedGPSDistanceMeters >= 0 else {
            throw RideCheckpointError.invalidCheckpoint
        }

        switch persistedPhase {
        case .active:
            guard phaseBeganAtDate == nil else {
                throw RideCheckpointError.invalidCheckpoint
            }
        case .temporarilyDisconnected, .endingCandidate:
            guard phaseBeganAtDate != nil else {
                throw RideCheckpointError.invalidCheckpoint
            }
        }

        switch (startingOdometerKilometers, latestOdometerKilometers) {
        case (nil, nil):
            break
        case let (.some(start), .some(latest)):
            guard start.isFinite,
                  start >= 0,
                  latest.isFinite,
                  latest >= start else {
                throw RideCheckpointError.invalidCheckpoint
            }
        default:
            // The engine establishes start/latest together at the first real ODO
            // observation. Persisting only one endpoint would invent an invariant
            // that a recovery path cannot interpret safely.
            throw RideCheckpointError.invalidCheckpoint
        }

        self.sessionID = sessionID
        self.beganAtDate = beganAtDate
        self.confirmedAtDate = confirmedAtDate
        self.persistedPhase = persistedPhase
        self.phaseBeganAtDate = phaseBeganAtDate
        self.lastObservedAtDate = lastObservedAtDate
        self.checkpointedAtDate = checkpointedAtDate
        self.startingOdometerKilometers = startingOdometerKilometers
        self.latestOdometerKilometers = latestOdometerKilometers
        self.accumulatedGPSDistanceMeters = accumulatedGPSDistanceMeters
    }

    private enum CodingKeys: String, CodingKey {
        case sessionID
        case beganAtDate
        case confirmedAtDate
        case persistedPhase
        case phaseBeganAtDate
        case lastObservedAtDate
        case checkpointedAtDate
        case startingOdometerKilometers
        case latestOdometerKilometers
        case accumulatedGPSDistanceMeters
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                sessionID: container.decode(UUID.self, forKey: .sessionID),
                beganAtDate: container.decode(Date.self, forKey: .beganAtDate),
                confirmedAtDate: container.decode(Date.self, forKey: .confirmedAtDate),
                persistedPhase: container.decode(RideCheckpointPhase.self, forKey: .persistedPhase),
                phaseBeganAtDate: container.decodeIfPresent(Date.self, forKey: .phaseBeganAtDate),
                lastObservedAtDate: container.decode(Date.self, forKey: .lastObservedAtDate),
                checkpointedAtDate: container.decode(Date.self, forKey: .checkpointedAtDate),
                startingOdometerKilometers: container.decodeIfPresent(Double.self, forKey: .startingOdometerKilometers),
                latestOdometerKilometers: container.decodeIfPresent(Double.self, forKey: .latestOdometerKilometers),
                accumulatedGPSDistanceMeters: container.decode(Double.self, forKey: .accumulatedGPSDistanceMeters)
            )
        } catch RideCheckpointError.invalidCheckpoint {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Ride checkpoint contains invalid durable evidence."
                )
            )
        }
    }
}

public enum RideDurableCheckpoint: Codable, Equatable, Sendable {
    case inProgress(RideRecoveryCheckpoint)
    case completedPendingCommit(CompletedRideEvidence)

    private enum Kind: String, Codable {
        case inProgress
        case completedPendingCommit
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case inProgress
        case completedPendingCommit
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .inProgress:
            self = .inProgress(
                try container.decode(RideRecoveryCheckpoint.self, forKey: .inProgress)
            )
        case .completedPendingCommit:
            self = .completedPendingCommit(
                try container.decode(CompletedRideEvidence.self, forKey: .completedPendingCommit)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .inProgress(checkpoint):
            try container.encode(Kind.inProgress, forKey: .kind)
            try container.encode(checkpoint, forKey: .inProgress)
        case let .completedPendingCommit(evidence):
            try container.encode(Kind.completedPendingCommit, forKey: .kind)
            try container.encode(evidence, forKey: .completedPendingCommit)
        }
    }
}

public protocol RideCheckpointStore: Sendable {
    func save(_ checkpoint: RideDurableCheckpoint) async throws
    func load() async throws -> RideDurableCheckpoint?
    func clear() async throws
}

/// Two-slot atomic journal for compact ride recovery and completion-handoff evidence.
///
/// Each save writes a new generation to the older/unused slot with Foundation's
/// atomic file replacement. The other slot remains a previous known-good copy,
/// so a truncated/corrupt newest write can fall back without erasing the ride.
/// This is intentionally separate from the later completed-ride SwiftData ledger.
///
/// This design protects against ordinary process interruption and partial/corrupt
/// checkpoint files. It does not claim a stronger power-loss durability guarantee
/// than the underlying filesystem/Foundation atomic-write semantics provide.
public actor AtomicRideCheckpointStore: RideCheckpointStore {
    static let schemaVersion = 1
    static let slotAFileName = "ride-journal-a.json"
    static let slotBFileName = "ride-journal-b.json"

    private struct SchemaProbe: Decodable {
        let schemaVersion: Int
    }

    struct Envelope: Codable, Equatable, Sendable {
        let schemaVersion: Int
        let generation: UInt64
        let checkpoint: RideDurableCheckpoint
    }

    private enum SlotRead {
        case missing
        case valid(Envelope)
        case corrupt
        case unsupported(Int)

        var envelope: Envelope? {
            guard case let .valid(envelope) = self else { return nil }
            return envelope
        }

        var isCorrupt: Bool {
            if case .corrupt = self { return true }
            return false
        }
    }

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

    public func save(_ checkpoint: RideDurableCheckpoint) async throws {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let a = try readSlot(at: slotAURL)
        let b = try readSlot(at: slotBURL)
        try rejectUnsupportedSchema(a, b)
        try rejectConflictingGenerations(a, b)

        let valid = [a, b].compactMap(\.envelope)
        if valid.isEmpty, a.isCorrupt, b.isCorrupt {
            // With both copies unreadable there is no safe way to decide what
            // generation/evidence would be overwritten. Explicit clear/recovery
            // is required instead of silently erasing both forensic copies.
            throw RideCheckpointError.corruptedCheckpoint
        }

        let highestGeneration = valid.map(\.generation).max() ?? 0
        guard highestGeneration < UInt64.max else {
            throw RideCheckpointError.generationOverflow
        }
        let envelope = Envelope(
            schemaVersion: Self.schemaVersion,
            generation: highestGeneration + 1,
            checkpoint: checkpoint
        )

        let destination = destinationURL(slotA: a, slotB: b)
        let data = try encoder.encode(envelope)
        try data.write(to: destination, options: Data.WritingOptions.atomic)

        // Small synchronous verification is deliberate. A checkpoint cadence
        // layer must prevent high-frequency writes; when a durable write is
        // requested, immediately verify that the new slot is decodable before
        // reporting success. The other slot remains the fallback.
        guard case let .valid(verified) = try readSlot(at: destination),
              verified == envelope else {
            throw RideCheckpointError.corruptedCheckpoint
        }
    }

    public func load() async throws -> RideDurableCheckpoint? {
        let a = try readSlot(at: slotAURL)
        let b = try readSlot(at: slotBURL)
        try rejectUnsupportedSchema(a, b)
        try rejectConflictingGenerations(a, b)

        let valid = [a, b].compactMap(\.envelope)
        if let newest = valid.max(by: { $0.generation < $1.generation }) {
            return newest.checkpoint
        }

        if a.isCorrupt || b.isCorrupt {
            throw RideCheckpointError.corruptedCheckpoint
        }
        return nil
    }

    public func clear() async throws {
        for url in [slotAURL, slotBURL] where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private var slotAURL: URL {
        directoryURL.appendingPathComponent(Self.slotAFileName, isDirectory: false)
    }

    private var slotBURL: URL {
        directoryURL.appendingPathComponent(Self.slotBFileName, isDirectory: false)
    }

    private func readSlot(at url: URL) throws -> SlotRead {
        guard fileManager.fileExists(atPath: url.path) else {
            return .missing
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return .corrupt
        }

        do {
            let probe = try decoder.decode(SchemaProbe.self, from: data)
            guard probe.schemaVersion == Self.schemaVersion else {
                return .unsupported(probe.schemaVersion)
            }
            return .valid(try decoder.decode(Envelope.self, from: data))
        } catch {
            return .corrupt
        }
    }

    private func rejectUnsupportedSchema(_ slots: SlotRead...) throws {
        for slot in slots {
            if case let .unsupported(version) = slot {
                // A newer/older app may own the freshest valid checkpoint. Never
                // silently overwrite or downgrade it.
                throw RideCheckpointError.unsupportedSchema(version)
            }
        }
    }

    private func rejectConflictingGenerations(_ slotA: SlotRead, _ slotB: SlotRead) throws {
        guard let a = slotA.envelope,
              let b = slotB.envelope,
              a.generation == b.generation,
              a != b else {
            return
        }
        throw RideCheckpointError.conflictingGenerations
    }

    private func destinationURL(slotA: SlotRead, slotB: SlotRead) -> URL {
        switch (slotA, slotB) {
        case (.corrupt, .missing):
            // Preserve the corrupt copy for diagnostics and recover into the
            // unused slot rather than destroying the only forensic evidence.
            return slotBURL
        case (.missing, .corrupt):
            return slotAURL
        default:
            break
        }

        switch (slotA.envelope, slotB.envelope) {
        case (nil, _):
            return slotAURL
        case (_, nil):
            return slotBURL
        case let (.some(a), .some(b)):
            return a.generation <= b.generation ? slotAURL : slotBURL
        }
    }
}
