import Foundation

/// Product-facing meaning of ride-duration evidence in the live cockpit.
///
/// `elapsedObserved` is available only when observation coverage is complete from
/// the ride/session boundary. `partialObserved` means Nembra can truthfully show
/// how much time it actually observed, but must not present that value as the
/// ride's complete elapsed duration.
public enum RideDurationCockpitDisplayRole: Equatable, Sendable {
    case elapsedObserved
    case partialObserved
}

/// A truth-preserving duration value suitable for a cockpit readout.
///
/// This is presentation state, not telemetry evidence. It deliberately keeps the
/// exact accepted observed nanoseconds beside a whole-second rendering value so
/// UI formatting never has to reconstruct or round-trip measurement evidence.
/// No wall-clock timestamp or display clock participates in this projection.
public struct RideDurationCockpitValue: Equatable, Sendable {
    public let sessionID: UUID
    public let observedDurationNanoseconds: UInt64
    public let wholeObservedSeconds: UInt64
    public let observationSegmentCount: Int
    public let role: RideDurationCockpitDisplayRole

    private init(
        sessionID: UUID,
        observedDurationNanoseconds: UInt64,
        observationSegmentCount: Int,
        role: RideDurationCockpitDisplayRole
    ) {
        self.sessionID = sessionID
        self.observedDurationNanoseconds = observedDurationNanoseconds
        self.wholeObservedSeconds = observedDurationNanoseconds / 1_000_000_000
        self.observationSegmentCount = observationSegmentCount
        self.role = role
    }
}

/// Fail-closed primary presentation state for live ride duration.
///
/// Unknown or structurally contradictory evidence remains unavailable instead of
/// becoming a synthetic `0:00`. A legitimate observed zero-duration segment is
/// preserved as a real zero value.
///
/// The projection never advances time on its own. Higher layers must provide a
/// newer accepted `RideSessionDurationEvidenceSnapshot` when more process-local
/// monotonic time has actually been observed. This prevents a 1 Hz/60 Hz display
/// timer from turning an app suspension, reconnect gap, or stale frame into ride
/// evidence.
public enum RideDurationCockpitState: Equatable, Sendable {
    case unavailable(sessionID: UUID)
    case observed(RideDurationCockpitValue)

    public init(snapshot: RideSessionDurationEvidenceSnapshot) {
        guard let duration = snapshot.observedDurationNanoseconds else {
            self = .unavailable(sessionID: snapshot.sessionID)
            return
        }

        let role: RideDurationCockpitDisplayRole
        switch snapshot.coverage {
        case .unknown:
            self = .unavailable(sessionID: snapshot.sessionID)
            return
        case .complete:
            // A legitimate duration accumulator can produce complete coverage
            // only from its first contiguous observation segment.
            guard snapshot.observationSegmentCount == 1 else {
                self = .unavailable(sessionID: snapshot.sessionID)
                return
            }
            role = .elapsedObserved
        case .partial:
            guard snapshot.observationSegmentCount > 0 else {
                self = .unavailable(sessionID: snapshot.sessionID)
                return
            }
            role = .partialObserved
        }

        self = .observed(
            RideDurationCockpitValue(
                sessionID: snapshot.sessionID,
                observedDurationNanoseconds: duration,
                observationSegmentCount: snapshot.observationSegmentCount,
                role: role
            )
        )
    }
}
