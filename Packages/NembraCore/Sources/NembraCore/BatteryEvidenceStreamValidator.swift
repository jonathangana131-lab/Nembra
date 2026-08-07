public enum BatteryEvidenceStreamValidationError: Error, Equatable, Sendable {
    case nonMonotonicUptime
    case missingContinuityBoundary
}

/// Process-local ordering guard for normalized battery evidence.
///
/// `receivedAtUptimeNanoseconds` is ordering evidence only inside one process/boot uptime
/// epoch. Wall-clock dates are deliberately ignored for ordering because the system clock
/// can move. Equal uptimes are allowed because one transport callback may legitimately
/// produce several normalized semantic fields from the same received packet.
///
/// An explicit `.afterUnobservedInterval` observation starts a fresh continuity segment,
/// but it does not switch an existing validator into a different uptime epoch. A process
/// relaunch must create a fresh validator. Keeping that boundary prevents old pre-gap
/// observations with numerically larger uptimes from being re-admitted after a lower-uptime
/// reset and masquerading as current-segment evidence.
///
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
    /// The existing process-local uptime baseline is intentionally retained. Disconnects,
    /// missed callbacks, and other continuity gaps do not reset system uptime. Retaining the
    /// baseline prevents delayed pre-gap evidence from being accepted after the boundary.
    /// A true process relaunch starts with a new validator instead of reusing this state.
    public mutating func markUnobservedInterval() {
        requiresContinuityBoundary = true
    }

    /// Validates process-local ordering and advances the ordering baseline atomically.
    ///
    /// This method never promotes `BatteryEvidenceRole`, changes semantic values, or
    /// decides whether an observation is suitable for adaptive-range learning.
    public mutating func accept(_ observation: BatteryEvidenceObservation) throws {
        if observation.continuity == .afterUnobservedInterval {
            if let lastAcceptedUptimeNanoseconds,
               observation.receivedAtUptimeNanoseconds < lastAcceptedUptimeNanoseconds {
                throw BatteryEvidenceStreamValidationError.nonMonotonicUptime
            }

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
