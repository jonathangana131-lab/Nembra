public enum BatteryEvidenceSnapshotError: Error, Equatable, Sendable {
    case stream(BatteryEvidenceStreamValidationError)
    case conflictingSameUptimeFieldEvidence
}

/// Latest normalized battery observations that are known to belong to the same
/// uninterrupted evidence segment.
///
/// This is current-process state, not durable telemetry history. A continuity boundary
/// clears prior fields so a fresh post-gap SoC cannot be presented as synchronous with
/// stale pre-gap voltage/current/power evidence.
public struct BatteryEvidenceCurrentSegmentSnapshot: Equatable, Sendable {
    public let observationsByField: [BatteryEvidenceField: BatteryEvidenceObservation]

    /// Raw snapshot construction stays inside NembraCore. External consumers receive
    /// snapshots only from `BatteryEvidenceSnapshotAccumulator.currentSnapshot`, so they
    /// cannot bypass stream ordering/continuity by assembling arbitrary field mixtures.
    init(observationsByField: [BatteryEvidenceField: BatteryEvidenceObservation]) {
        self.observationsByField = observationsByField
    }

    public var isEmpty: Bool {
        observationsByField.isEmpty
    }

    public subscript(field: BatteryEvidenceField) -> BatteryEvidenceObservation? {
        observationsByField[field]
    }
}

/// Stateful, process-local accumulator for a coherent latest battery evidence segment.
///
/// The accumulator composes `BatteryEvidenceStreamValidator` with per-field latest-value
/// retention. It does not decode protocol bytes, choose evidence roles, infer gaps from
/// timing thresholds, or promote any observation into verified hardware truth.
public struct BatteryEvidenceSnapshotAccumulator: Equatable, Sendable {
    private var streamValidator: BatteryEvidenceStreamValidator
    private var latestByField: [BatteryEvidenceField: BatteryEvidenceObservation]

    /// Receipt uptime of the currently open post-gap boundary batch. Multiple normalized
    /// fields from one first post-gap callback may all legitimately inherit the explicit
    /// continuity boundary. They are one segment reset, not repeated resets.
    ///
    /// The batch closes as soon as accepted evidence advances to a greater uptime. A
    /// later explicit boundary then starts a new segment. `markUnobservedInterval()` also
    /// closes any open batch explicitly.
    private var boundaryBatchUptimeNanoseconds: UInt64?

    public init() {
        streamValidator = BatteryEvidenceStreamValidator()
        latestByField = [:]
        boundaryBatchUptimeNanoseconds = nil
    }

    public var currentSnapshot: BatteryEvidenceCurrentSegmentSnapshot {
        BatteryEvidenceCurrentSegmentSnapshot(observationsByField: latestByField)
    }

    public var lastAcceptedUptimeNanoseconds: UInt64? {
        streamValidator.lastAcceptedUptimeNanoseconds
    }

    public var requiresContinuityBoundary: Bool {
        streamValidator.requiresContinuityBoundary
    }

    /// Immediately invalidates the current live segment when a higher layer knows
    /// evidence continuity was lost. Retained/history presentation belongs elsewhere.
    public mutating func markUnobservedInterval() {
        streamValidator.markUnobservedInterval()
        latestByField.removeAll(keepingCapacity: true)
        boundaryBatchUptimeNanoseconds = nil
    }

    /// Validates and atomically incorporates one observation into the current segment.
    public mutating func ingest(_ observation: BatteryEvidenceObservation) throws {
        // Exact same-field/same-uptime evidence is globally idempotent. Check this before
        // touching the stream validator: replaying an old accepted boundary after newer
        // fields arrived must not rewind the process-local ordering baseline. A caller
        // that actually knows a new gap occurred uses `markUnobservedInterval()`, which
        // clears the old snapshot and therefore removes this duplicate ambiguity.
        if let existing = latestByField[observation.value.field],
           existing.receivedAtUptimeNanoseconds == observation.receivedAtUptimeNanoseconds {
            guard existing == observation else {
                throw BatteryEvidenceSnapshotError.conflictingSameUptimeFieldEvidence
            }
            return
        }

        var candidateValidator = streamValidator
        do {
            try candidateValidator.accept(observation)
        } catch let error as BatteryEvidenceStreamValidationError {
            throw BatteryEvidenceSnapshotError.stream(error)
        }

        var candidateLatest = latestByField
        var candidateBoundaryBatchUptime = boundaryBatchUptimeNanoseconds

        // Once evidence advances beyond the boundary receipt uptime, later explicit
        // boundaries are new segment boundaries even if their new uptime epoch is lower.
        if let boundaryUptime = candidateBoundaryBatchUptime,
           observation.receivedAtUptimeNanoseconds > boundaryUptime {
            candidateBoundaryBatchUptime = nil
        }

        if observation.continuity == .afterUnobservedInterval {
            if candidateBoundaryBatchUptime != observation.receivedAtUptimeNanoseconds {
                candidateLatest.removeAll(keepingCapacity: true)
                candidateBoundaryBatchUptime = observation.receivedAtUptimeNanoseconds
            }
        }

        candidateLatest[observation.value.field] = observation
        streamValidator = candidateValidator
        latestByField = candidateLatest
        boundaryBatchUptimeNanoseconds = candidateBoundaryBatchUptime
    }
}
