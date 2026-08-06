/// One truth-preserving action produced when normalized battery evidence is
/// considered for the adaptive percentage-based range domain.
///
/// The adapter is intentionally action-oriented so a caller cannot accidentally
/// discard a verified continuity break merely because the first resumed battery
/// field was voltage/current/power instead of SoC.
public enum BatteryAdaptiveRangeEvidenceAction: Equatable, Sendable {
    /// This observation must not affect production adaptive-range learning.
    case ignore

    /// Verified vehicle battery evidence resumed after an interval Nembra did
    /// not observe. Any in-flight range-learning anchor/window must be discarded
    /// before later SoC evidence is accepted.
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

/// Bridges the strict battery-evidence truth boundary into the adaptive-range
/// SoC domain without promoting stock-app, Simulator, estimated, or display-only
/// values into measured scooter evidence.
public enum BatteryAdaptiveRangeEvidenceAdapter {
    public static func action(
        for observation: BatteryEvidenceObservation
    ) throws -> BatteryAdaptiveRangeEvidenceAction {
        // Only physically verified target-vehicle measurements are allowed to
        // influence production range learning or its evidence continuity.
        guard observation.isAuthoritativeVehicleMeasurement else {
            return .ignore
        }

        let requiresReset = observation.requiresNewContinuityAnchor

        guard observation.value.field == .stateOfChargePercent else {
            // A verified non-SoC field cannot teach percentage-based efficiency,
            // but its first-post-gap continuity marker is still important. If we
            // ignored it, a later continuous SoC could accidentally close a
            // learning window across an interval Nembra never observed.
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
