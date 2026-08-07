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
    /// Public durable writes are deliberately Simulator/runtime-QA only.
    @discardableResult
    func saveSimulatorQA(
        _ checkpoint: ObservedPowerEnvelopeCalibrationCheckpoint
    ) async throws -> ObservedPowerEnvelopeCheckpointSaveResult

    /// Public durable reads are likewise Simulator/runtime-QA only. Verified
    /// physical import is package-sealed on the concrete store.
    func loadSimulatorQA() async throws -> ObservedPowerEnvelopeCalibrationCheckpoint?

    /// Logically clears retained calibration using a monotonic tombstone barrier.
    func clear() async throws
}

/// Two-slot atomic journal for one exact observed-power calibration scope/policy.
///
/// Disk bytes first decode into `StoredCheckpointWire`, which carries no trusted
/// physical provenance. Simulator wire records may enter the public checkpoint
/// decoder; verified wire records may become authority-bearing checkpoints only
/// through the package-sealed conversion in `ObservedPowerEnvelopePersistence`.
///
/// `clear()` is monotonic: it atomically writes a newer clear tombstone before a
/// second scrub tombstone replaces the surviving old slot. A crash after the first
/// write can therefore never resurrect a pre-clear checkpoint; the newer tombstone
/// wins, or an unsupported surviving record keeps the journal fail-closed until the
/// explicit clear is retried.
public actor AtomicObservedPowerEnvelopeCheckpointStore: ObservedPowerEnvelopeCheckpointStore {
    static let schemaVersion = 1
    static let slotAFileName = "observed-power-envelope-journal-a.json"
    static let slotBFileName = "observed-power-envelope-journal-b.json"

    enum RecordKind: String, Codable, Equatable, Sendable {
        case checkpoint
        case cleared
    }

    struct StoredCheckpointWire: Codable, Equatable, Sendable {
        let schemaVersion: Int
        let vehicleIdentityKey: String
        let confirmedModeKey: String?
        let identityAuthority: String
        let evidenceAuthority: String
        let policy: ObservedPowerEnvelopePolicyCheckpoint
        let learnedObservedCeilingWatts: Double
        let learningSampleCount: Int
        let upperBandSupportCount: Int

        init(_ checkpoint: ObservedPowerEnvelopeCalibrationCheckpoint) {
            schemaVersion = checkpoint.schemaVersion
            vehicleIdentityKey = checkpoint.vehicleIdentityKey
            confirmedModeKey = checkpoint.confirmedModeKey
            identityAuthority = checkpoint.identityAuthority.rawValue
            evidenceAuthority = checkpoint.evidenceAuthority.rawValue
            policy = checkpoint.policy
            learnedObservedCeilingWatts = checkpoint.learnedObservedCeilingWatts
            learningSampleCount = checkpoint.learningSampleCount
            upperBandSupportCount = checkpoint.upperBandSupportCount
        }
    }

    struct Envelope: Codable, Equatable, Sendable {
        let schemaVersion: Int
        let generation: UInt64
        let kind: RecordKind
        let checkpoint: StoredCheckpointWire?

        static func checkpoint(
            generation: UInt64,
            checkpoint: ObservedPowerEnvelopeCalibrationCheckpoint
        ) -> Self {
            Self(
                schemaVersion: AtomicObservedPowerEnvelopeCheckpointStore.schemaVersion,
                generation: generation,
                kind: .checkpoint,
                checkpoint: StoredCheckpointWire(checkpoint)
            )
        }

        static func checkpoint(
            generation: UInt64,
            wire: StoredCheckpointWire
        ) -> Self {
            Self(
                schemaVersion: AtomicObservedPowerEnvelopeCheckpointStore.schemaVersion,
                generation: generation,
                kind: .checkpoint,
                checkpoint: wire
            )
        }

        static func cleared(generation: UInt64) -> Self {
            Self(
                schemaVersion: AtomicObservedPowerEnvelopeCheckpointStore.schemaVersion,
                generation: generation,
                kind: .cleared,
                checkpoint: nil
            )
        }
    }

    private struct StoreSchemaProbe: Decodable {
        let schemaVersion: Int
    }

    private struct RecordProbe: Decodable {
        struct Checkpoint: Decodable {
            let schemaVersion: Int
        }

        let kind: RecordKind
        let checkpoint: Checkpoint?
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

        var isInvalidOrMissing: Bool {
            switch self {
            case .missing, .corrupt, .unsupportedStoreSchema, .unsupportedCheckpointSchema:
                true
            case .valid:
                false
            }
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
    public func saveSimulatorQA(
        _ checkpoint: ObservedPowerEnvelopeCalibrationCheckpoint
    ) async throws -> ObservedPowerEnvelopeCheckpointSaveResult {
        try saveValidated(
            checkpoint,
            requiredScopeAuthority: .simulatorQA,
            requiredEvidenceAuthority: .simulatorQA
        )
    }

    public func loadSimulatorQA() async throws -> ObservedPowerEnvelopeCalibrationCheckpoint? {
        guard let wire = try newestCheckpointWire() else { return nil }
        return try simulatorCheckpoint(from: wire)
    }

#if SWIFT_PACKAGE
    /// Trusted production persistence entry point. Taking the sealed learner rather
    /// than an arbitrary public checkpoint prevents ordinary JSON import from
    /// claiming verified physical provenance.
    @discardableResult
    package func saveVerifiedVehicleMeasurements(
        from learner: ObservedPowerEnvelopeLearner
    ) async throws -> ObservedPowerEnvelopeCheckpointSaveResult {
        let checkpoint = try ObservedPowerEnvelopeCalibrationCheckpoint
            .verifiedVehicleMeasurements(from: learner)
        return try saveValidated(
            checkpoint,
            requiredScopeAuthority: .verifiedVehicleIdentity,
            requiredEvidenceAuthority: .verifiedVehicleMeasurement
        )
    }

    /// Trusted physical restore performs wire decode + sealed checkpoint conversion
    /// + exact scope/policy validation as one package-only operation.
    package func loadVerifiedVehicleMeasurement(
        expectedScope: ObservedPowerEnvelopeScope,
        expectedPolicy: ObservedPowerEnvelopePolicy
    ) async throws -> ObservedPowerEnvelopeRestoredCalibration? {
        guard let wire = try newestCheckpointWire() else { return nil }
        let checkpoint = try verifiedCheckpoint(from: wire)
        return try checkpoint.restoredVerifiedVehicleMeasurement(
            expectedScope: expectedScope,
            expectedPolicy: expectedPolicy
        )
    }
#endif

    public func clear() async throws {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let a = try readSlot(at: slotAURL)
        let b = try readSlot(at: slotBURL)
        let valid = [a, b].compactMap(\.envelope)
        let highestKnownGeneration = valid.map(\.generation).max() ?? 0

        // Two durable writes are required to scrub both slots. Check the complete
        // generation budget before the first mutation so an overflow never leaves a
        // half-advanced clear sequence merely because phase two could not be numbered.
        guard highestKnownGeneration <= UInt64.max - 2 else {
            throw ObservedPowerEnvelopeCheckpointStoreError.generationOverflow
        }

        let firstURL = firstClearTarget(slotA: a, slotB: b)
        let secondURL = firstURL == slotAURL ? slotBURL : slotAURL

        // Phase 1 is the semantic commit point. It targets an invalid/missing slot
        // first when available, otherwise the older valid generation. Once this
        // atomic tombstone lands, any surviving recognized checkpoint is older.
        let barrier = Envelope.cleared(generation: highestKnownGeneration + 1)
        try writeAndVerify(barrier, to: firstURL)

        // Phase 2 scrubs the remaining slot with an even newer tombstone. A crash
        // before/during this write is still logically cleared because phase 1 wins;
        // if the survivor has an unsupported schema, normal load remains fail-closed.
        let scrub = Envelope.cleared(generation: highestKnownGeneration + 2)
        try writeAndVerify(scrub, to: secondURL)
    }

    private func newestCheckpointWire() throws -> StoredCheckpointWire? {
        let a = try readSlot(at: slotAURL)
        let b = try readSlot(at: slotBURL)
        try rejectUnsupportedSchema(a, b)
        try rejectConflictingGenerations(a, b)

        let valid = [a, b].compactMap(\.envelope)
        try validateJournalProgression(valid)

        if let newest = valid.max(by: { $0.generation < $1.generation }) {
            switch newest.kind {
            case .cleared:
                return nil
            case .checkpoint:
                guard let wire = newest.checkpoint else {
                    throw ObservedPowerEnvelopeCheckpointStoreError.corruptedCheckpoint
                }
                return wire
            }
        }

        if a.isCorrupt || b.isCorrupt {
            throw ObservedPowerEnvelopeCheckpointStoreError.corruptedCheckpoint
        }
        return nil
    }

    private func saveValidated(
        _ checkpoint: ObservedPowerEnvelopeCalibrationCheckpoint,
        requiredScopeAuthority: ObservedPowerEnvelopeScopeAuthority,
        requiredEvidenceAuthority: ObservedPowerEnvelopeEvidenceAuthority
    ) throws -> ObservedPowerEnvelopeCheckpointSaveResult {
        guard checkpoint.identityAuthority == requiredScopeAuthority,
              checkpoint.evidenceAuthority == requiredEvidenceAuthority else {
            throw ObservedPowerEnvelopeCheckpointStoreError.authorityMismatch
        }

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
            throw ObservedPowerEnvelopeCheckpointStoreError.corruptedCheckpoint
        }

        let newest = valid.max(by: { $0.generation < $1.generation })
        if let newest, newest.kind == .checkpoint {
            guard let wire = newest.checkpoint else {
                throw ObservedPowerEnvelopeCheckpointStoreError.corruptedCheckpoint
            }
            let retained = try checkpoint(
                from: wire,
                requiredScopeAuthority: requiredScopeAuthority,
                requiredEvidenceAuthority: requiredEvidenceAuthority
            )
            switch try replacementDecision(existing: retained, incoming: checkpoint) {
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
        let envelope = Envelope.checkpoint(generation: generation, checkpoint: checkpoint)
        let destination = destinationURL(slotA: a, slotB: b)
        try writeAndVerify(envelope, to: destination)
        return .stored(generation: generation)
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

        switch (older.kind, newer.kind) {
        case (.checkpoint, .checkpoint):
            guard let olderWire = older.checkpoint,
                  let newerWire = newer.checkpoint else {
                throw ObservedPowerEnvelopeCheckpointStoreError.corruptedCheckpoint
            }
            let olderCheckpoint = try validatedCheckpoint(from: olderWire)
            let newerCheckpoint = try validatedCheckpoint(from: newerWire)
            try validateSameBinding(olderCheckpoint, newerCheckpoint)

            if olderCheckpoint == newerCheckpoint {
                return
            }
            let requiredRaisedCeiling = olderCheckpoint.learnedObservedCeilingWatts
                * (1 + olderCheckpoint.policy.upwardHysteresisFraction)
            guard requiredRaisedCeiling.isFinite else {
                throw ObservedPowerEnvelopeCheckpointStoreError.reconciliationThresholdOverflow
            }
            guard newerCheckpoint.learnedObservedCeilingWatts > requiredRaisedCeiling else {
                throw ObservedPowerEnvelopeCheckpointStoreError.invalidCalibrationProgression
            }

        case (.checkpoint, .cleared),
             (.cleared, .checkpoint),
             (.cleared, .cleared):
            // A newer clear releases the old binding; a newer checkpoint after a
            // clear is a legitimate explicit rebind and starts a new progression.
            return
        }
    }

    private func simulatorCheckpoint(
        from wire: StoredCheckpointWire
    ) throws -> ObservedPowerEnvelopeCalibrationCheckpoint {
        do {
            let data = try encoder.encode(wire)
            return try decoder.decode(
                ObservedPowerEnvelopeCalibrationCheckpoint.self,
                from: data
            )
        } catch let error as ObservedPowerEnvelopeCheckpointError {
            throw mapCheckpointError(error)
        } catch {
            throw ObservedPowerEnvelopeCheckpointStoreError.corruptedCheckpoint
        }
    }

#if SWIFT_PACKAGE
    private func verifiedCheckpoint(
        from wire: StoredCheckpointWire
    ) throws -> ObservedPowerEnvelopeCalibrationCheckpoint {
        guard let identityAuthority = ObservedPowerEnvelopeScopeAuthority(
            rawValue: wire.identityAuthority
        ), let evidenceAuthority = ObservedPowerEnvelopeEvidenceAuthority(
            rawValue: wire.evidenceAuthority
        ) else {
            throw ObservedPowerEnvelopeCheckpointStoreError.authorityMismatch
        }

        do {
            return try ObservedPowerEnvelopeCalibrationCheckpoint.verifiedStoredFields(
                schemaVersion: wire.schemaVersion,
                vehicleIdentityKey: wire.vehicleIdentityKey,
                confirmedModeKey: wire.confirmedModeKey,
                identityAuthority: identityAuthority,
                evidenceAuthority: evidenceAuthority,
                policy: wire.policy,
                learnedObservedCeilingWatts: wire.learnedObservedCeilingWatts,
                learningSampleCount: wire.learningSampleCount,
                upperBandSupportCount: wire.upperBandSupportCount
            )
        } catch let error as ObservedPowerEnvelopeCheckpointError {
            throw mapCheckpointError(error)
        }
    }
#endif

    private func validatedCheckpoint(
        from wire: StoredCheckpointWire
    ) throws -> ObservedPowerEnvelopeCalibrationCheckpoint {
        if wire.identityAuthority == ObservedPowerEnvelopeScopeAuthority.simulatorQA.rawValue,
           wire.evidenceAuthority == ObservedPowerEnvelopeEvidenceAuthority.simulatorQA.rawValue {
            return try simulatorCheckpoint(from: wire)
        }

#if SWIFT_PACKAGE
        if wire.identityAuthority
                == ObservedPowerEnvelopeScopeAuthority.verifiedVehicleIdentity.rawValue,
           wire.evidenceAuthority
                == ObservedPowerEnvelopeEvidenceAuthority.verifiedVehicleMeasurement.rawValue {
            return try verifiedCheckpoint(from: wire)
        }
#endif

        throw ObservedPowerEnvelopeCheckpointStoreError.authorityMismatch
    }

    private func checkpoint(
        from wire: StoredCheckpointWire,
        requiredScopeAuthority: ObservedPowerEnvelopeScopeAuthority,
        requiredEvidenceAuthority: ObservedPowerEnvelopeEvidenceAuthority
    ) throws -> ObservedPowerEnvelopeCalibrationCheckpoint {
        let checkpoint = try validatedCheckpoint(from: wire)
        guard checkpoint.identityAuthority == requiredScopeAuthority,
              checkpoint.evidenceAuthority == requiredEvidenceAuthority else {
            throw ObservedPowerEnvelopeCheckpointStoreError.authorityMismatch
        }
        return checkpoint
    }

    private func mapCheckpointError(
        _ error: ObservedPowerEnvelopeCheckpointError
    ) -> ObservedPowerEnvelopeCheckpointStoreError {
        switch error {
        case .authorityMismatch:
            .authorityMismatch
        case .unsupportedSchemaVersion(let version):
            .unsupportedCheckpointSchema(version)
        case .scopeMismatch:
            .scopeMismatch
        case .policyMismatch:
            .policyMismatch
        default:
            .corruptedCheckpoint
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

            let probe = try decoder.decode(RecordProbe.self, from: data)
            if probe.kind == .checkpoint {
                guard let checkpointProbe = probe.checkpoint else {
                    return .corrupt
                }
                guard checkpointProbe.schemaVersion
                        == ObservedPowerEnvelopeCalibrationCheckpoint.currentSchemaVersion else {
                    return .unsupportedCheckpointSchema(checkpointProbe.schemaVersion)
                }
            } else if probe.checkpoint != nil {
                return .corrupt
            }

            let envelope = try decoder.decode(Envelope.self, from: data)
            switch envelope.kind {
            case .checkpoint:
                guard let wire = envelope.checkpoint else { return .corrupt }
                _ = try validatedCheckpoint(from: wire)
            case .cleared:
                guard envelope.checkpoint == nil else { return .corrupt }
            }
            return .valid(envelope)
        } catch let error as ObservedPowerEnvelopeCheckpointStoreError {
            switch error {
            case .unsupportedCheckpointSchema(let version):
                return .unsupportedCheckpointSchema(version)
            default:
                return .corrupt
            }
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
        switch (slotA.envelope, slotB.envelope) {
        case (nil, nil):
            if slotA.isInvalidOrMissing, slotB.isInvalidOrMissing {
                return slotA.isCorrupt ? slotBURL : slotAURL
            }
            return slotAURL
        case (nil, .some):
            return slotAURL
        case (.some, nil):
            return slotBURL
        case let (.some(a), .some(b)):
            return a.generation <= b.generation ? slotAURL : slotBURL
        }
    }

    private func firstClearTarget(slotA: SlotRead, slotB: SlotRead) -> URL {
        if slotA.isInvalidOrMissing { return slotAURL }
        if slotB.isInvalidOrMissing { return slotBURL }

        guard let a = slotA.envelope, let b = slotB.envelope else {
            return slotAURL
        }
        return a.generation <= b.generation ? slotAURL : slotBURL
    }

    private func writeAndVerify(_ envelope: Envelope, to destination: URL) throws {
        let data = try encoder.encode(envelope)
        try data.write(to: destination, options: Data.WritingOptions.atomic)

        guard case let .valid(verified) = try readSlot(at: destination),
              verified == envelope else {
            throw ObservedPowerEnvelopeCheckpointStoreError.corruptedCheckpoint
        }
    }
}
