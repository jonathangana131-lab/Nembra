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

    public init(observationsByField: [BatteryEvidenceField: BatteryEvidenceObservation]) {
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

    public init() {
        streamValidator = BatteryEvidenceStreamValidator()
        latestByField = [:]
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
    }

    /// Validates and atomically incorporates one observation into the current segment.
    public mutating func ingest(_ observation: BatteryEvidenceObservation) throws {
        var candidateValidator = streamValidator
        do {
            try candidateValidator.accept(observation)
        } catch let error as BatteryEvidenceStreamValidationError {
            throw BatteryEvidenceSnapshotError.stream(error)
        }

        var candidateLatest = latestByField

        if observation.continuity == .afterUnobservedInterval {
            candidateLatest.removeAll(keepingCapacity: true)
        }

        if let existing = candidateLatest[observation.value.field],
           existing.receivedAtUptimeNanoseconds == observation.receivedAtUptimeNanoseconds {
            guard existing == observation else {
                throw BatteryEvidenceSnapshotError.conflictingSameUptimeFieldEvidence
            }

            // Exact duplicate evidence is idempotent.
            streamValidator = candidateValidator
            latestByField = candidateLatest
            return
        }

        candidateLatest[observation.value.field] = observation
        streamValidator = candidateValidator
        latestByField = candidateLatest
    }
}
