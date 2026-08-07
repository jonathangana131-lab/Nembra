import Foundation

/// Field-specific speed evidence used to decide whether controls that are safe
/// only while stopped may be exposed.
///
/// This deliberately does not derive freshness from `VehicleState`'s aggregate
/// `dataAvailability`: another live vehicle field cannot make an old speed value
/// current. Display interpolation and short-horizon estimates also do not belong
/// here. The caller must classify the latest accepted speed evidence before
/// asking for stopped-only control eligibility.
public enum StoppedControlSpeedEvidence: Equatable, Sendable {
    /// No current or retained speed value is available.
    case unavailable
    /// A previously accepted speed value exists, but it is not current evidence.
    case retained(kilometersPerHour: Double)
    /// Current accepted absolute speed evidence for the active vehicle session.
    case liveAuthoritative(kilometersPerHour: Double)
}

public enum StoppedOnlyControlPolicyError: Error, Equatable, Sendable {
    case invalidStoppedThreshold
}

/// Why current evidence cannot prove the vehicle is stopped.
public enum StoppedControlUnavailabilityReason: Equatable, Sendable {
    /// Stopped-only controls require the active vehicle session to be connected.
    case vehicleNotConnected(VehicleConnectionState)
    /// No speed evidence is available for the active session.
    case speedUnavailable
    /// A speed value exists, but it is retained/stale and cannot prove a stop.
    case speedRetained
    /// A malformed value reached this boundary. Fail closed rather than treating
    /// it as zero or manufacturing a safe stopped state.
    case invalidLiveSpeedEvidence
}

/// Product-facing motion state for stopped-only controls.
///
/// `confirmedStopped` is intentionally narrower than "not moving": it requires
/// a connected session and current accepted absolute speed evidence below the
/// caller-supplied product threshold. `notProvenStopped` keeps unavailable or
/// stale evidence distinct from a measured moving state.
public enum StoppedControlMotionState: Equatable, Sendable {
    case confirmedStopped(kilometersPerHour: Double)
    case moving(kilometersPerHour: Double)
    case notProvenStopped(StoppedControlUnavailabilityReason)

    public var permitsStoppedOnlyControls: Bool {
        if case .confirmedStopped = self {
            return true
        }
        return false
    }
}

/// Fail-closed eligibility policy for controls that should appear only after a
/// legitimate current speed measurement proves the vehicle is stopped.
///
/// No ES80 cadence, freshness interval, resolution, or physical stop threshold
/// is guessed here. The stopped threshold is injected by the product layer, and
/// field-specific currentness must be established before constructing
/// `.liveAuthoritative` evidence.
public struct StoppedOnlyControlPolicy: Equatable, Sendable {
    public let stoppedThresholdKilometersPerHour: Double

    public init(stoppedThresholdKilometersPerHour: Double) throws {
        guard stoppedThresholdKilometersPerHour.isFinite,
              stoppedThresholdKilometersPerHour > 0 else {
            throw StoppedOnlyControlPolicyError.invalidStoppedThreshold
        }
        self.stoppedThresholdKilometersPerHour = stoppedThresholdKilometersPerHour
    }

    public func motionState(
        connection: VehicleConnectionState,
        speedEvidence: StoppedControlSpeedEvidence
    ) -> StoppedControlMotionState {
        guard connection == .connected else {
            return .notProvenStopped(.vehicleNotConnected(connection))
        }

        switch speedEvidence {
        case .unavailable:
            return .notProvenStopped(.speedUnavailable)

        case .retained:
            return .notProvenStopped(.speedRetained)

        case let .liveAuthoritative(kilometersPerHour):
            guard kilometersPerHour.isFinite, kilometersPerHour >= 0 else {
                return .notProvenStopped(.invalidLiveSpeedEvidence)
            }

            if kilometersPerHour < stoppedThresholdKilometersPerHour {
                return .confirmedStopped(kilometersPerHour: kilometersPerHour)
            }
            return .moving(kilometersPerHour: kilometersPerHour)
        }
    }
}
