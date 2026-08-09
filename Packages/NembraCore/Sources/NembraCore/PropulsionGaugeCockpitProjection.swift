/// The accepted numeric power value that a cockpit may present as a measurement.
/// Construction is file-private so callers cannot relabel an interpolated render value as accepted evidence.
public struct PropulsionGaugeCockpitAcceptedMeasurement: Equatable, Sendable {
    /// Exact vehicle/mode identity of the display model that accepted this measurement.
    /// Detached cockpit values must stay bound to their source identity rather than relying on
    /// whichever vehicle happens to be current when a UI callback is later delivered.
    public let identity: PropulsionGaugeIdentity
    public let watts: Double
    public let receiptSequenceNumber: UInt64
    public let receivedAtUptimeNanoseconds: UInt64
    /// Source continuity/clock generation of this accepted measurement. A newer generation may
    /// legitimately restart receipt sequence and uptime, so detached measurements must preserve it.
    public let continuityGeneration: UInt64
    public let authority: PropulsionPowerSampleAuthority

    fileprivate init(
        identity: PropulsionGaugeIdentity,
        watts: Double,
        receiptSequenceNumber: UInt64,
        receivedAtUptimeNanoseconds: UInt64,
        continuityGeneration: UInt64,
        authority: PropulsionPowerSampleAuthority
    ) {
        self.identity = identity
        self.watts = watts
        self.receiptSequenceNumber = receiptSequenceNumber
        self.receivedAtUptimeNanoseconds = receivedAtUptimeNanoseconds
        self.continuityGeneration = continuityGeneration
        self.authority = authority
    }
}

/// Numeric cockpit truth is intentionally typed by currentness. `.retained` is last accepted
/// evidence, not a fresh measurement; `.unavailable` carries no primary numeric value.
public enum PropulsionGaugeCockpitMeasurement: Equatable, Sendable {
    case live(PropulsionGaugeCockpitAcceptedMeasurement)
    case retained(PropulsionGaugeCockpitAcceptedMeasurement)
    case unavailable
}

/// Cockpit-facing projection of the canonical propulsion gauge.
///
/// This type deliberately does not expose `displayWatts`. The band may move at display refresh rate,
/// while the numeric readout remains tied to an accepted measurement (or explicitly retained /
/// unavailable). Product semantics such as "near observed max" are intentionally owned by the separate
/// accepted-power observed-scale-region layer rather than duplicated here.
public struct PropulsionGaugeCockpitSnapshot: Equatable, Sendable {
    /// Exact vehicle/mode identity for this snapshot, including unavailable states.
    /// Keeping identity on the snapshot prevents an asynchronous/cached projection from becoming
    /// ordinary-looking state for a different selected vehicle or confirmed mode.
    public let identity: PropulsionGaugeIdentity
    public let measurement: PropulsionGaugeCockpitMeasurement

    /// Render-only position for the live propulsion band. Never telemetry evidence.
    public let visualPropulsionFraction: Double?
    /// Display-only target geometry derived directly from the accepted measurement plus the same
    /// compatible scale admitted by this frame. This is stable across 60 Hz interpolation and exists
    /// so Reduce Motion can snap to accepted-target presentation without reconstructing watts from
    /// moving geometry. It is still presentation state, never telemetry/evidence.
    public let acceptedTargetPropulsionFraction: Double?
    /// Render-only marker derived from accepted peak samples inside the canonical hold window.
    public let recentAcceptedPeakMarkerFraction: Double?
    /// The compatible presentation-scale origin admitted by the canonical gauge frame.
    /// This is presentation provenance only; it does not convert render fractions into measurements.
    public let scaleOrigin: PropulsionGaugeScaleOrigin?

