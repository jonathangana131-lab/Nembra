public enum BatteryEvidenceStreamValidationError: Error, Equatable, Sendable {
    case nonMonotonicUptime
    case missingContinuityBoundary
}

/// Process-local ordering guard for normalized battery evidence.
///
/// `receivedAtUptimeNanoseconds` is ordering evidence only inside one uptime epoch.
/// Wall-clock dates are deliberately ignored for ordering because the system clock can
/// move. Equal uptimes are allowed because one transport callback may legitimately
/// produce several normalized semantic fields from the same received packet.
///
/// An explicit `.afterUnobservedInterval` observation starts a fresh ordering baseline,
/// including after process relaunch where the new uptime epoch may be numerically lower.
/// Call `markUnobservedInterval()` when a higher layer knows evidence was missed before
/// the first post-gap observation arrives; that next observation must then carry the
/// explicit continuity boundary.
public struct BatteryEvidenceStreamValidator: Equatable, Sendable {
    public private(set) var lastAcceptedUptimeNanoseconds: UInt64?
    public private(set) var requiresContinuityBoundary: Bool

    public init() {
        lastAcceptedUptimeNanoseconds = nil
        requiresContinuityBoundary = false
    }

    /// Records that battery evidence continuity is no longer known.
    ///
    /// The old uptime baseline is intentionally discarded. Uptime values from another
    /// process/boot epoch must never be compared as though they shared one clock.
    public mutating func markUnobservedInterval() {
        lastAcceptedUptimeNanoseconds = nil
        requiresContinuityBoundary = true
    }

    /// Validates process-local ordering and advances the ordering baseline atomically.
    ///
    /// This method never promotes `BatteryEvidenceRole`, changes semantic values, or
    /// decides whether an observation is suitable for adaptive-range learning.
    public mutating func accept(_ observation: BatteryEvidenceObservation) throws {
        if observation.continuity == .afterUnobservedInterval {
            lastAcceptedUptimeNanoseconds = observation.receivedAtUptimeNanoseconds
            requiresContinuityBoundary = false
            return
        }

        guard !requiresContinuityBoundary else {
            throw BatteryEvidenceStreamValidationError.missingContinuityBoundary
        }

        if let lastAcceptedUptimeNanoseconds,
           observation.receivedAtUptimeNanoseconds < lastAcceptedUptimeNanoseconds {
            throw BatteryEvidenceStreamValidationError.nonMonotonicUptime
        }

        lastAcceptedUptimeNanoseconds = observation.receivedAtUptimeNanoseconds
    }
}
