import Foundation

/// Durable provenance describing what Nembra can truthfully say about scooter
/// transport continuity during one confirmed ride.
///
/// This is intentionally tri-state. It records observed disconnect evidence and
/// known observation-coverage loss; it never claims that Bluetooth was
/// continuously healthy merely because no disconnect state was received.
public enum RideTransportGapEvidence: String, Codable, Equatable, Sendable {
    /// Nembra cannot classify the whole ride's transport-gap history because
    /// required provenance is legacy/missing or a known process interval was
    /// not observed.
    case unknown

    /// Among scooter transport states Nembra actually received for this
    /// uninterrupted current-process ride, no disconnected state was observed.
    /// This does not assert packet cadence or complete BLE notification coverage.
    case noneObserved

    /// At least one scooter transport disconnect was directly observed after
    /// ride confirmation. Once observed, this evidence is never downgraded.
    case observed

    /// Process recovery itself is not evidence that Bluetooth disconnected.
    /// However, an unobserved process interval means a previous `noneObserved`
    /// classification can no longer cover the whole ride. Direct evidence stays.
    var afterProcessRecovery: RideTransportGapEvidence {
        switch self {
        case .observed:
            return .observed
        case .noneObserved, .unknown:
            return .unknown
        }
    }
}
