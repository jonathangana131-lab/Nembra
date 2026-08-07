import Foundation

public enum ObservedPowerEnvelopeCheckpointStoreError: Error, Equatable, Sendable {
    case corruptedCheckpoint
    case conflictingGenerations
    case unsupportedSchema(Int)
    case unsupportedCheckpointSchema(Int)
    case generationOverflow
    case scopeMismatch
    case policyMismatch
    case authorityMismatch
    case invalidCalibrationProgression
    case reconciliationThresholdOverflow
}

public enum ObservedPowerEnvelopeCheckpointSaveResult: Equatable, Sendable {
    case stored(generation: UInt64)
    case retainedExisting
}

public protocol ObservedPowerEnvelopeCheckpointStore: Sendable {
    @discardableResult
    func save(
        _ checkpoint: ObservedPowerEnvelopeCalibrationCheckpoint
    ) async throws -> ObservedPowerEnvelopeCheckpointSaveResult

    func load() async throws -> ObservedPowerEnvelopeCalibrationCheckpoint?
    func clear() async throws
}

/// Two-slot atomic journal for one exact observed-power calibration scope/policy.
///
/// The checkpoint itself owns semantic validation and physical-vs-Simulator
/// authority. This store adds crash tolerance and durable monotonicity only:
/// it never reconstructs live telemetry, receipt chronology, rolling samples, or
/// display frames.
///
/// A directory becomes bound to the first valid checkpoint written there. A
/// different vehicle/mode, authority pair, or learning policy requires an
/// explicit clear/new directory instead of silently overwriting retained history.
/// Qualified stronger calibrations may advance according to the exact persisted
/// upward-hysteresis policy. Equal, lower, or sub-hysteresis candidates are a
/// successful no-op so callers cannot accidentally shrink the learned gauge scale.
public actor AtomicObservedPowerEnvelopeCheckpointStore: ObservedPowerEnvelopeCheckpointStore {
    static let schemaVersion = 1
    static let slotAFileName = "observed-power-envelope-journal-a.json"
    static let slotBFileName = "observed-power-envelope-journal-b.json"

    private struct StoreSchemaProbe: Decodable {
        let schemaVersion: Int
    }

    private struct CheckpointSchemaProbe: Decodable {
        struct Checkpoint: Decodable {
            let schemaVersion: Int
        }

        let checkpoint: Checkpoint
    }

    struct Envelope: Codable, Equatable, Sendable {
        let schemaVersion: Int
        let generation: UInt64
        let checkpoint: ObservedPowerEnvelopeCalibrationCheckpoint
    }

    private enum SlotRead {
        case missing
        case valid(Envelope)
        case corrupt
        case unsupportedStoreSchema(Int)
        case unsupportedCheckpointSchema(Int)

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

    @discardableResult
    public func save(
        _ checkpoint: ObservedPowerEnvelopeCalibrationCheckpoint
    ) async throws -> ObservedPowerEnvelopeCheckpointSaveResult {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let a = try readSlot(at: slotAURL)
        let b = try readSlot(at: slotBURL)
        try rejectUnsupportedSchema(a, b)
        try rejectConflictingGenerations(a, b)

        let valid = [a, b].compactMap(\.envelope)
        try validateJournalProgression(valid)

        if valid.isEmpty, a.isCorrupt, b.isCorrupt {
            // No trustworthy generation or calibration survives. Preserve both
            // forensic copies until an explicit clear/recovery decision.
            throw ObservedPowerEnvelopeCheckpointStoreError.corruptedCheckpoint
        }

        let newest = valid.max(by: { $0.generation < $1.generation })
        if let newest {
            switch try replacementDecision(existing: newest.checkpoint, incoming: checkpoint) {
            case .retainExisting:
                return .retainedExisting
            case .storeIncoming:
                break
            }
        }

        let highestGeneration = newest?.generation ?? 0
        guard highestGeneration < UInt64.max else {
            throw ObservedPowerEnvelopeCheckpointStoreError.generationOverflow
        }
        let generation = highestGeneration + 1
        let envelope = Envelope(
            schemaVersion: Self.schemaVersion,
            generation: generation,
            checkpoint: checkpoint
        )

        let destination = destinationURL(slotA: a, slotB: b)
        let data = try encoder.encode(envelope)
        try data.write(to: destination, options: Data.WritingOptions.atomic)

        // Calibration writes should be infrequent. Verify the newly written slot
        // synchronously before reporting success; the other slot remains fallback.
        guard case let .valid(verified) = try readSlot(at: destination),
              verified == envelope else {
            throw ObservedPowerEnvelopeCheckpointStoreError.corruptedCheckpoint
        }

        return .stored(generation: generation)
    }

    public func load() async throws -> ObservedPowerEnvelopeCalibrationCheckpoint? {
        let a = try readSlot(at: slotAURL)
        let b = try readSlot(at: slotBURL)
        try rejectUnsupportedSchema(a, b)
        try rejectConflictingGenerations(a, b)

        let valid = [a, b].compactMap(\.envelope)
        try validateJournalProgression(valid)
        if let newest = valid.max(by: { $0.generation < $1.generation }) {
            return newest.checkpoint
        }

        if a.isCorrupt || b.isCorrupt {
            throw ObservedPowerEnvelopeCheckpointStoreError.corruptedCheckpoint
        }
        return nil
    }

    public func clear() async throws {
        for url in [slotAURL, slotBURL] where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private enum ReplacementDecision {
        case retainExisting
        case storeIncoming
    }

    private func replacementDecision(
        existing: ObservedPowerEnvelopeCalibrationCheckpoint,
        incoming: ObservedPowerEnvelopeCalibrationCheckpoint
    ) throws -> ReplacementDecision {
        try validateSameBinding(existing, incoming)

        if incoming == existing {
            return .retainExisting
        }

        let requiredRaisedCeiling = existing.learnedObservedCeilingWatts
            * (1 + existing.policy.upwardHysteresisFraction)
        guard requiredRaisedCeiling.isFinite else {
            throw ObservedPowerEnvelopeCheckpointStoreError.reconciliationThresholdOverflow
        }

        guard incoming.learnedObservedCeilingWatts > requiredRaisedCeiling else {
            return .retainExisting
        }
        return .storeIncoming
    }

    private func validateSameBinding(
        _ lhs: ObservedPowerEnvelopeCalibrationCheckpoint,
        _ rhs: ObservedPowerEnvelopeCalibrationCheckpoint
    ) throws {
        guard lhs.vehicleIdentityKey == rhs.vehicleIdentityKey,
              lhs.confirmedModeKey == rhs.confirmedModeKey else {
            throw ObservedPowerEnvelopeCheckpointStoreError.scopeMismatch
        }
        guard lhs.identityAuthority == rhs.identityAuthority,
              lhs.evidenceAuthority == rhs.evidenceAuthority else {
            throw ObservedPowerEnvelopeCheckpointStoreError.authorityMismatch
        }
        guard lhs.policy == rhs.policy else {
            throw ObservedPowerEnvelopeCheckpointStoreError.policyMismatch
        }
    }

    private func validateJournalProgression(_ envelopes: [Envelope]) throws {
        guard envelopes.count == 2 else { return }
        let ordered = envelopes.sorted { $0.generation < $1.generation }
        let older = ordered[0]
        let newer = ordered[1]
        try validateSameBinding(older.checkpoint, newer.checkpoint)

        if older.checkpoint == newer.checkpoint {
            return
        }

        let requiredRaisedCeiling = older.checkpoint.learnedObservedCeilingWatts
            * (1 + older.checkpoint.policy.upwardHysteresisFraction)
        guard requiredRaisedCeiling.isFinite else {
            throw ObservedPowerEnvelopeCheckpointStoreError.reconciliationThresholdOverflow
        }
        guard newer.checkpoint.learnedObservedCeilingWatts > requiredRaisedCeiling else {
            throw ObservedPowerEnvelopeCheckpointStoreError.invalidCalibrationProgression
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
            let storeProbe = try decoder.decode(StoreSchemaProbe.self, from: data)
            guard storeProbe.schemaVersion == Self.schemaVersion else {
                return .unsupportedStoreSchema(storeProbe.schemaVersion)
            }

            let checkpointProbe = try decoder.decode(CheckpointSchemaProbe.self, from: data)
            guard checkpointProbe.checkpoint.schemaVersion
                    == ObservedPowerEnvelopeCalibrationCheckpoint.currentSchemaVersion else {
                return .unsupportedCheckpointSchema(checkpointProbe.checkpoint.schemaVersion)
            }

            return .valid(try decoder.decode(Envelope.self, from: data))
        } catch {
            return .corrupt
        }
    }

    private func rejectUnsupportedSchema(_ slots: SlotRead...) throws {
        for slot in slots {
            switch slot {
            case let .unsupportedStoreSchema(version):
                throw ObservedPowerEnvelopeCheckpointStoreError.unsupportedSchema(version)
            case let .unsupportedCheckpointSchema(version):
                throw ObservedPowerEnvelopeCheckpointStoreError.unsupportedCheckpointSchema(version)
            default:
                break
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
        throw ObservedPowerEnvelopeCheckpointStoreError.conflictingGenerations
    }

    private func destinationURL(slotA: SlotRead, slotB: SlotRead) -> URL {
        switch (slotA, slotB) {
        case (.corrupt, .missing):
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
