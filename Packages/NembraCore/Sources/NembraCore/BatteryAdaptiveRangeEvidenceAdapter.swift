/// One truth-preserving action produced when normalized battery evidence is
/// considered for the adaptive percentage-based range domain.
///
/// The adapter is intentionally action-oriented so a caller cannot accidentally
/// discard a known continuity break merely because the first resumed battery
/// field is non-SoC or carries a non-authoritative truth role.
public enum BatteryAdaptiveRangeEvidenceAction: Equatable, Sendable {
    /// This continuous observation must not affect production adaptive-range learning.
    case ignore

    /// Battery evidence resumed after an interval Nembra did not observe. Any
    /// in-flight range-learning anchor/window must be discarded before later
    /// authoritative SoC evidence is accepted.
    case resetContinuity

    /// A continuous, physically verified vehicle SoC reading that is eligible
    /// to enter the adaptive-range domain. Model/window policy still decides
    /// whether it can actually teach efficiency.
    case ingestSOC(BatterySOCReading)

    /// The first verified vehicle SoC after an unobserved interval. The caller
    /// must reset in-flight continuity first, then ingest this reading as the
    /// new clean anchor/evidence point.
    case resetContinuityAndIngestSOC(BatterySOCReading)
}

/// Pure semantic bridge from the strict battery-evidence truth boundary into
/// the adaptive-range SoC domain.
///
/// Continuity is evidence about observation coverage, not about whether the
/// numeric value is authoritative. Therefore every explicit
/// `.afterUnobservedInterval` boundary resets in-flight range learning, while
/// only a verified vehicle SoC value is ever promoted to authoritative SoC.
public enum BatteryAdaptiveRangeEvidenceAdapter {
    public static func action(
        for observation: BatteryEvidenceObservation
    ) throws -> BatteryAdaptiveRangeEvidenceAction {
        let requiresReset = observation.requiresNewContinuityAnchor

        guard observation.isAuthoritativeVehicleMeasurement else {
            // A stock-app/simulation/estimate/presentation value still cannot
            // train range. However, if the evidence stream explicitly says an
            // interval was unobserved, that known gap must close any in-flight
            // learning span so later verified SoC cannot bridge across it.
            return requiresReset ? .resetContinuity : .ignore
        }

        guard observation.value.field == .stateOfChargePercent else {
            // Verified voltage/current/power/charging evidence does not teach
            // percentage-based efficiency, but an explicit first-post-gap
            // marker still resets the range-learning continuity boundary.
            return requiresReset ? .resetContinuity : .ignore
        }

        guard let percentage = observation.value.numericValue else {
            // BatterySemanticValue normally makes this state impossible, and its
            // Codable path revalidates the same invariant. Keep the bridge
            // fail-closed if that upstream contract ever changes.
            throw BatteryEvidenceValidationError.invalidSemanticValue
        }

        let reading = try BatterySOCReading(
            percentage: percentage,
            provenance: .authoritativeMeasurement,
            receivedAtUptimeNanoseconds: observation.receivedAtUptimeNanoseconds
        )

        return requiresReset
            ? .resetContinuityAndIngestSOC(reading)
            : .ingestSOC(reading)
    }
}

/// Stateful entry point that enforces the battery evidence stream's ordering
/// contract before returning an adaptive-range action.
///
/// Higher layers should prefer this type over calling the pure adapter directly
/// when consuming a live/persisted sequence. The stream validator and semantic
/// action advance atomically: an ordering/continuity validation failure never
/// mutates the accepted-stream baseline and never returns an ingest action.
public struct BatteryAdaptiveRangeEvidenceBridge: Equatable, Sendable {
    public private(set) var streamValidator: BatteryEvidenceStreamValidator

    public init(streamValidator: BatteryEvidenceStreamValidator = .init()) {
        self.streamValidator = streamValidator
    }

    /// Records that evidence was missed before the next observation arrives.
    /// The next observation must carry `.afterUnobservedInterval` or stream
    /// validation fails closed.
    public mutating func markUnobservedInterval() {
        streamValidator.markUnobservedInterval()
    }

    public mutating func accept(
        _ observation: BatteryEvidenceObservation
    ) throws -> BatteryAdaptiveRangeEvidenceAction {
        let action = try BatteryAdaptiveRangeEvidenceAdapter.action(for: observation)

        var candidateValidator = streamValidator
        try candidateValidator.accept(observation)
        streamValidator = candidateValidator

        return action
    }
}
