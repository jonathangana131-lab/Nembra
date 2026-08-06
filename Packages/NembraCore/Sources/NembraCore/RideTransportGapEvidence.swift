import Foundation

/// Durable provenance describing what Nembra can truthfully say about scooter
/// transport continuity during one confirmed ride.
///
/// This is intentionally tri-state. It records observed non-connected vehicle
/// transport states and known observation-coverage loss; it never claims that
/// Bluetooth was continuously healthy merely because no gap state was received.
public enum RideTransportGapEvidence: String, Codable, Equatable, Sendable {
    /// Nembra cannot classify the whole ride's transport-gap history because
    /// required provenance is legacy/missing or a known process interval was
    /// not observed.
    case unknown

    /// Among vehicle transport states Nembra actually received for this
    /// uninterrupted current-process ride, every post-confirmation state was
    /// `.connected`; no `.disconnected`, `.connecting`, or `.reconnecting` state
    /// was observed. This does not assert packet cadence or complete Bluetooth
    /// notification/state-observation coverage.
    case noneObserved

    /// At least one post-confirmation vehicle transport state was observed while
    /// it was not `.connected` (`.disconnected`, `.connecting`, or
    /// `.reconnecting`). Once observed, this evidence is never downgraded.
    case observed

    /// Process recovery itself is not a vehicle transport-state observation.
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
