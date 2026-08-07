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
/// termination. Monotonic uptime is intentionally absent: it is boot-relative
/// transient timing evidence, and a durable checkpoint cannot prove that a later
/// process shares the same uptime domain.
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
    /// Durable transport-continuity provenance accumulated before this
    /// checkpoint. A legacy checkpoint without this field decodes as unknown.
    public let transportGapEvidence: RideTransportGapEvidence

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
        accumulatedGPSDistanceMeters: Double,
        transportGapEvidence: RideTransportGapEvidence = .unknown
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
        case .temporarilyDisconnected:
            guard phaseBeganAtDate != nil,
                  transportGapEvidence != .noneObserved else {
                // A current-process temporary-disconnect phase is direct gap
                // evidence. Recovery-created disconnected phases are persisted
                // with `.unknown`, never with an unqualified no-gap claim.
                throw RideCheckpointError.invalidCheckpoint
            }
        case .endingCandidate:
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
        self.transportGapEvidence = transportGapEvidence
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
        case transportGapEvidence
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
                accumulatedGPSDistanceMeters: container.decode(Double.self, forKey: .accumulatedGPSDistanceMeters),
                transportGapEvidence: try container.decodeIfPresent(
                    RideTransportGapEvidence.self,
                    forKey: .transportGapEvidence
                ) ?? .unknown
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
            try container.encode(Kind.completedPendingCommit, forKey: .completedPendingCommit)
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
    /// v2 adds explicit ride transport-gap provenance. v1 is still readable so
    /// an existing in-progress ride can recover, but every subsequent write is
    /// v2. Older apps will reject v2 instead of silently erasing the new meaning.
    static let schemaVersion = 2
    static let legacySchemaVersion = 1
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

    private struct DecodedEnvelope<Checkpoint: Decodable>: Decodable {
        let schemaVersion: Int
        let generation: UInt64
        let checkpoint: Checkpoint
    }

    private enum JournalCheckpointKind: String, Decodable {
        case inProgress
        case completedPendingCommit
    }

    private enum JournalCheckpointCodingKeys: String, CodingKey {
        case kind
        case inProgress
        case completedPendingCommit
    }

    private enum RecoveryCodingKeys: String, CodingKey {
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
        case transportGapEvidence
    }

    private struct RecoveryFields {
        let sessionID: UUID
        let beganAtDate: Date
        let confirmedAtDate: Date
        let persistedPhase: RideCheckpointPhase
        let phaseBeganAtDate: Date?
        let lastObservedAtDate: Date
        let checkpointedAtDate: Date
        let startingOdometerKilometers: Double?
        let latestOdometerKilometers: Double?
        let accumulatedGPSDistanceMeters: Double

        init(container: KeyedDecodingContainer<RecoveryCodingKeys>) throws {
            self.sessionID = try container.decode(UUID.self, forKey: .sessionID)
            self.beganAtDate = try container.decode(Date.self, forKey: .beganAtDate)
            self.confirmedAtDate = try container.decode(Date.self, forKey: .confirmedAtDate)
            self.persistedPhase = try container.decode(RideCheckpointPhase.self, forKey: .persistedPhase)
            self.phaseBeganAtDate = try container.decodeIfPresent(Date.self, forKey: .phaseBeganAtDate)
            self.lastObservedAtDate = try container.decode(Date.self, forKey: .lastObservedAtDate)
            self.checkpointedAtDate = try container.decode(Date.self, forKey: .checkpointedAtDate)
            self.startingOdometerKilometers = try container.decodeIfPresent(
                Double.self,
                forKey: .startingOdometerKilometers
            )
            self.latestOdometerKilometers = try container.decodeIfPresent(
                Double.self,
                forKey: .latestOdometerKilometers
            )
            self.accumulatedGPSDistanceMeters = try container.decode(
                Double.self,
                forKey: .accumulatedGPSDistanceMeters
            )
        }

        func domain(
            transportGapEvidence: RideTransportGapEvidence
        ) throws -> RideRecoveryCheckpoint {
            try RideRecoveryCheckpoint(
                sessionID: sessionID,
                beganAtDate: beganAtDate,
                confirmedAtDate: confirmedAtDate,
                persistedPhase: persistedPhase,
                phaseBeganAtDate: phaseBeganAtDate,
                lastObservedAtDate: lastObservedAtDate,
                checkpointedAtDate: checkpointedAtDate,
                startingOdometerKilometers: startingOdometerKilometers,
                latestOdometerKilometers: latestOdometerKilometers,
                accumulatedGPSDistanceMeters: accumulatedGPSDistanceMeters,
                transportGapEvidence: transportGapEvidence
            )
        }
    }

    private struct CurrentRideRecoveryCheckpoint: Decodable {
        let value: RideRecoveryCheckpoint

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: RecoveryCodingKeys.self)
            let fields = try RecoveryFields(container: container)
            let transportGapEvidence = try container.decode(
                RideTransportGapEvidence.self,
                forKey: .transportGapEvidence
            )
            self.value = try fields.domain(transportGapEvidence: transportGapEvidence)
        }
    }

    private struct LegacyRideRecoveryCheckpoint: Decodable {
        let value: RideRecoveryCheckpoint

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: RecoveryCodingKeys.self)
            let fields = try RecoveryFields(container: container)
            self.value = try fields.domain(transportGapEvidence: .unknown)
        }
    }

    private enum CompletedCodingKeys: String, CodingKey {
        case sessionID
        case beganAtDate
        case confirmedAtDate
        case endedAtDate
        case startingOdometerKilometers
        case endingOdometerKilometers
        case qualityScreenedGPSDistanceMeters
        case continuity
        case transportGapEvidence
    }

    private struct CompletedFields {
        let sessionID: UUID
        let beganAtDate: Date
        let confirmedAtDate: Date
        let endedAtDate: Date
        let startingOdometerKilometers: Double?
        let endingOdometerKilometers: Double?
        let qualityScreenedGPSDistanceMeters: Double
        let continuity: RideSessionContinuity

        init(container: KeyedDecodingContainer<CompletedCodingKeys>) throws {
            self.sessionID = try container.decode(UUID.self, forKey: .sessionID)
            self.beganAtDate = try container.decode(Date.self, forKey: .beganAtDate)
            self.confirmedAtDate = try container.decode(Date.self, forKey: .confirmedAtDate)
            self.endedAtDate = try container.decode(Date.self, forKey: .endedAtDate)
            self.startingOdometerKilometers = try container.decodeIfPresent(
                Double.self,
                forKey: .startingOdometerKilometers
            )
            self.endingOdometerKilometers = try container.decodeIfPresent(
                Double.self,
                forKey: .endingOdometerKilometers
            )
            self.qualityScreenedGPSDistanceMeters = try container.decode(
                Double.self,
                forKey: .qualityScreenedGPSDistanceMeters
            )
            self.continuity = try container.decode(RideSessionContinuity.self, forKey: .continuity)
        }

        func domain(
            transportGapEvidence: RideTransportGapEvidence
        ) throws -> CompletedRideEvidence {
            try CompletedRideEvidence(
                sessionID: sessionID,
                beganAtDate: beganAtDate,
                confirmedAtDate: confirmedAtDate,
                endedAtDate: endedAtDate,
                startingOdometerKilometers: startingOdometerKilometers,
                endingOdometerKilometers: endingOdometerKilometers,
                qualityScreenedGPSDistanceMeters: qualityScreenedGPSDistanceMeters,
                continuity: continuity,
                transportGapEvidence: transportGapEvidence
            )
        }
    }

    private struct CurrentCompletedRideEvidence: Decodable {
        let value: CompletedRideEvidence

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CompletedCodingKeys.self)
            let fields = try CompletedFields(container: container)
            let transportGapEvidence = try container.decode(
                RideTransportGapEvidence.self,
                forKey: .transportGapEvidence
            )
            self.value = try fields.domain(transportGapEvidence: transportGapEvidence)
        }
    }

    private struct LegacyCompletedRideEvidence: Decodable {
        let value: CompletedRideEvidence

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CompletedCodingKeys.self)
            let fields = try CompletedFields(container: container)
            self.value = try fields.domain(transportGapEvidence: .unknown)
        }
    }

    private enum CurrentDurableCheckpoint: Decodable {
        case inProgress(RideRecoveryCheckpoint)
        case completedPendingCommit(CompletedRideEvidence)

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: JournalCheckpointCodingKeys.self)
            switch try container.decode(JournalCheckpointKind.self, forKey: .kind) {
            case .inProgress:
                self = .inProgress(
                    try container.decode(CurrentRideRecoveryCheckpoint.self, forKey: .inProgress).value
                )
            case .completedPendingCommit:
                self = .completedPendingCommit(
                    try container.decode(
                        CurrentCompletedRideEvidence.self,
                        forKey: .completedPendingCommit
                    ).value
                )
            }
        }

        var value: RideDurableCheckpoint {
            switch self {
            case let .inProgress(checkpoint):
                return .inProgress(checkpoint)
            case let .completedPendingCommit(evidence):
                return .completedPendingCommit(evidence)
            }
        }
    }

    private enum LegacyDurableCheckpoint: Decodable {
        case inProgress(RideRecoveryCheckpoint)
        case completedPendingCommit(CompletedRideEvidence)

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: JournalCheckpointCodingKeys.self)
            switch try container.decode(JournalCheckpointKind.self, forKey: .kind) {
            case .inProgress:
                self = .inProgress(
                    try container.decode(LegacyRideRecoveryCheckpoint.self, forKey: .inProgress).value
                )
            case .completedPendingCommit:
                self = .completedPendingCommit(
                    try container.decode(
                        LegacyCompletedRideEvidence.self,
                        forKey: .completedPendingCommit
                    ).value
                )
            }
        }

        var value: RideDurableCheckpoint {
            switch self {
            case let .inProgress(checkpoint):
                return .inProgress(checkpoint)
            case let .completedPendingCommit(evidence):
                return .completedPendingCommit(evidence)
            }
        }
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
        let a = try readSlot(at: slotAURL)
        let b = try readSlot(at: slotBURL)
        try rejectUnsupportedSchema(a, b)
        try rejectConflictingGenerations(a, b)

        let slots: [(url: URL, read: SlotRead)] = [
            (slotAURL, a),
            (slotBURL, b),
        ]
        let validSlots: [(url: URL, envelope: Envelope)] = slots.compactMap { slot in
            guard let envelope = slot.read.envelope else { return nil }
            return (slot.url, envelope)
        }

        guard let newest = validSlots.max(by: {
            $0.envelope.generation < $1.envelope.generation
        }) else {
            // `clear()` is the explicit recovery path when no valid generation
            // survives. Unsupported schemas and conflicting valid generations
            // have already failed closed above.
            for slot in slots where fileManager.fileExists(atPath: slot.url.path) {
                try fileManager.removeItem(at: slot.url)
            }
            return
        }

        // Remove every non-authoritative fallback before the newest valid
        // generation. If deletion is interrupted, restart can still recover only
        // the newest checkpoint; an older in-progress ride can never be exposed
        // merely because completion acknowledgement partially cleared the journal.
        for slot in slots
            where slot.url != newest.url
            && fileManager.fileExists(atPath: slot.url.path) {
            try fileManager.removeItem(at: slot.url)
        }

        if fileManager.fileExists(atPath: newest.url.path) {
            try fileManager.removeItem(at: newest.url)
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
            switch probe.schemaVersion {
            case Self.schemaVersion:
                // The same JSONDecoder path that accepts the current journal also
                // requires non-null, valid transport provenance. There is no
                // JSONSerialization preflight whose duplicate-key semantics can
                // disagree with the authoritative decode.
                let current = try decoder.decode(
                    DecodedEnvelope<CurrentDurableCheckpoint>.self,
                    from: data
                )
                guard current.schemaVersion == Self.schemaVersion else {
                    return .corrupt
                }
                return .valid(
                    Envelope(
                        schemaVersion: Self.schemaVersion,
                        generation: current.generation,
                        checkpoint: current.checkpoint.value
                    )
                )

            case Self.legacySchemaVersion:
                // Schema v1 predates transport provenance. The legacy DTO never
                // decodes that key, so even an injected current-era field cannot
                // self-assert a v2 claim; migration always supplies `.unknown`.
                let legacy = try decoder.decode(
                    DecodedEnvelope<LegacyDurableCheckpoint>.self,
                    from: data
                )
                guard legacy.schemaVersion == Self.legacySchemaVersion else {
                    return .corrupt
                }
                return .valid(
                    Envelope(
                        schemaVersion: Self.schemaVersion,
                        generation: legacy.generation,
                        checkpoint: legacy.checkpoint.value
                    )
                )

            default:
                return .unsupported(probe.schemaVersion)
            }
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
