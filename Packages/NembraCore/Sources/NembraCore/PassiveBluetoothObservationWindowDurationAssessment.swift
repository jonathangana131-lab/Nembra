/// Duration-only assessment of immutable passive-capture observation boundaries.
///
/// This type answers one deliberately narrow question: did Nembra preserve at
/// least the caller-required amount of monotonic observation time between the
/// latest accepted finite-acquisition-ready boundary and the terminal
/// observation horizon?
///
/// A sufficient result is Nembra lifecycle-duration evidence only. It does not
/// prove continuous BLE traffic, RF emission, foreground authority, target
/// identity, scooter health/state, protocol semantics, or physical hardware
/// behavior. Those remain separate acceptance gates.
public struct PassiveBluetoothObservationWindowDurationAssessment: Equatable, Sendable {
    public enum Status: String, Equatable, Sendable {
        case sufficient
        case invalidMinimumDuration
        case missingFiniteAcquisitionReady
        case missingObservationHorizon
        case horizonPrecedesReady
        case insufficientDuration
    }

    public let status: Status
    public let minimumRequiredDurationNanoseconds: UInt64
    public let observedDurationNanoseconds: UInt64?
    public let readyBoundary: PassiveBluetoothObservationBoundary?
    public let horizonBoundary: PassiveBluetoothObservationBoundary?

    /// Convenience only; the assessment itself remains duration evidence rather
    /// than a declaration that the wider capture experiment is healthy/valid.
    public var isSufficient: Bool {
        status == .sufficient
    }

    private init(
        status: Status,
        minimumRequiredDurationNanoseconds: UInt64,
        observedDurationNanoseconds: UInt64?,
        readyBoundary: PassiveBluetoothObservationBoundary?,
        horizonBoundary: PassiveBluetoothObservationBoundary?
    ) {
        self.status = status
        self.minimumRequiredDurationNanoseconds = minimumRequiredDurationNanoseconds
        self.observedDurationNanoseconds = observedDurationNanoseconds
        self.readyBoundary = readyBoundary
        self.horizonBoundary = horizonBoundary
    }

    /// Assesses a caller-defined minimum using only the capture's monotonic
    /// uptime evidence. Wall-clock `Date` values are intentionally ignored.
    ///
    /// If multiple finite-acquisition-ready boundaries exist, the latest one is
    /// authoritative for this duration calculation. This is conservative: a
    /// repeated ready transition resets the duration window instead of allowing
    /// an older/stale ready boundary to make a short final window appear long.
    ///
    /// A zero minimum fails closed so an accidentally unconfigured product gate
    /// cannot silently accept an empty observation window.
    public static func assess(
        session: PassiveBluetoothCaptureSession,
        minimumDurationNanoseconds: UInt64
    ) -> Self {
        let readyBoundary = session.observationBoundaries.last {
            $0.kind == .finiteAcquisitionReady
        }
        let horizonBoundary = session.observationBoundaries.last {
            $0.kind == .observationHorizon
        }

        guard minimumDurationNanoseconds > 0 else {
            return Self(
                status: .invalidMinimumDuration,
                minimumRequiredDurationNanoseconds: minimumDurationNanoseconds,
                observedDurationNanoseconds: nil,
                readyBoundary: readyBoundary,
                horizonBoundary: horizonBoundary
            )
        }

        guard let readyBoundary else {
            return Self(
                status: .missingFiniteAcquisitionReady,
                minimumRequiredDurationNanoseconds: minimumDurationNanoseconds,
                observedDurationNanoseconds: nil,
                readyBoundary: nil,
                horizonBoundary: horizonBoundary
            )
        }

        guard let horizonBoundary else {
            return Self(
                status: .missingObservationHorizon,
                minimumRequiredDurationNanoseconds: minimumDurationNanoseconds,
                observedDurationNanoseconds: nil,
                readyBoundary: readyBoundary,
                horizonBoundary: nil
            )
        }

        guard horizonBoundary.observedAtUptimeNanoseconds >= readyBoundary.observedAtUptimeNanoseconds else {
            return Self(
                status: .horizonPrecedesReady,
                minimumRequiredDurationNanoseconds: minimumDurationNanoseconds,
                observedDurationNanoseconds: nil,
                readyBoundary: readyBoundary,
                horizonBoundary: horizonBoundary
            )
        }

        let observedDurationNanoseconds =
            horizonBoundary.observedAtUptimeNanoseconds - readyBoundary.observedAtUptimeNanoseconds
        let status: Status = observedDurationNanoseconds >= minimumDurationNanoseconds
            ? .sufficient
            : .insufficientDuration

        return Self(
            status: status,
            minimumRequiredDurationNanoseconds: minimumDurationNanoseconds,
            observedDurationNanoseconds: observedDurationNanoseconds,
            readyBoundary: readyBoundary,
            horizonBoundary: horizonBoundary
        )
    }
}