    fileprivate init(
        identity: PropulsionGaugeIdentity,
        measurement: PropulsionGaugeCockpitMeasurement,
        visualPropulsionFraction: Double?,
        acceptedTargetPropulsionFraction: Double?,
        recentAcceptedPeakMarkerFraction: Double?,
        scaleOrigin: PropulsionGaugeScaleOrigin?
    ) {
        self.identity = identity
        self.measurement = measurement
        self.visualPropulsionFraction = visualPropulsionFraction
        self.acceptedTargetPropulsionFraction = acceptedTargetPropulsionFraction
        self.recentAcceptedPeakMarkerFraction = recentAcceptedPeakMarkerFraction
        self.scaleOrigin = scaleOrigin
    }
}

public extension PropulsionGaugeDisplayModel {
    /// Projects one cockpit snapshot while keeping accepted-measurement truth and display-clock motion separate.
    /// The canonical frame is evaluated exactly once per call so a 60 Hz cockpit does not duplicate
    /// interpolation work merely to recover the accepted numeric value.
    func cockpitSnapshot(
        atUptimeNanoseconds now: UInt64,
        scale: PropulsionGaugeScale?
    ) -> PropulsionGaugeCockpitSnapshot {
        let frame = frame(atUptimeNanoseconds: now, scale: scale)
        let measurement = cockpitMeasurement(from: frame)

        // A live/retained frame must carry complete accepted provenance. If it does not, fail the whole
        // cockpit surface closed rather than showing moving presentation state without accepted truth.
        guard measurement != .unavailable || frame.availability == .unavailable else {
            return PropulsionGaugeCockpitSnapshot(
                identity: frame.identity,
                measurement: .unavailable,
                visualPropulsionFraction: nil,
                acceptedTargetPropulsionFraction: nil,
                recentAcceptedPeakMarkerFraction: nil,
                scaleOrigin: nil
            )
        }

        guard frame.availability == .live else {
            return PropulsionGaugeCockpitSnapshot(
                identity: frame.identity,
                measurement: measurement,
                visualPropulsionFraction: nil,
                acceptedTargetPropulsionFraction: nil,
                recentAcceptedPeakMarkerFraction: nil,
                scaleOrigin: nil
            )
        }

        let acceptedTargetPropulsionFraction: Double?
        if let scale,
           let admittedScaleOrigin = frame.scaleOrigin,
           scale.identity == frame.identity,
           scale.origin == admittedScaleOrigin,
           case let .live(accepted) = measurement {
            acceptedTargetPropulsionFraction = min(1, max(0, accepted.watts / scale.ceilingWatts))
        } else {
            acceptedTargetPropulsionFraction = nil
        }

        return PropulsionGaugeCockpitSnapshot(
            identity: frame.identity,
            measurement: measurement,
            visualPropulsionFraction: frame.normalizedPropulsion,
            acceptedTargetPropulsionFraction: acceptedTargetPropulsionFraction,
            recentAcceptedPeakMarkerFraction: frame.acceptedPeakNormalized,
            scaleOrigin: frame.scaleOrigin
        )
    }

    private func cockpitMeasurement(
        from frame: PropulsionGaugeFrame
    ) -> PropulsionGaugeCockpitMeasurement {
        guard frame.availability != .unavailable,
              let watts = frame.latestAcceptedWatts,
              let receiptSequenceNumber = frame.latestAcceptedReceiptSequenceNumber,
              let receivedAtUptimeNanoseconds = frame.latestAcceptedUptimeNanoseconds,
              let continuityGeneration = frame.latestAcceptedContinuityGeneration,
              let authority = frame.latestAuthority else {
            return .unavailable
        }

        let accepted = PropulsionGaugeCockpitAcceptedMeasurement(
            identity: frame.identity,
            watts: watts,
            receiptSequenceNumber: receiptSequenceNumber,
            receivedAtUptimeNanoseconds: receivedAtUptimeNanoseconds,
            continuityGeneration: continuityGeneration,
            authority: authority
        )

        switch frame.availability {
        case .live:
            return .live(accepted)
        case .retained:
            return .retained(accepted)
        case .unavailable:
            return .unavailable
        }
    }
}