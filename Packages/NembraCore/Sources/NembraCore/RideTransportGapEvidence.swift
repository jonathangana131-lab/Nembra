import Foundation

/// Durable provenance describing what Nembra can truthfully say about scooter
/// transport continuity during one confirmed ride.
///
/// This is intentionally tri-state. A process/relaunch gap can make previous
/// "no disconnect observed" evidence incomplete even when no Bluetooth
/// disconnect packet/state transition was actually witnessed.
public enum RideTransportGapEvidence: String, Codable, Equatable, Sendable {
    /// Nembra cannot prove whether a scooter transport gap occurred across all
    /// of the ride evidence available to this process/history record.
    case unknown

    /// Nembra continuously observed the confirmed ride interval represented by
    /// the current process evidence and did not observe a scooter disconnect.
    case noneObserved

    /// At least one scooter transport disconnect was directly observed after
    /// ride confirmation. Once observed, this evidence is never downgraded.
    case observed

    /// Process recovery itself is not evidence that Bluetooth disconnected.
    /// However, an unobserved process interval means a previous `noneObserved`
    /// claim can no longer cover the whole ride. Directly observed gaps survive.
    var afterProcessRecovery: RideTransportGapEvidence {
        switch self {
        case .observed:
            return .observed
        case .noneObserved, .unknown:
            return .unknown
        }
    }
}
